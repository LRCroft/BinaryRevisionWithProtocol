module consumer;
import std.stdio;
import core.stdc.stdlib;
import vsn;

// VSN-1 independent consumer (D) -- Storage Policy round-trip.
// Uses the library's createWithPolicy + exportBytes (wire-out)
// + importBytes (wire-in).
bool hasSig(ubyte[] b) {
    if (b.length < 6) return false;
    for (size_t i = 0; i + 6 <= b.length; i++)
        if (b[i] == 0 && b[i + 1] == 9 && b[i + 2] == 4 &&
            b[i + 3] == 9 && b[i + 4] == 1 && b[i + 5] == 1)
            return true;
    return false;
}

void main() {
    bool bad = false;
    for (int p = 1; p <= 4; p++) {
        auto s = createWithPolicy(p);
        auto b = s.exportBytes();
        if (!hasSig(b)) { writefln("FAIL p=%d wire-out", p); bad = true; }
        auto s2 = createWithPolicy(1);
        if (!s2.importBytes(b)) { writefln("FAIL p=%d import", p); bad = true; }
        if (s2.storagePolicy != cast(ubyte) p) {
            writefln("FAIL p=%d got=%d", p, s2.storagePolicy); bad = true;
        }
    }
    writefln(bad ? "CONSUMER D FAIL" : "CONSUMER D PASS");
    if (bad) exit(1);
}
