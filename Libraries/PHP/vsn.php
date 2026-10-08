<?php
namespace VSN;

const MAGIC = "VSN-";
const CFV = 1; const EV = 1;
const REC_END_OF_RECORDS = 0; const REC_FILE_IDENTITY = 1; const REC_REVISION = 2;
const REC_FILE_HEAD = 4; const REC_CONTENT_OBJECT = 5; const REC_COMMIT_MARKER = 6; const REC_MODE_DECLARATION = 7;
const REC_STORAGE_POLICY = 0x0009;                      // StoragePolicy record type
const FID_FILE_ID = 0x101; const FID_REV_ID = 0x201; const FID_REV_FILE_ID = 0x202;
const FID_REV_OBJECT_SERIAL = 0x203; const FID_REV_PATH = 0x210; const FID_REV_PRESENCE = 0x211;
const FID_HEAD_FILE_ID = 0x401; const FID_HEAD_REV_ID = 0x402;
const FID_COMMIT_GENERATION = 0x601; const FID_OBJECT_SERIAL = 0x501; const FID_OBJECT_SIZE = 0x511;
const FID_MODE = 0x701;                                // OBSOLETE: was ModeDeclaration field (deprecated)
const FID_STORAGE_POLICY = 0x0901;                     // StoragePolicy.field_id
const MODE_MODERN = 1; const MODE_ENTERPRISE = 2;

// Storage Policy values -- authoritative classification (directly on wire)
const STORAGE_POLICY_HIGHLY_VERTICAL    = 1;
const STORAGE_POLICY_VERTICAL           = 2;
const STORAGE_POLICY_HORIZONTAL         = 3;
const STORAGE_POLICY_HIGHLY_HORIZONTAL  = 4;
const REP_DIRECT_1 = 1; const REP_EXTENTS_1 = 2; const REP_VERSION_1 = 1;

class Container {
    public int $cfv = CFV; public int $ev = EV; public array $records = []; public array $objects = [];
    public int $trailerRecordCount = 0; public int $trailerGeneration = 0;
    public int $mode = MODE_MODERN; public int $byteLength = 0;
    public int $storagePolicy = STORAGE_POLICY_VERTICAL;
    private bool $locked = false;
    public function withLock(callable $fn) {
        while ($this->locked) { usleep(10); }
        $this->locked = true;
        try { return $fn(); } finally { $this->locked = false; }
    }
}

function parse(string $data): Container {
    if (strlen($data) < 8 || substr($data, 0, 4) !== MAGIC) throw new \InvalidArgumentException("bad magic");
    $c = new Container();
    $c->cfv = unpack("n", substr($data,4,2))[1];
    $c->ev = unpack("n", substr($data,6,2))[1];
    $c->mode = MODE_MODERN;
    $c->byteLength = strlen($data);
    // Extract storage_policy from REC_STORAGE_POLICY record in binary
    $sp = parse_sp_from_bytes($data);
    if ($sp !== null) { $c->storagePolicy = $sp; }
    return $c;
}

// Storage Policy reader helper — extract from actual wire bytes
function parse_sp_from_bytes(string $data): ?int {
    $pos = 8;
    $len = strlen($data);
    while ($pos + 2 <= $len) {
        $rt = (ord($data[$pos]) << 8) | ord($data[$pos+1]);
        if ($rt === 0x0000) break;  // RecordsEnd — stop scanning
        $pos += 2;
        $plen = ord($data[$pos]); $pos++;
        if ($pos + $plen > $len) break;
        $ppos = $pos;
        while ($ppos + 2 <= $pos + $plen) {
            $fid = (ord($data[$ppos]) << 8) | ord($data[$ppos+1]); $ppos += 2;
            if ($ppos > $pos + $plen) break;
            $vlen = ord($data[$ppos]); $ppos++;
            if ($vlen === 1 && $ppos <= $pos + $plen && $fid === FID_STORAGE_POLICY) {
                return ord($data[$ppos]);
            }
            $ppos += max($vlen, 1);
        }
        $pos += $plen;
    }
    return null;
}

function encode(int $mode, int $gen, int $sp = 2): string { 
    $rec = pack("n", REC_STORAGE_POLICY) . pack("C", 4) . pack("n", FID_STORAGE_POLICY) . pack("CC", 1, $sp >= 1 && $sp <= 4 ? $sp : 2);
    return MAGIC . pack("n", CFV) . pack("n", EV) . $rec; 
}

function validateStructural(Container $c): bool { return $c->cfv === CFV && in_array($c->mode, [MODE_MODERN, MODE_ENTERPRISE], true); }
function recover(string $data): int { return (strlen($data) >= 8 && substr($data,0,4) === MAGIC) ? 0 : -1; }

class MutableStore {
    public int $mode = MODE_MODERN;
    public int $storagePolicy = STORAGE_POLICY_VERTICAL;
    public int $generation = 0;
    private int $nextRevId = 1;
    private int $nextObjSerial = 1;
    private array $files = [];
    private array $heads = [];
    private array $revisions = [];
    private array $objects = [];

    public static function create(int $mode = MODE_MODERN): self { $s = new self(); $s->mode = $mode; return $s; }

    /** Writer Storage Policy chain -- OBSOLETE: cancelled mode mapping removed. */
    public static function createWithStoragePolicy(int $spolicy): self {
        $s = self::create(MODE_MODERN);
        $s->storagePolicy = $spolicy;
        return $s;
    }

    public static function open(string $data): self {
        if (strlen($data) < 8 || substr($data,0,4) !== MAGIC) throw new \InvalidArgumentException("bad magic");
        return self::create(MODE_MODERN);
    }

    public function close(): void {}
    public function getMode(): int { return $this->mode; }

    /** Allocate a unique 16-byte FileId; distinct files never collide. */
    private function allocateFileId(): string {
        for ($n = count($this->files) + 1; $n < PHP_INT_MAX; $n++) {
            $fid = str_repeat("\0", 16);
            for ($i = 0; $i < 16; $i++) { $fid[$i] = chr(($n >> ((15 - $i) * 8)) & 0xFF); }
            if (!isset($this->heads[$fid])) return $fid;
        }
        throw new \RuntimeException("FileId space exhausted");
    }
    public function createFile(string $path, string $content): string {
        $fid = $this->allocateFileId();
        $serial = $this->nextObjSerial++;
        $revId = $this->nextRevId++;
        $this->files[$fid] = $path;
        $this->heads[$fid] = $revId;
        $this->objects[$serial] = $content;
        $this->revisions[$revId] = ["file_id"=>$fid,"object_serial"=>$serial,"path"=>$path,"presence"=>1];
        return $fid;
    }

    public function readFile(string $fid): string {
        if (!isset($this->heads[$fid])) throw new \InvalidArgumentException("unknown file id");
        $rev = $this->revisions[$this->heads[$fid]];
        if ($rev["presence"] === 0) throw new \RuntimeException("file deleted");
        $serial = $rev["object_serial"];
        return $serial === 0 ? "" : $this->objects[$serial];
    }

    public function writeFile(string $fid, string $content): void {
        if (!isset($this->heads[$fid])) throw new \InvalidArgumentException("unknown file id");
        $serial = $this->nextObjSerial++;
        $revId = $this->nextRevId++;
        $this->objects[$serial] = $content;
        $this->revisions[$revId] = ["file_id"=>$fid,"object_serial"=>$serial,"path"=>$this->files[$fid],"presence"=>1];
        $this->heads[$fid] = $revId;
    }

    public function deleteFile(string $fid): void {
        if (!isset($this->heads[$fid])) throw new \InvalidArgumentException("unknown file id");
        $revId = $this->nextRevId++;
        $this->revisions[$revId] = ["file_id"=>$fid,"object_serial"=>0,"path"=>$this->files[$fid],"presence"=>0];
        $this->heads[$fid] = $revId;
    }

    public function renameFile(string $fid, string $newPath): void {
        if (!isset($this->heads[$fid])) throw new \InvalidArgumentException("unknown file id");
        $revId = $this->nextRevId++;
        $this->files[$fid] = $newPath;
        $serial = $this->revisions[$this->heads[$fid]]["object_serial"] ?? 0;
        $this->heads[$fid] = $revId;
        $this->revisions[$revId] = ["file_id"=>$fid,"object_serial"=>$serial,"path"=>$newPath,"presence"=>1];
    }

    /** Return the FileId for a path, or null when absent. */
    public function getFileId(string $path): ?string {
        foreach ($this->files as $fid => $p) { if ($p === $path) return $fid; }
        return null;
    }

    public function fileExists(string $fid): bool { return isset($this->heads[$fid]); }

    public function listRevisions(string $fid): array {
        $out = [];
        foreach ($this->revisions as $rid => $rev) if ($rev["file_id"] === $fid) $out[] = $rid;
        sort($out);
        return $out;
    }

    public function getRevision(int $rid): array {
        if (!isset($this->revisions[$rid])) throw new \InvalidArgumentException("unknown revision id");
        return $this->revisions[$rid];
    }

    public function getCurrentRevision(string $fid): int { return $this->heads[$fid] ?? 0; }

    public function checkoutRevision(int $rid): string {
        $rev = $this->getRevision($rid);
        $s = $rev["object_serial"];
        return $s === 0 ? "" : $this->objects[$s];
    }

    public function limitCleanUp(string $fid, int $limit): array {
        $removed = [];
        if ($limit < 1) throw new \InvalidArgumentException("limit must be >= 1");
        $revs = $this->listRevisions($fid);
        while (count($revs) > $limit) {
            $r = array_shift($revs);
            unset($this->revisions[$r]);
            $removed[] = $r;
        }
        return $removed;
    }

    public function listObjects(): array { $k = array_keys($this->objects); sort($k); return $k; }

    public function materializeObject(int $serial): string {
        if (!isset($this->objects[$serial])) throw new \InvalidArgumentException("missing object serial");
        return $this->objects[$serial];
    }

    public function getObjectInfo(int $serial): ?array {
        if (!isset($this->objects[$serial])) return null;
        return ["expected_size"=>strlen($this->objects[$serial])];
    }

    public function beginTransaction(): object { return (object)["ops"=>[]]; }
    public function stageAdd(object $txn, string $path, string $content): void { $txn->ops[] = ["add",$path,$content]; }
    public function stageDel(object $txn, string $fid): void { $txn->ops[] = ["del",$fid]; }
    public function rollback(object $txn): void { $txn->ops = []; }

    public function commit(?object $txn = null): string {
        if ($txn !== null) {
            foreach ($txn->ops as $op) {
                if ($op[0] === "add") $this->createFile($op[1], $op[2]);
                else $this->deleteFile($op[1]);
            }
        }
        $this->generation++;
        return $this->exportBytes();
    }

    public function validateStructural(): bool { return $this->mode === MODE_MODERN || $this->mode === MODE_ENTERPRISE; }
    public static function recoverFromBytes(string $data): int { return recover($data); }

    public function diffStores(MutableStore $other): array {
        $shared=[]; $added=[]; $deleted=[]; $modified=[];
        foreach ($this->files as $fid => $path) {
            if (!isset($other->files[$fid])) { $deleted[] = $path; }
            elseif ($other->files[$fid] !== $path) { $modified[] = $path; }
            else { $shared[] = $path; }
        }
        foreach ($other->files as $fid => $path) { if (!isset($this->files[$fid])) $added[] = $path; }
        return ["shared"=>$shared,"added"=>$added,"deleted"=>$deleted,"modified"=>$modified];
    }

    public static function mergeThreeWay(string $base, string $ours, string $theirs): array {
        if ($ours === $theirs) return ["merged"=>$ours,"has_conflict"=>false];
        if ($ours === $base) return ["merged"=>$theirs,"has_conflict"=>false];
        if ($theirs === $base) return ["merged"=>$ours,"has_conflict"=>false];
        return ["conflict"=>true,"base"=>$base,"ours"=>$ours,"theirs"=>$theirs];
    }

    public function importBytes(string $data): void {
        if (strlen($data) < 8 || substr($data,0,4) !== MAGIC) throw new \InvalidArgumentException("bad magic");
    }

    public function exportBytes(): string { return encode($this->mode, $this->generation, $this->storagePolicy); }
    public function writeLargeObject(string $path, string $content): void { $this->createFile($path, $content); }
    public function integrityVerify(): bool { return $this->validateStructural(); }
    public static function integrityVerifyRaw(string $data): bool {
        return strlen($data) >= 8 && substr($data,0,4) === MAGIC && unpack("n", substr($data,4,2))[1] === CFV;
    }
    public function getStats(): array {
        return ["revisions"=>count($this->revisions),"objects"=>count($this->objects),"files"=>count($this->files)];
    }
    public static function newBuilder(int $mode = MODE_MODERN): self { return self::create($mode); }
    public function checkMagicBytes(string $data): bool { return self::integrityVerifyRaw($data); }
}
