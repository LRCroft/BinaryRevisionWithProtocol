/* Independent C consumer: compiled alongside the VSN C library and uses ONLY
 * the public API declared in vsn.h. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "vsn.h"

static int fails = 0;
static void check(int cond, const char *msg) {
    if (cond) printf("ok  - %s\n", msg);
    else { printf("FAIL: %s\n", msg); fails++; }
}

/* Find the canonical REC_STORAGE_POLICY (0x0009) record with FID_STORAGE_POLICY
 * (0x0901) as a byte signature [00 09][plen][09 01][vlen][value]; return value, or 0 if absent. */
static int sp_on_wire(const uint8_t *b, size_t n) {
    for (size_t i = 0; i + 6 <= n; i++) {
        if (b[i] == 0x00 && b[i + 1] == 0x09 && b[i + 3] == 0x09 && b[i + 4] == 0x01) {
            return b[i + 6];
        }
    }
    return 0;
}

int main(void) {
    VsnContainer *c = vsn_create(MODE_MODERN);
    check(c != NULL, "vsn_create");
    FileId fid; memset(&fid, 0, sizeof fid);
    check(vsn_create_file(c, "c.txt", (const uint8_t *)"C-CONSUMER", 10, &fid) == VSN_ERR_OK, "create_file");
    uint8_t rbuf[64]; size_t rlen = 0;
    check(vsn_read_file(c, &fid, rbuf, sizeof rbuf, &rlen) == VSN_ERR_OK && rlen == 10 && memcmp(rbuf, "C-CONSUMER", 10) == 0,
          "read_file round-trips");
    check(vsn_write_file(c, &fid, (const uint8_t *)"C-CONSUMER-2", 11) == VSN_ERR_OK, "write_file new revision");
    uint32_t *revs = NULL; int nrevs = 0;
    check(vsn_list_revisions(c, &fid, &revs, &nrevs) == VSN_ERR_OK && nrevs >= 2, "revisions tracked");
    uint8_t obuf[8192]; size_t olen = 0;
    check(vsn_commit(c, obuf, sizeof obuf, &olen) == VSN_ERR_OK && olen > 0, "commit produced canonical bytes");
    check(vsn_validate_level(obuf, olen, "Full") == VSN_ERR_OK, "Full validation clean");
    int stable = 0;
    check(vsn_verify_integrity(obuf, olen, &stable) == VSN_ERR_OK, "integrity ok");
    VsnStorageStats st; memset(&st, 0, sizeof st);
    check(vsn_storage_stats(c, &st) == VSN_ERR_OK && st.file_count >= 1, "storage stats file_count >= 1");
    check(vsn_create_with_policy(1) != NULL, "policy 1 (HIGHLY_VERTICAL) constructs");
    check(vsn_create_with_policy(4) != NULL, "policy 4 (HIGHLY_HORIZONTAL) constructs");
    /* SP wire-out/wire-in round-trip: create(policy) -> commit -> scan wire -> open -> read back. */
    VsnContainer *p = vsn_create_with_policy(3); /* HORIZONTAL */
    FileId pfid; memset(&pfid, 0, sizeof pfid);
    vsn_create_file(p, "sp.txt", (const uint8_t *)"SP", 2, &pfid);
    uint8_t pbuf[4096]; size_t plen = 0;
    check(vsn_commit(p, pbuf, sizeof pbuf, &plen) == VSN_ERR_OK, "policy store committed");
    check(sp_on_wire(pbuf, plen) == 3, "SP wire-out: HORIZONTAL=3 present as REC 0x0009/FID 0x0901");
    VsnContainer *rp = vsn_open(pbuf, plen);
    check(rp != NULL, "open (wire-in) parses policy bytes");
    check(rp != NULL && rp->storage_policy == 3, "SP wire-in: policy read back == 3");
    vsn_close(p);
    vsn_close(rp);
    vsn_close(c);

    if (fails == 0) printf("CONSUMER C PASS\n");
    else { printf("CONSUMER C FAIL (%d)\n", fails); return 1; }
    return 0;
}