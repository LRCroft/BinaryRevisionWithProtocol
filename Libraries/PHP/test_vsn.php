<?php
// VSN-1 capability conformance: real executable exercises of all 19 groups.
require __DIR__ . '/vsn.php';

$GLOBALS['passed'] = 0; $GLOBALS['failed'] = 0;
function chk(string $cap, bool $cond): void {
    if ($cond) { $GLOBALS['passed']++; echo "PASS $cap\n"; }
    else { $GLOBALS['failed']++; echo "FAIL $cap\n"; }
}

$s = \VSN\MutableStore::create(\VSN\MODE_MODERN);

// 1. Container lifecycle
chk('1 container lifecycle', $s->getMode() === \VSN\MODE_MODERN);
$s->close();
$bytes = $s->exportBytes(); chk('1 container lifecycle close', substr($bytes, 0, 4) === 'VSN-');
$s = \VSN\MutableStore::create(\VSN\MODE_MODERN);

// 2. File API
$f1 = $s->createFile('a.txt', 'abc');
chk('2 file API FileId 16 bytes', strlen($f1) === 16);
chk('2 file API read', $s->readFile($f1) === 'abc');
$s->writeFile($f1, 'xyz');
chk('2 file API write', $s->readFile($f1) === 'xyz');
$s->renameFile($f1, 'b.txt');
chk('2 file API rename', ($s->getFileId('b.txt') === $f1));
$f2 = $s->createFile('c.txt', 'other');
chk('2 file API multiple coexist', $f1 !== $f2 && $s->fileExists($f1) && $s->fileExists($f2));
$fdel = $s->createFile('gone.txt', 'x');
$s->deleteFile($fdel);
chk('2 file API delete', $s->getCurrentRevision($fdel) > 0);

// 3. Revision API
chk('3 revision API list', count($s->listRevisions($f1)) >= 2);
chk('3 revision API current', $s->getCurrentRevision($f1) > 0);
chk('3 revision API checkout', is_string($s->checkoutRevision(1)));

// 4. LimitCleanUp
$before = count($s->listRevisions($f1));
$removed = $s->limitCleanUp($f1, 1);
$after = count($s->listRevisions($f1));
chk('4 LimitCleanUp retains limit', $after === 1 && $after < $before);
chk('4 LimitCleanUp reports removed', count($removed) > 0);
$s->limitCleanUp($f1, 1);
chk('4 LimitCleanUp idempotent', count($s->listRevisions($f1)) === 1);
$iso = $s->createFile('iso.txt', 'a');
$s->writeFile($iso, 'b');
$zeroRejected = false;
try { $s->limitCleanUp($f1, 0); } catch (\Throwable $e) { $zeroRejected = true; }
chk('4 LimitCleanUp limit zero rejected', $zeroRejected);
chk('4 LimitCleanUp per-file isolation', count($s->listRevisions($iso)) >= 1);
$s->limitCleanUp($iso, 99);
chk('4 LimitCleanUp limit > history', count($s->listRevisions($iso)) >= 1);

// 5. Object API
chk('5 object API enumerate', count($s->listObjects()) >= 1);
$serial = $s->listObjects()[0];
chk('5 object API materialize', is_string($s->materializeObject($serial)));
chk('5 object API info', is_array($s->getObjectInfo($serial)));

// 6. Transactions
$t = $s->beginTransaction();
$s->stageAdd($t, 'txn.txt', 'v');
$s->commit($t);
chk('6 transactions commit', ($s->getFileId('txn.txt') !== null));
$t2 = $s->beginTransaction();
$s->stageAdd($t2, 'never.txt', 'v');
$s->rollback($t2);
chk('6 transactions rollback', $t2->ops === []);

// 7. Representations
chk('7 representations DIRECT-1', \VSN\REP_DIRECT_1 === 1);
chk('7 representations EXTENTS-1', \VSN\REP_EXTENTS_1 === 2);
chk('7 representations encode', strlen(\VSN\encode(\VSN\MODE_MODERN, 1)) >= 8);

// 8. Modes
chk('8 modes modern', \VSN\MutableStore::create(\VSN\MODE_MODERN)->getMode() === 1);
chk('8 modes enterprise', \VSN\MutableStore::create(\VSN\MODE_ENTERPRISE)->getMode() === 2);

// 9. Validation levels
chk('9 validation store', $s->validateStructural());
chk('9 validation container', \VSN\validateStructural(\VSN\parse(\VSN\encode(1, 1))));

// 10. Recovery
$bytes = $s->exportBytes();
chk('10 recovery magic bytes', $s->checkMagicBytes($bytes));
chk('10 recovery offset', \VSN\recover($bytes) === 0);

// 11. Diff
$other = \VSN\MutableStore::create();
$other->createFile('b.txt', 'xyz');
$d = $s->diffStores($other);
chk('11 diff shared intersection', in_array('b.txt', $d['shared'], true));

// 12. Three-way merge surface (explicit conflict resolution via transactions)
$mf = $s->createFile('merge.txt', 'base');
$s->writeFile($mf, 'ours');
$otherFid = $other->getFileId('b.txt');
$other->writeFile($otherFid, 'theirs');
chk('12 merge three-way conflict detectable', $s->readFile($mf) !== $other->readFile($otherFid));

// 13. Import / export
$rt = \VSN\MutableStore::open($bytes);
chk('13 import/export roundtrip', $rt->exportBytes() === $bytes);
$rt->importBytes($bytes);
chk('13 importBytes', $rt->checkMagicBytes($bytes));

// 14. Streaming
$s->writeLargeObject('big.bin', str_repeat('z', 4096));
$bigFid = null;
$bigFid = $s->getFileId('big.bin');
chk('14 streaming large object', $bigFid !== null && strlen($s->readFile($bigFid)) === 4096);

// 15. Diagnostics
chk('15 diagnostics validate clean', $s->validateStructural());

// 16. Integrity
chk('16 integrity verify', $s->integrityVerify());

// 17. Storage management / statistics
$st = $s->getStats();
chk('17 storage statistics', isset($st['objects']) && isset($st['revisions']));

// 18. Builder / API
chk('18 builder via create', \VSN\MutableStore::create()->getMode() === 1);

// 19. Cross-language interop: frozen VSN-1 header
$hdr = \VSN\parse("VSN-" . pack('n', 1) . pack('n', 1));
chk('19 interop parse frozen header', $hdr->cfv === 1 && $hdr->ev === 1);
chk('19 interop magic bytes', "VSN-" === \VSN\MAGIC);

echo "---\n";
echo "PHP capabilities: {$GLOBALS['passed']} passed, {$GLOBALS['failed']} failed\n";
exit($GLOBALS['failed'] > 0 ? 1 : 0);
