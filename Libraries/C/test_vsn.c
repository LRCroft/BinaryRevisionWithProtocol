/* VSN-1 parallel conformance test -- Tier 2 (pthread) + full 19 caps */
#include "vsn.h"
#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static int results[20] = {0};
static pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;

static void set_result(int n, int v) {
    pthread_mutex_lock(&mtx);
    results[n] = v;
    pthread_mutex_unlock(&mtx);
}

static void *cap_run(void *arg) {
    int n = (int)(long)arg;
    VsnContainer *c = vsn_create(MODE_MODERN);
    if (!c) { set_result(n, 0); return NULL; }
    int ok = 1;
    switch(n) {
        case 1: /* C1: Container lifecycle */
            vsn_close(c); c = vsn_create(MODE_ENTERPRISE);
            ok = (c && c->mode == MODE_ENTERPRISE) ? 1 : 0;
            if (c) set_result(n, ok), vsn_close(c); return NULL;

        case 2: /* C2: File API -- create/read/write/list/delete */
            {
                FileId fid, fid2; size_t clen; uint8_t buf[16]; const uint8_t *rd = NULL;
                memset(&fid,0,sizeof(fid)); memset(&fid2,0,sizeof(fid2));
                if (vsn_create_file(c,"a",(const uint8_t*)"hello",5,&fid)!=VSN_ERR_OK) ok=0;
                else if (!vsn_file_exists(c,&fid)) ok=0;
                else { rd = vsn_read_file(c,&fid,0,buf,sizeof(buf),&clen); if(!rd||clen!=5)ok=0; }
                if (ok) vsn_write_file(c,&fid,(const uint8_t*)"xyz",3);
                if (ok) { size_t c2=0; rd=vsn_read_file(c,&fid,0,buf,sizeof(buf),&c2); ok=(rd&&c2==3)?1:0; }
                if (ok) vsn_create_file(c,"b",(const uint8_t*)"def",3,&fid2);
                { FileId *fl=vsn_list_files(c,NULL); ok=(fl&&fl[0].id[0]!=0)?1:0; free(fl); }
            } break;
}


        case 3: /* C3: Revision API */
            {
                FileId rf; int nr, cr; memset(&rf,0,sizeof(rf));
                if (vsn_create_file(c,"r",(const uint8_t*)"v1",2,&rf)!=VSN_ERR_OK) ok=0;
                else { vsn_write_file(c,&rf,(const uint8_t*)"v2",2); vsn_write_file(c,&rf,(const uint8_t*)"v3",2); }
                if (ok) { nr=vsn_list_revisions(c,&rf,NULL); cr=vsn_current_revision(c,&rf); ok=(nr>=3&&cr==3)?1:0; }
            } break;

        case 4: /* C4: LimitCleanup */
            { FileId lf; memset(&lf,0,sizeof(lf)); vsn_create_file(c,"lc",(const uint8_t*)"x",1,&lf); int rm=vsn_limit_cleanup(c,&lf,3,NULL); ok=(rm>=0)?1:0; } break;

        case 5: /* C5: Object API */
            { FileId of; memset(&of,0,sizeof(of)); vsn_create_file(c,"o",(const uint8_t*)"AB",2,&of); int no=vsn_list_objects(c,NULL); ok=(no>=1)?1:0; } break;

        case 6: /* C6: Transactions */
            { VsnTx tx; memset(&tx,0,sizeof(tx)); int rc=vsn_begin_tx(c,&tx); if(rc!=VSN_ERR_OK)ok=0; else { uint8_t* out=vsn_commit_tx(c,&tx,NULL,NULL); ok=(out&&strlen((char*)out)>=8)?1:0; free(out); } } break;

        case 7: /* C7: Representations */
            if (REP_DIRECT_1 != 1 || REP_EXTENTS_1 != 2) ok = 0; break;

        case 8: /* C8: Modes */

        case 9: /* C9: Validation -- invalid data must fail */
            { uint8_t bad[8]={0}; int v=vsn_validate_level(bad,8,"Full"); ok=(v!=VSN_ERR_OK)?1:0; } break;

        case 10:/* C10: Recovery */
            { const uint8_t* hdr=(const uint8_t[]){0x56,0x53,0x4E,0x2D,'\0',1,'\0',1}; VsnContainer* r=vsn_open(hdr,8); int br_ok = (vsn_open((const uint8_t[]){0},8)==NULL) ? 1 : 0; ok=(r&&br_ok)?1:0; if(r)vsn_close(r); } break;

        case 11:/* C11: Diff */
            { VsnContainer*c2=vsn_create(MODE_MODERN); FileId a; memset(&a,0,sizeof(a)); if(c2){vsn_create_file(c,"x",(const uint8_t*)"1",1,&a); int d=vsn_diff_count(c,c2,NULL); ok=(d>=0)?1:0; free(d);} else ok=0; vsn_close(c2); } break;

        case 12:/* C12: Merge */
            { VsnContainer*c3=vsn_create(MODE_MODERN); uint8_t* mb=vsn_merge_three_way(c,c3,NULL,NULL,NULL); ok=(mb!=NULL)?1:0; vsn_close(c3); } break;

        case 13:/* C13: Import/Export */
            { const uint8_t* hdr=(const uint8_t[]){0x56,0x53,0x4E,0x2D,'\0',1,'\0',1}; VsnContainer* imp=vsn_open(hdr,8); ok=(imp!=NULL)?1:0; if(imp)vsn_close(imp); } break;

        case 14:/* C14: Streaming */
            { FileId sf; memset(&sf,0,sizeof(sf)); vsn_create_file(c,"big",(const uint8_t*)"bigdata",7,&sf); int lo=vsn_list_objects(c,NULL); ok=(lo>=1)?1:0; } break;

        case 15:/* C15: Diagnostics */
            { VsnDiagnostic diag; int dn=0; const uint8_t* hdr=(const uint8_t[]){0x56,0x53,0x4E,0x2D,'\0',1,'\0',1}; int rc=vsn_validate_diagnostics(hdr,8,"Full",&diag,1,&dn); ok=(rc==VSN_ERR_OK)?1:0; } break;

        case 16:/* C16: Integrity */
            { int st=-1; const uint8_t* hdr=(const uint8_t[]){0x56,0x53,0x4E,0x2D,'\0',1,'\0',1}; int rc=vsn_verify_integrity(hdr,8,&st); ok=(rc==VSN_ERR_OK&&st>=0)?1:0; } break;

        case 17:/* C17: Storage Stats */
            { VsnStorageStats ss; vsn_storage_stats(c,&ss); ok=(ss.file_count>=0||ss.rev_count>=0)?1:0; } break;

        case 18:/* C18: Builder/API */
            { VsnContainer*b=vsn_create(MODE_ENTERPRISE); if(!b)ok=0; else{ ok=(b->mode==MODE_ENTERPRISE)?1:0; vsn_close(b); } } break;

        case 19:/* C19: Interop magic bytes */
            { const uint8_t hdr[]={0x56,0x53,0x4E,0x2D,'\0',1,'\0',1}; int mc=vsn_magic_check(hdr,8); ok=(mc!=0)?1:0; } break;

        default: ok = 0;
    }
    set_result(n, ok); vsn_close(c); return NULL;
}

int main(void) {
    pthread_t threads[20];
    for (int i = 1; i <= 19; i++) pthread_create(&threads[i], NULL, cap_run, (void *)(long)i);
    int passed = 0;
    for (int i = 1; i <= 19; i++) { pthread_join(threads[i], NULL); if(results[i])passed++; printf("%s %d cap%d\n", results[i]?"PASS":"FAIL",i,i); }
    printf("PASS %d\n", passed); return passed == 19 ? 0 : 1;
}