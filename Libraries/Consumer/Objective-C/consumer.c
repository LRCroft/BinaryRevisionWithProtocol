/* VSN-1 independent consumer (Objective-C / pure C) -- Storage Policy round-trip.
 *
 * Uses the library's canonical SP encode/parse (vsn_sp_c.c: vsn_sp_encode_c /
 * vsn_sp_parse_c) to verify both wire-out (the canonical REC_STORAGE_POLICY
 * signature is emitted) and wire-in (the library parser reads back the same
 * value) for all four policies (1..4).
 *
 * Built with plain gcc (no Foundation needed) in the vsn-objc image.
 */
#include <stdio.h>
#include <stdint.h>

extern void vsn_sp_encode_c(int policy, uint8_t out[15]);
extern int vsn_sp_parse_c(const void* data, int len);

int has_sig(const uint8_t* b, int n) {
    for (int i = 0; i + 6 < n; i++)
        if (b[i] == 0x00 && b[i + 1] == 0x09 && b[i + 2] == 0x04 &&
            b[i + 3] == 0x09 && b[i + 4] == 0x01 && b[i + 5] == 0x01)
            return 1;
    return 0;
}

int main(void) {
    int bad = 0;
    for (int p = 1; p <= 4; p++) {
        uint8_t buf[15];
        vsn_sp_encode_c(p, buf);               /* wire-out via library encoder */
        int sig = has_sig(buf, 15);
        int got = vsn_sp_parse_c(buf, 15);     /* wire-in via library parser  */
        if (!sig) { printf("FAIL p=%d wire-out signature missing\n", p); bad = 1; }
        if (got != p) { printf("FAIL p=%d got=%d\n", p, got); bad = 1; }
    }
    printf(bad ? "CONSUMER OBJC FAIL\n" : "CONSUMER OBJC PASS\n");
    return bad ? 1 : 0;
}
