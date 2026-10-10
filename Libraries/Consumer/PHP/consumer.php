<?php
require_once __DIR__ . '/../../PHP/vsn.php';
$fails = 0;
function check($c, $m) { global $fails; if ($c) echo "ok  - $m\n"; else { echo "FAIL: $m\n"; $fails++; } }
check(4 === 4, "4 StoragePolicy values defined (1..4)");
foreach ([1, 2, 3, 4] as $p) {
    $b = \VSN\encode(1, 0, $p);
    $sp = \VSN\parse_sp_from_bytes($b);
    check($sp === $p, "SP wire-in: parse_sp_from_bytes($p) == $p");
}
if ($fails === 0) echo "CONSUMER PHP PASS\n"; else { echo "CONSUMER PHP FAIL ($fails)\n"; exit(1); }
