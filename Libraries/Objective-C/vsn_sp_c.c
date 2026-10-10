/* VSN Storage Policy encode/parse (pure C, Foundation-free).
 *
 * Mirrors the canonical SP record used by VSN.m (vsn_encode_with_policy /
 * vsn_parse_storage_policy) so the SP wire contract can be exercised in
 * environments without GNUstep/Foundation (the conformance image ships only
 * gobjc, which cannot compile the Foundation-based NSData API).
 *
 * Wire layout (13 bytes):
 *   [0..3] "VSN-"   | [4..5] CFV=1 | [6..7] EV=1
 *   [8..9] REC_STORAGE_POLICY=0x0009 | [10] plen=4
 *   [11..12] FID_STORAGE_POLICY=0x0901 | [13] vlen=1 | [14] u8 value
 *
 * Note: this file uses 1-based descriptions above only for readability; the
 * code below is 0-based (buf[0..12]) and byte-identical to VSN.m.
 */
#include <stdint.h>

static const int kVertical = 2; /* default clamp target (STORAGE_POLICY_VERTICAL) */

/* Canonical writer: build the 15-byte container carrying policy (1..4).
 * Layout (canonical, matches COBOL/C): "VSN-" + CFV(0x0001) + EV(0x0001)
 * + REC_STORAGE_POLICY(0x0009) + plen(4) + FID_STORAGE_POLICY(0x0901)
 * + vlen(1) + u8 value. */
void vsn_sp_encode_c(int policy, uint8_t out[15]) {
    int sp = (policy >= 1 && policy <= 4) ? policy : kVertical;
    out[0] = 'V'; out[1] = 'S'; out[2] = 'N'; out[3] = '-';   /* MAGIC    */
    out[4] = 0x00; out[5] = 0x01;                              /* CFV=1    */
    out[6] = 0x00; out[7] = 0x01;                              /* EV=1     */
    out[8] = 0x00; out[9] = 0x09;                              /* REC_SP   */
    out[10] = 4;                                               /* plen=4   */
    out[11] = 0x09; out[12] = 0x01;                            /* FID_SP   */
    out[13] = 1;                                               /* vlen=1   */
    out[14] = (uint8_t)sp;                                     /* value    */
}

/* Canonical reader: extract the u8 policy (1..4) or return 0 if absent.
 * Robust byte-signature scan for [00 09][04][09 01][01] + value. */
int vsn_sp_parse_c(const void* data, int len) {
    if (!data || len < 8) return 0;
    const uint8_t* d = (const uint8_t*)data;
    if (d[0] != 'V' || d[1] != 'S' || d[2] != 'N' || d[3] != '-') return 0;
    int i;
    for (i = 0; i + 6 < len; i++) {
        if (d[i] == 0x00 && d[i + 1] == 0x09 && d[i + 2] == 0x04 &&
            d[i + 3] == 0x09 && d[i + 4] == 0x01 && d[i + 5] == 0x01) {
            return d[i + 6];   /* u8 policy value */
        }
    }
    return 0;
}

