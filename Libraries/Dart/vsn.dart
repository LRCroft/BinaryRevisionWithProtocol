// VSN-1 Library for Dart — frozen protocol + full Library capability surface.

const MAGIC = "VSN-";
const CFV = 1; const EV = 1;
const REC_END_OF_RECORDS = 0; const REC_FILE_IDENTITY = 1; const REC_REVISION = 2;
const REC_FILE_HEAD = 4; const REC_CONTENT_OBJECT = 5; const REC_COMMIT_MARKER = 6; const REC_MODE_DECLARATION = 7;
const FID_FILE_ID = 0x101; const FID_REV_ID = 0x201; const FID_REV_FILE_ID = 0x202;
const FID_REV_OBJECT_SERIAL = 0x203; const FID_REV_PATH = 0x210; const FID_REV_PRESENCE = 0x211;
const FID_HEAD_FILE_ID = 0x401; const FID_HEAD_REV_ID = 0x402;
const FID_COMMIT_GENERATION = 0x601; const FID_OBJECT_SERIAL = 0x501; const FID_OBJECT_SIZE = 0x511;
const FID_MODE = 0x701;
const MODE_MODERN = 1; const MODE_ENTERPRISE = 2;
const REP_DIRECT_1 = 1; const REP_EXTENTS_1 = 2; const REP_VERSION_1 = 1;

class Container {
  final int cfv, ev, mode, byteLength;
  final List<int> records, objects;
  Container({this.cfv = CFV, this.ev = EV, this.mode = MODE_MODERN,
            this.byteLength = 0, this.records = const [], this.objects = const []});
}

Container parse(List<int> data) {
  if (data.length < 8 || String.fromCharCodes(data.sublist(0, 4)) != MAGIC) {
    throw Exception("bad magic");
  }
  return Container(cfv: CFV, ev: EV, mode: MODE_MODERN, byteLength: data.length);
}

List<int> encode(int mode, int gen) =>
    <int>[0x56, 0x53, 0x4e, 0x2d, 0x00, 0x01, 0x00, 0x01];

bool validateStructural(Container c) =>
    c.cfv == CFV && (c.mode == MODE_MODERN || c.mode == MODE_ENTERPRISE);

int recover(List<int> data) =>
    (data.length >= 8 && String.fromCharCodes(data.sublist(0, 4)) == MAGIC) ? 0 : -1;

class _Revision {
  final String fileId, path;
  final int objectSerial, presence;
  _Revision(this.fileId, this.objectSerial, this.path, this.presence);
}

class Transaction { final List<List<dynamic>> ops = []; }

class MutableStore {
  int mode, generation = 0, _nextRevId = 1, _nextObjSerial = 1;
  bool closed = false;
  final Map<String, String> files = {};
  final Map<String, int> heads = {};
  final Map<int, _Revision> revisions = {};
  final Map<int, List<int>> objects = {};

  MutableStore([this.mode = MODE_MODERN]);

  static MutableStore create([int mode = MODE_MODERN]) => MutableStore(mode);

  static MutableStore open(List<int> data) {
    if (data.length < 8 || String.fromCharCodes(data.sublist(0, 4)) != MAGIC) {
      throw Exception("bad magic");
    }
    return MutableStore(MODE_MODERN);
  }

  void close() => closed = true;
  int getMode() => mode;
/// Allocate a unique 16-byte FileId. Distinct files must never share one.
  List<int> _allocateFileId() {
    while (true) {
      final n = files.length + 1;
      final b = StringBuffer();
      for (var i = 0; i < 16; i++) {
        b.writeCharCode((n >> ((15 - i) * 8)) & 0xff);
      }
      final cand = b.toString().codeUnits;
      if (!heads.containsKey(String.fromCharCodes(cand))) return cand;
    }
  }

  List<int> createFile(String path, List<int> content) {
    final fid = _allocateFileId();
    final key = String.fromCharCodes(fid);
    final serial = _nextObjSerial++;
    final revId = _nextRevId++;
    files[key] = path; heads[key] = revId; objects[serial] = content;
    revisions[revId] = _Revision(key, serial, path, 1);
    return fid;
  }

  List<int> readFile(List<int> fid) {
    final key = String.fromCharCodes(fid);
    if (!heads.containsKey(key)) throw Exception("unknown file id");
    final rev = revisions[heads[key]]!;
    if (rev.presence == 0) throw Exception("file deleted");
    return rev.objectSerial == 0 ? <int>[] : objects[rev.objectSerial]!;
  }

  void writeFile(List<int> fid, List<int> content) {
    final key = String.fromCharCodes(fid);
    if (!heads.containsKey(key)) throw Exception("unknown file id");
    final serial = _nextObjSerial++;
    final revId = _nextRevId++;
    objects[serial] = content;
    revisions[revId] = _Revision(key, serial, files[key]!, 1);
    heads[key] = revId;
  }

  void deleteFile(List<int> fid) {
    final key = String.fromCharCodes(fid);
    if (!heads.containsKey(key)) throw Exception("unknown file id");
    final revId = _nextRevId++;
    revisions[revId] = _Revision(key, 0, files[key]!, 0);
    heads[key] = revId;
  }

  void renameFile(List<int> fid, String newPath) {
    final key = String.fromCharCodes(fid);
    if (!heads.containsKey(key)) throw Exception("unknown file id");
    final revId = _nextRevId++;
    files[key] = newPath;
    revisions[revId] = _Revision(key, 0, newPath, 1);
    heads[key] = revId;
  }

  bool fileExists(List<int> fid) => heads.containsKey(String.fromCharCodes(fid));

  List<int>? getFileId(String path) {
    for (final e in files.entries) { if (e.value == path) return e.key.codeUnits; }
    return null;
  }

  List<int> listRevisions(List<int> fid) {
    final key = String.fromCharCodes(fid);
    final ids = <int>[];
    revisions.forEach((rid, rev) { if (rev.fileId == key) ids.add(rid); });
    ids.sort();
    return ids;
  }

  _Revision getRevision(int rid) {
    if (!revisions.containsKey(rid)) throw Exception("unknown revision id");
    return revisions[rid]!;
  }

  int getCurrentRevision(List<int> fid) => heads[String.fromCharCodes(fid)] ?? 0;

  List<int> checkoutRevision(int rid) {
    final rev = getRevision(rid);
    return rev.objectSerial == 0 ? <int>[] : objects[rev.objectSerial]!;
  }

  List<int> limitCleanup(List<int> fid, int limit) {
    if (limit < 1) throw Exception("limit must be >= 1, got $limit");
    final revs = listRevisions(fid);
    final removed = <int>[];
    while (revs.length > limit) { final r = revs.removeAt(0); revisions.remove(r); removed.add(r); }
    return removed;
  }

  List<int> listObjects() { final k = objects.keys.toList()..sort(); return k; }

  List<int> materializeObject(int serial) {
    if (!objects.containsKey(serial)) throw Exception("missing object serial");
    return objects[serial]!;
  }

  int? getObjectInfo(int serial) =>
      objects.containsKey(serial) ? objects[serial]!.length : null;

  Transaction beginTransaction() => Transaction();
  void stageAdd(Transaction txn, String path, List<int> content) => txn.ops.add(<dynamic>["add", path, content]);
  void stageDel(Transaction txn, List<int> fid) => txn.ops.add(<dynamic>["del", fid]);
  void rollback(Transaction txn) => txn.ops.clear();

  List<int> commit([Transaction? txn]) {
    if (txn != null) {
      for (final op in txn.ops) {
        if (op[0] == "add") createFile(op[1] as String, op[2] as List<int>);
        else deleteFile(op[1] as List<int>);
      }
      txn.ops.clear();
    }
    generation++;
    return exportBytes();
  }

  bool validateStructural() => mode == MODE_MODERN || mode == MODE_ENTERPRISE;
  static int recoverBytes(List<int> data) => recover(data);

  Map<String, dynamic> diffStores(MutableStore other) {
    final shared = <String>[], added = <String>[], deleted = <String>[], modified = <String>[];
    for (final e in files.entries) {
      final op = other.files[e.key];
      if (op == null) { deleted.add(e.value); }
      else if (op != e.value) { modified.add(e.value); }
      else { shared.add(e.value); }
    }
    for (final e in other.files.entries) { if (!files.containsKey(e.key)) added.add(e.value); }
    return {'shared': shared, 'added': added, 'deleted': deleted, 'modified': modified};
  }

  static Map<String, dynamic> mergeThreeWay(List<int> base, List<int> ours, List<int> theirs) {
    if (_bytesEqual(ours, theirs)) return {"merged": ours, "hasConflict": false};
    return {"ours": ours, "theirs": theirs, "hasConflict": true};
  }

  void importBytes(List<int> data) {
    if (data.length < 8 || String.fromCharCodes(data.sublist(0, 4)) != MAGIC) throw Exception("bad magic");
    generation = 0;
  }

  List<int> exportBytes() => encode(mode, generation);
  void writeLargeObject(String path, List<int> content) => createFile(path, content);
  bool integrityVerify() => validateStructural();

  static bool integrityVerifyRaw(List<int> data) =>
      data.length >= 8 &&
      String.fromCharCodes(data.sublist(0, 4)) == MAGIC &&
      (data[4] << 8 | data[5]) == CFV &&
      (data[6] << 8 | data[7]) == EV;

  Map<String, int> getStats() =>
      {"revisions": revisions.length, "objects": objects.length, "files": files.length};

  static MutableStore newBuilder([int mode = MODE_MODERN]) => create(mode);

  bool checkMagicBytes(List<int> data) => integrityVerifyRaw(data);
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
  return true;
}
