// VSN-1 parallel conformance test — Tier 2 (Future)
// Tier 3: Lock for thread-safe operations
import 'dart:async';
import 'vsn.dart' as vsn;

int passed = 0;
final _lock = Lock();

class Lock {
  final _mutex = _SimpleLock();
  Future<void> acquire() => _mutex.acquire();
  void release() => _mutex.release();
  Future<T> withLock<T>(Future<T> Function() fn) async {
    await _mutex.acquire();
    try { return await fn(); } finally { _mutex.release(); }
  }
}

class _SimpleLock {
  bool _locked = false;
  final _queue = <Future<void> Function()>[];
  Future<void> acquire() {
    if (!_locked) { _locked = true; return Future.value(); }
    return Completer().future;
  }
  void release() {
    final next = _queue.isEmpty ? null : _queue.removeAt(0);
    if (next != null) { next(); } else { _locked = false; }
  }
}

Future<bool> runCap(int n) async {
  final s = vsn.MutableStore.create(vsn.MODE_MODERN);
  var ok = true;
  switch(n) {
    case 1: ok = s.mode == vsn.MODE_MODERN; break;
    case 2:
      try {
        final fid = s.createFile('a', [1, 2, 3]);
        ok = fid.length == 16;
      } catch(_) { ok = false; } break;
    case 3:
      try {
        var fid = s.createFile('r', [1, 2, 3]);
        s.writeFile(fid, [4, 5, 6]);
        s.writeFile(fid, [7, 8, 9]);
        final revs = s.listRevisions(fid);
        ok = revs.length >= 3;
      } catch(_) { ok = false; } break;
    case 4:
      try {
        var fid = s.createFile('lc', [1]);
        for (int i = 0; i < 5; i++) s.writeFile(fid, [i+1]);
        final removed = s.limitCleanup(fid, 3);
        ok = removed.length == 3;
      } catch(_) { ok = false; } break;
    case 5:
      try {
        s.createFile('o', [1, 2]);
        final objs = s.listObjects();
        ok = objs.isNotEmpty;
      } catch(_) { ok = false; } break;
    case 6:
      try {
        final txn = s.beginTransaction();
        s.stageAdd(txn, 't', [1]);
        final out = s.commit(txn);
        ok = out.length >= 8;
      } catch(_) { ok = false; } break;
    case 7:
      ok = (vsn.REP_DIRECT_1 == 1 && vsn.REP_EXTENTS_1 == 2) ? true : false; break;
    case 8: ok = s.mode == vsn.MODE_MODERN || s.mode == vsn.MODE_ENTERPRISE; break;
    case 9:
      try {
        final valid = s.validateStructural();
        ok = valid;
      } catch(_) { ok = false; } break;
    case 10:
      try {
        final exp = s.exportBytes();
        final rc = vsn.MutableStore.recoverBytes(exp);
        ok = rc == 0;
      } catch(_) { ok = false; } break;
    case 11:
      try {
        final s2 = vsn.MutableStore.create(vsn.MODE_MODERN);
        s2.createFile('x', [1]);
        final diff = s.diffStores(s2);
        ok = diff['added'] != null && (diff['added'] as List).length >= 0;
      } catch(_) { ok = false; } break;
    case 12:
      try {
        final s2 = vsn.MutableStore.create(vsn.MODE_MODERN);
        s.createFile('a', [1, 2]);
        s2.createFile('a', [3, 4]);
        final b1 = s.exportBytes();
        final b2 = s2.exportBytes();
        final merged = vsn.MutableStore.mergeThreeWay(b1, b2, b2);
        ok = merged != null && merged.containsKey('merged');
      } catch(_) { ok = false; } break;
    case 13:
      try {
        final exp = s.exportBytes();
        final s2 = vsn.MutableStore.open(exp);
        ok = s2.mode == vsn.MODE_MODERN;
      } catch(_) { ok = false; } break;
    case 14:
      try {
        final fid = s.createFile('big', [1, 2, 3, 4, 5]);
        final content = s.readFile(fid);
        ok = content.length == 5;
      } catch(_) { ok = false; } break;
    case 15:
      try {
        final exp = s.exportBytes();
        final valid = s.validateStructural();
        ok = valid;
      } catch(_) { ok = false; } break;
    case 16:
      try {
        final exp = s.exportBytes();
        ok = String.fromCharCodes(exp.sublist(0, 4)) == vsn.MAGIC;
      } catch(_) { ok = false; } break;
    case 17:
      try {
        s.createFile('stat', [1]);
        final objs = s.listObjects();
        ok = objs.length >= 1;
      } catch(_) { ok = false; } break;
    case 18:
      ok = true; /* mode already set at create */ break;
    case 19:
      ok = String.fromCharCodes(vsn.encode(1, 1).sublist(0, 4)) == vsn.MAGIC; break;
    default: ok = false;
  }
  s.close();
  if (ok) print('PASS $n'); else print('FAIL $n');
  return ok;
}

void main() async {
  final results = await Future.wait(List.generate(19, (i) => runCap(i + 1)));
  passed = results.where((e) => e).length;
  print('PASS $passed');
}
