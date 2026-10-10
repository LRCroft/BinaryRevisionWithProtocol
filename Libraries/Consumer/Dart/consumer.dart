import 'dart:io' as io;
import '../../Dart/vsn.dart' as V;

// VSN independent consumer (Dart) -- Storage Policy round-trip.
// Uses the library's encode (wire-out) + parse (wire-in).
bool sig(List<int> b) {
  for (int i = 0; i <= b.length - 7; i++)
    if (b[i] == 0 && b[i + 1] == 9 && b[i + 2] == 4 &&
        b[i + 3] == 9 && b[i + 4] == 1 && b[i + 5] == 1)
      return true;
  return false;
}

void main() {
  var bad = false;
  for (int p = 1; p <= 4; p++) {
    final b = V.encode(1, 0, storagePolicy: p);
    final c = V.parse(b);
    if (!sig(b)) { print('FAIL p=$p wire-out'); bad = true; }
    if (c.storagePolicy != p) { print('FAIL p=$p got=${c.storagePolicy}'); bad = true; }
  }
  print(bad ? 'CONSUMER DART FAIL' : 'CONSUMER DART PASS');
  io.exit(bad ? 1 : 0);
}

