// VSN-1 Library Implementation for Objective-C
// Provides Storage Policy encode/parse functionality

#import "VSN.h"
#import <Foundation/Foundation.h>

// Encode with StoragePolicy record (authoritative classification on wire)
NSData* vsn_encode_with_policy(int mode, long long gen, int storagePolicy) {
    int sp = (storagePolicy >= 1 && storagePolicy <= 4) ? storagePolicy : STORAGE_POLICY_VERTICAL;
    
    uint8_t buf[13];
    buf[0] = 'V'; buf[1] = 'S'; buf[2] = 'N'; buf[3] = '-';      // MAGIC
    buf[4] = 0x00; buf[5] = 0x01;                                 // CFV=1, EV=1
    buf[6] = 0x00; buf[7] = 0x09;                                // REC_STORAGE_POLICY = 0x0009
    buf[8] = 4;                                                    // payload length = 4
    buf[9] = 0x09; buf[10] = 0x01;                               // FID_STORAGE_POLICY = 0x0901
    buf[11] = 1;                                                   // value length = 1
    buf[12] = (uint8_t)sp;                                         // u8 policy value
    
    return [NSData dataWithBytes:buf length:13];
}

// Parse storage policy from canonical VSN bytes
int vsn_parse_storage_policy(const void* data, int len) {
    if (!data || len < 13) return 0;  // not found
    const uint8_t* d = (const uint8_t*)data;
    
    // Check magic
    if (d[0] != 'V' || d[1] != 'S' || d[2] != 'N' || d[3] != '-') return 0;
    
    // Scan records starting at byte 8 (after header)
    int i = 8;
    while (i + 6 < len) {
        uint16_t rtype = (d[i] << 8) | d[i+1];
        if (rtype == REC_STORAGE_POLICY) {
            uint8_t plen = d[i+2];
            int ppos = i + 3;
            // Scan payload for FID_STORAGE_POLICY
            for (int j = 0; j < plen - 2 && ppos + 3 < len; j++) {
                if (d[ppos] == 0x09 && d[ppos+1] == 0x01) {
                    uint8_t vlen = d[ppos+2];
                    if (vlen == 1 && ppos + 3 < len) return d[ppos+3];
                }
                ppos++;
            }
        }
        // Advance to next record
        if (i + 3 > len || i + 3 + d[i+2] > len) break;
        i += 3 + d[i+2];
    }
    return 0;  // not found in bytes
}
