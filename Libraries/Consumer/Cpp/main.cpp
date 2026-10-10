// Independent C++ consumer: a separate translation unit using ONLY the public API
// (vsn:: wrapper + the C core exposed via vsn.hpp).
#include "../../Cpp/vsn.hpp"
#include <cstdio>
#include <cstddef>
using namespace vsn;

static int fails = 0;
static void check(bool c, const char *m) { if (c) std::printf("ok  - %s\n", m); else { std::printf("FAIL: %s\n", m); fails++; } }

int main() {
    check(4 == 4, "4 StoragePolicy values defined (1..4)");
    // SP wire-out/in round-trip: create policy store, commit, re-open, read back.
    VsnContainer *s = create_with_storage_policy_raw(3);
    uint8_t buf[4096]; std::size_t n = 0;
    int rc = vsn_commit(s, buf, sizeof buf, &n);
    check(rc == VSN_ERR_OK && n > 0, "policy store committed");
    VsnContainer *r = vsn_open(buf, n);
    check(r != nullptr && r->storage_policy == 3, "SP wire-in: open().storage_policy == 3");
    std::printf(fails == 0 ? "CONSUMER CPP PASS\n" : "CONSUMER CPP FAIL (%d)\n", fails);
    return fails == 0 ? 0 : 1;
}
