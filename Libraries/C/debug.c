#include "vsn.h"
#include <stdio.h>
int main(void) {
    VsnContainer *c = vsn_create(MODE_MODERN);
    FileId fid;
    int rc = vsn_create_file(c, "r.txt", (const uint8_t*)"reopen", 6, &fid);
    printf("create_file: %d\n", rc);
    uint8_t buf[4096]; size_t len;
    rc = vsn_commit(c, buf, 4096, &len);
    printf("commit: %d, len: %zu\n", rc, len);
    if (len > 0) {
        printf("magic: %c%c%c%c\n", buf[0],buf[1],buf[2],buf[3]);
        printf("cfv: %d, ev: %d\n", (buf[4]<<8)|buf[5], (buf[6]<<8)|buf[7]);
        /* Try parse */
        VsnContainer c2;
        rc = vsn_parse(buf, len, &c2);
        printf("parse: %d, files=%d revs=%d objs=%d gen=%u\n", rc, c2.file_count, c2.rev_count, c2.obj_count, c2.generation);
        if (rc == VSN_ERR_OK) {
            printf("rev0: id=%u serial=%u presence=%u path=%s\n", c2.revs[0].rev_id, c2.revs[0].object_serial, c2.revs[0].presence, c2.revs[0].path);
            printf("obj0: serial=%u len=%u\n", c2.objects[0].serial, c2.objects[0].len);
            printf("obj0.data[0..2]: %02x %02x %02x\n", c2.objects[0].data[0], c2.objects[0].data[1], c2.objects[0].data[2]);
        }
        /* Hex dump first 60 bytes */
        printf("hex: ");
        for (size_t i = 0; i < len && i < 60; i++) printf("%02x ", buf[i]);
        printf("\n");
    }
    vsn_close(c);
    return 0;
}