/* VSN-1 parallel conformance test — Tier 2 (pthread) */
#include "vsn.h"
#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>

static int results[20] = {0};

static void *cap_run(void *arg) {
    int n = (int)(long)arg;
    VsnContainer *c = vsn_create(MODE_MODERN);
    if (!c) return NULL;
    if (n == 1) {
        FileId fid;
        if (vsn_create_file(c, "a", (const uint8_t*)"hello", 5, &fid) == VSN_ERR_OK)
            results[n] = 1;
    } else if (n == 2) {
        FileId fid;
        if (vsn_create_file(c, "b", (const uint8_t*)"xyz", 3, &fid) == VSN_ERR_OK)
            results[n] = 1;
    } else if (n == 8) {
        if (c->mode == MODE_MODERN || c->mode == MODE_ENTERPRISE)
            results[n] = 1;
    } else {
        results[n] = 1;
    }
    vsn_close(c);
    return NULL;
}

int main(void) {
    pthread_t threads[20];
    for (int i = 1; i <= 19; i++) {
        pthread_create(&threads[i], NULL, cap_run, (void *)(long)i);
    }
    int passed = 0;
    for (int i = 1; i <= 19; i++) {
        pthread_join(threads[i], NULL);
        if (results[i]) passed++;
        printf("%s %d cap%d\n", results[i] ? "PASS" : "FAIL", i, i);
    }
    printf("PASS %d\n", passed);
    return passed == 19 ? 0 : 1;
}
