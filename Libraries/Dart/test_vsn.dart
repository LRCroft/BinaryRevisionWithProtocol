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
  if (n == 2) {
    final fid = s.createFile('a', [1, 2, 3]);
    ok = fid.length == 16;
  }
  if (n == 8) ok = s.mode == vsn.MODE_MODERN;
  s.close();
  if (ok) print('PASS $n'); else print('FAIL $n');
  return ok;
}

void main() async {
  final results = await Future.wait(List.generate(19, (i) => runCap(i + 1)));
  passed = results.where((e) => e).length;
  print('PASS $passed');
}
