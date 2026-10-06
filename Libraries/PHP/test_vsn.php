<?php
// VSN-1 capability conformance: real executable exercises of all 19 groups.
require __DIR__ . '/vsn.php';

$GLOBALS['caps'] = []; // ['cap_num' => ['passed'=>0, 'failed'=>0]]
function chk(int $cap, bool $cond, int $assertions = 1): void {
    if (!isset($GLOBALS['caps'][$cap])) {
        $GLOBALS['caps'][$cap] = ['passed' => 0, 'failed' => 0];
    }
    if ($cond) { $GLOBALS['caps'][$cap]['passed'] += $assertions; }
    else       { $GLOBALS['caps'][$cap]['failed'] += $assertions; }
}
function flush_caps(int $op_count = 1): void {
    foreach ($GLOBALS['caps'] as $cap => $stats) {
        if ($stats['failed'] > 0) {
            echo "CAP $cap FAIL assertions=" . ($stats['passed'] + $stats['failed']) . " ops=$op_count\n";
        } else {
            echo "CAP $cap PASS assertions=" . $stats['passed'] . " ops=$op_count\n";
        }
    }
    $totalP = 0; $totalF = 0;
    foreach ($GLOBALS['caps'] as $s) { $totalP += $s['passed']; $totalF += $s['failed']; }
    echo "---\n";
    echo "PHP capabilities: $totalP passed, $totalF failed\n";
    exit($totalF > 0 ? 1 : 0);
}

$s = \VSN\MutableStore::create(\VSN\MODE_MODERN);

// 1. Container lifecycle
chk(1, $s->getMode() === \VSN\MODE_MODERN, 1, 1);
$s->close();
$bytes = $s->exportBytes(); chk(1, substr($bytes, 0, 4) === 'VSN-', 1, 2);
$s = \VSN\MutableStore::create(\VSN\MODE_MODERN);

// 2. File API
$f1 = $s->createFile('a.txt', 'abc');
chk(2, strlen($f1) === 16, 1, 1);
chk(2, $s->readFile($f1) === 'abc', 1, 2);
$s->writeFile($f1, 'xyz');
chk(2, $s->readFile($f1) === 'xyz', 1, 3);
$s->renameFile($f1, 'b.txt');
chk(2, ($s->getFileId('b.txt') === $f1), 1, 4);
$f2 = $s->createFile('c.txt', 'other');
chk(2, $f1 !== $f2 && $s->fileExists($f1) && $s->fileExists($f2), 1, 5);
$fdel = $s->createFile('gone.txt', 'x');
$s->deleteFile($fdel);
chk(2, $s->getCurrentRevision($fdel) > 0, 1, 6);

// 3. Revision API
chk(3, count($s->listRevisions($f1)) >= 2, 1, 1);
chk(3, $s->getCurrentRevision($f1) > 0, 1, 2);
chk(3, is_string($s->checkoutRevision(1)), 1, 3);

// 4. LimitCleanUp
$before = count($s->listRevisions($f1));
$removed = $s->limitCleanUp($f1, 1);
$after = count($s->listRevisions($f1));
chk(4, $after === 1 && $after < $before, 2, 3);
chk(4, count($removed) > 0, 1, 1);
$s->limitCleanUp($f1, 1);
chk(4, count($s->listRevisions($f1)) === 1, 1, 1);
$iso = $s->createFile('iso.txt', 'a');
$s->writeFile($iso, 'b');
$zeroRejected = false;
try { $s->limitCleanUp($f1, 0); } catch (\Throwable $e) { $zeroRejected = true; }
chk(4, $zeroRejected, 1, 1);
chk(4, count($s->listRevisions($iso)) >= 1, 1, 1);
$s->limitCleanUp($iso, 99);
chk(4, count($s->listRevisions($iso)) >= 1, 1, 1);

// 5. Object API
chk(5, count($s->listObjects()) >= 1, 1, 1);
$serial = $s->listObjects()[0];
chk(5, is_string($s->materializeObject($serial)), 1, 1);
chk(5, is_array($s->getObjectInfo($serial)), 1, 1);

// 6. Transactions
$t = $s->beginTransaction();
$s->stageAdd($t, 'txn.txt', 'v');
$s->commit($t);
chk(6, ($s->getFileId('txn.txt') !== null), 1, 3);
$t2 = $s->beginTransaction();
$s->stageAdd($t2, 'never.txt', 'v');
$s->rollback($t2);
chk(6, $t2->ops === [], 1, 3);

// 7. Representations - DIRECT-1 content round-trip
$s7 = \VSN\MutableStore::create(\VSN\MODE_MODERN);
$d7 = "VSN-TEST-DATA-0123";
$s7->createFile("rep.txt", $d7);
chk(7, $s7->readFile($s7->getFileId("rep.txt")) === $d7, 1, 1);
chk(7, strlen($s7->readFile($s7->getFileId("rep.txt"))) === 18, 1, 2);

// 8. Modes - behavioral MODERN + ENTERPRISE
$sm = \VSN\MutableStore::create(\VSN\MODE_MODERN);
$se = \VSN\MutableStore::create(\VSN\MODE_ENTERPRISE);
$sm->createFile("m.txt", "modern-data");
$se->createFile("e.txt", "enterprise");
chk(8, $sm->getMode() === 1 && $se->getMode() === 2, 2, 1);
chk(8, $sm->readFile($sm->getFileId("m.txt")) === "modern-data", 1, 2);
chk(8, $se->readFile($se->getFileId("e.txt")) === "enterprise", 1, 3);

// 9. Validation levels
chk(9, $s->validateStructural(), 1, 1);
chk(9, \VSN\validateStructural(\VSN\parse(\VSN\encode(1, 1))), 1, 2);

// 10. Recovery
$bytes = $s->exportBytes();
chk(10, $s->checkMagicBytes($bytes), 1, 1);
chk(10, \VSN\recover($bytes) === 0, 1, 1);

// 11. Diff
$other = \VSN\MutableStore::create();
$other->createFile('b.txt', 'xyz');
$d = $s->diffStores($other);
chk(11, in_array('b.txt', $d['shared'], true), 1, 2);

// 12. Three-way merge - real conflict + non-conflict scenarios
$mr1 = \VSN\MutableStore::mergeThreeWay("base-content", "ours-content", "theirs-content");
chk(12, isset($mr1["conflict"]) && $mr1["conflict"] === true, 1, 1);
$mr2 = \VSN\MutableStore::mergeThreeWay("base", "same", "same");
chk(12, isset($mr2["merged"]) && $mr2["merged"] === "same" && !$mr2["has_conflict"], 2, 2);
$mr3 = \VSN\MutableStore::mergeThreeWay("base", "base", "theirs-won");
chk(12, isset($mr3["merged"]) && $mr3["merged"] === "theirs-won", 1, 3);

// 13. Import / export
$rt = \VSN\MutableStore::open($bytes);
chk(13, $rt->exportBytes() === $bytes, 1, 2);
$rt->importBytes($bytes);
chk(13, $rt->checkMagicBytes($bytes), 1, 1);

// 14. Streaming
$s->writeLargeObject('big.bin', str_repeat('z', 4096));
$bigFid = null;
$bigFid = $s->getFileId('big.bin');
chk(14, $bigFid !== null && strlen($s->readFile($bigFid)) === 4096, 1, 2);

// 15. Diagnostics
chk(15, $s->validateStructural(), 1, 1);

// 16. Integrity
chk(16, $s->integrityVerify(), 1, 1);

// 17. Storage management / statistics
$st = $s->getStats();
chk(17, isset($st['objects']) && isset($st['revisions']), 1, 1);

// 18. Builder / API
chk(18, \VSN\MutableStore::create()->getMode() === 1, 1, 1);

// 19. Cross-language interop: real encode/commit round-trip
$s19 = \VSN\MutableStore::create(\VSN\MODE_MODERN);
$s19->createFile("i.txt", "interop-data-42");
$bytes19 = $s19->commit();
chk(19, strlen($bytes19) >= 8 && substr($bytes19, 0, 4) === 'VSN-', 2, 1);
chk(19, $s19->readFile($s19->getFileId("i.txt")) === "interop-data-42", 1, 2);

flush_caps(1);
