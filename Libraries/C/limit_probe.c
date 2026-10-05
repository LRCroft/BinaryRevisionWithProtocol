/* Executable LimitCleanUp probe for the C library (mirrors the Python probe).
 * Builds a real 10-revision history, runs LimitCleanUp, and verifies the
 * resulting revision history, inaccessible deleted revisions, FileHead,
 * commit/reopen, recovery, idempotency, and argument rejection.
 * Prints a final machine-readable line:
 *     LIMIT_CLEANUP <PASS|FAIL> removed=<csv> retained=<csv>
 */
#define _CRT_SECURE_NO_WARNINGS 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vsn.h"

static int failures = 0;
static void check(int cond, const char *label) { if (!cond) { failures++; printf("  FAIL: %s\n", label); } }

static VsnContainer *build(int n, FileId *fid) {
    VsnContainer *c = vsn_create(MODE_MODERN);
    if (!c) return NULL;
    if (vsn_create_file(c, "a.txt", (const uint8_t*)"v1", 2, fid) != VSN_ERR_OK) { vsn_close(c); return NULL; }
    for (int i = 2; i <= n; i++) {
        char buf[16]; int len = snprintf(buf, sizeof(buf), "v%d", i);
        if (vsn_write_file(c, fid, (const uint8_t*)buf, (size_t)len) != VSN_ERR_OK) { vsn_close(c); return NULL; }
    }
    return c;
}
static void csv(const uint32_t *a, int n, char *out, size_t cap) {
    size_t off = 0;
    for (int i = 0; i < n && off + 8 < cap; i++) off += (size_t)snprintf(out + off, cap - off, "%s%u", i ? "," : "", a[i]);
}

int main(void) {
    FileId fid; VsnContainer *c = build(10, &fid);
    uint32_t *rem = NULL, *ret = NULL, *remcopy = NULL, *retcopy = NULL; int nrem = 0, nret = 0;
    if (!c) { printf("LIMIT_CLEANUP FAIL removed= retained=\n"); return 1; }

    int rc = vsn_limit_cleanup(c, &fid, 5, &rem, &nrem);
    check(rc == VSN_ERR_OK, "limit_cleanup(10,5) ok");
    vsn_list_revisions(c, &fid, &ret, &nret);
    if (nrem > 0 && nrem <= 64) { remcopy = (uint32_t*)malloc(nrem * 4); memcpy(remcopy, rem, nrem * 4); }
    if (nret > 0 && nret <= 64) { retcopy = (uint32_t*)malloc(nret * 4); memcpy(retcopy, ret, nret * 4); }
    check(nrem == 5, "exactly 5 removed");
    check(nret == 5, "exactly 5 retained");
    int remok = (nrem == 5); for (int i = 0; i < nrem && remok; i++) if (remcopy[i] != (uint32_t)(i + 1)) remok = 0;
    check(remok, "removed ids == 1..5");
    int retok = (nret == 5); for (int i = 0; i < nret && retok; i++) if (retcopy[i] != (uint32_t)(6 + i)) retok = 0;
    check(retok, "retained ids == 6..10");
    { uint8_t o[256]; size_t ol; check(vsn_checkout_revision(c, &fid, 1, o, sizeof(o), &ol) != VSN_ERR_OK, "deleted rev 1 inaccessible"); }
    check(nret > 0 && retcopy[nret - 1] == 10, "FileHead is newest retained (10)");

    uint8_t data[16384]; size_t dlen = 0;
    check(vsn_commit(c, data, sizeof(data), &dlen) == VSN_ERR_OK, "commit ok");
    VsnContainer *r = vsn_open(data, dlen);
    check(r != NULL, "reopen ok");
    if (r) {
        uint32_t *rr = NULL; int nr = 0; vsn_list_revisions(r, &fid, &rr, &nr);
        int okset = (nr == 5); for (int i = 0; i < nr && okset; i++) if (rr[i] != (uint32_t)(6 + i)) okset = 0;
        check(okset, "reopen retained == 6..10");
        { uint8_t o[256]; size_t ol; check(vsn_checkout_revision(r, &fid, 1, o, sizeof(o), &ol) != VSN_ERR_OK, "deleted rev 1 inaccessible after reopen"); }
        uint8_t rb[16384]; size_t rbl = 0;
        check(vsn_recover(data, dlen, rb, sizeof(rb), &rbl) == VSN_ERR_OK, "recovery succeeded");
        int idem = 1; for (int i = 0; i < 3 && idem; i++) { uint32_t *rm = NULL; int nm = 0; vsn_limit_cleanup(r, &fid, 5, &rm, &nm); if (nm != 0) idem = 0; }
        check(idem, "repeat calls remove nothing");
        vsn_close(r);
    }
    vsn_close(c);

    FileId ffid; VsnContainer *fresh = build(3, &ffid);
    if (fresh) { uint32_t *rm = NULL; int nm = 0; vsn_limit_cleanup(fresh, &ffid, 99, &rm, &nm); check(nm == 0, "limit > history removes nothing");
        uint32_t *lv = NULL; int nl = 0; vsn_list_revisions(fresh, &ffid, &lv, &nl); check(nl == 3, "limit > history keeps all"); vsn_close(fresh); }
    FileId zfid; VsnContainer *zz = build(6, &zfid);
    if (zz) { uint32_t *rm = NULL; int nm = 0; check(vsn_limit_cleanup(zz, &zfid, 0, &rm, &nm) == VSN_ERR_INVALID_STATE, "limit 0 rejected 0x000C"); vsn_close(zz); }

    char cr[256], ct[256]; csv(remcopy, nrem, cr, sizeof(cr)); csv(retcopy, nret, ct, sizeof(ct));
    printf("removed=%s retained=%s\n", cr, ct);
    printf("LIMIT_CLEANUP %s removed=%s retained=%s\n", failures ? "FAIL" : "PASS", cr, ct);
    free(remcopy); free(retcopy);
    return failures ? 1 : 0;
}