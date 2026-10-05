/* Executable LimitCleanUp probe for the C++ library (mirrors the C/Python probe).
 * Builds a real 10-revision history, runs LimitCleanUp, and verifies the
 * resulting revision history, inaccessible deleted revisions, FileHead,
 * commit/reopen, recovery, idempotency, and argument rejection.
 * Prints a final machine-readable line:
 *     LIMIT_CLEANUP <PASS|FAIL> removed=<csv> retained=<csv>
 */
#include "vsn.hpp"
#include <cstdio>
#include <string>
using namespace vsn;

static int failures = 0;
static void check(bool cond, const char* label) { if (!cond) { failures++; std::printf("  FAIL: %s\n", label); } }
static void build(Container& c, int n, FileId& fid) {
    fid = c.create_file("a.txt", (const uint8_t*)"v1", 2);
    for (int i = 2; i <= n; i++) { char b[16]; int len = std::snprintf(b, 16, "v%d", i); c.write_file(fid, (const uint8_t*)b, (size_t)len); }
}
static std::string csv(const std::vector<uint32_t>& a) {
    std::string s; for (size_t i = 0; i < a.size(); i++) { if (i) s += ","; s += std::to_string(a[i]); }
    return s;
}

int main() {
    Container c(MODE_MODERN); FileId fid; build(c, 10, fid);
    std::vector<uint32_t> rem = c.limit_cleanup(fid, 5);
    std::vector<uint32_t> ret = c.list_revisions(fid);
    check(rem.size() == 5, "exactly 5 removed");
    check(ret.size() == 5, "exactly 5 retained");
    bool remok = rem.size() == 5; for (size_t i = 0; i < rem.size() && remok; i++) if (rem[i] != (uint32_t)(i + 1)) remok = false;
    check(remok, "removed ids == 1..5");
    bool retok = ret.size() == 5; for (size_t i = 0; i < ret.size() && retok; i++) if (ret[i] != (uint32_t)(6 + i)) retok = false;
    check(retok, "retained ids == 6..10");
    bool deleted = false; try { (void)c.checkout(fid, 1); } catch (const Error&) { deleted = true; }
    check(deleted, "deleted rev 1 inaccessible");
    check(ret.size() > 0 && ret[ret.size() - 1] == 10, "FileHead is newest retained (10)");

    auto data = c.commit();
    Container r(data.data(), data.size());
    std::vector<uint32_t> rr = r.list_revisions(fid);
    bool okset = rr.size() == 5; for (size_t i = 0; i < rr.size() && okset; i++) if (rr[i] != (uint32_t)(6 + i)) okset = false;
    check(okset, "reopen retained == 6..10");
    bool deleted2 = false; try { (void)r.checkout(fid, 1); } catch (const Error&) { deleted2 = true; }
    check(deleted2, "deleted rev 1 inaccessible after reopen");
    check(recover(data.data(), data.size()).size() > 0, "recovery succeeded");
    bool idem = true; for (int i = 0; i < 3 && idem; i++) { if (!r.limit_cleanup(fid, 5).empty()) idem = false; }
    check(idem, "repeat calls remove nothing");

    Container fresh(MODE_MODERN); FileId ffid; build(fresh, 3, ffid);
    check(fresh.limit_cleanup(ffid, 99).empty(), "limit > history removes nothing");
    check(fresh.list_revisions(ffid).size() == 3, "limit > history keeps all");

    Container zz(MODE_MODERN); FileId zfid; build(zz, 6, zfid);
    bool rejected = false; int code = 0;
    try { (void)zz.limit_cleanup(zfid, 0); } catch (const Error& e) { rejected = true; code = e.code; }
    check(rejected && code == VSN_ERR_INVALID_STATE, "limit 0 rejected 0x000C");

    std::printf("removed=%s retained=%s\n", csv(rem).c_str(), csv(ret).c_str());
    std::printf("LIMIT_CLEANUP %s removed=%s retained=%s\n", failures ? "FAIL" : "PASS", csv(rem).c_str(), csv(ret).c_str());
    return failures ? 1 : 0;
}