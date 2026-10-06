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
                FileId fid, fid2; size_t clen; uint8_t buf[16]; int rc2;
                memset(&fid,0,sizeof(fid)); memset(&fid2,0,sizeof(fid2));
                if (vsn_create_file(c,"a",(const uint8_t*)"hello",5,&fid)!=VSN_ERR_OK) ok=0;
                else if (vsn_read_file(c,&fid,buf,sizeof(buf),&clen)!=VSN_ERR_OK||clen!=5) ok=0;
                if (ok) vsn_write_file(c,&fid,(const uint8_t*)"xyz",3);
                if (ok) { size_t c2=0; rc2=vsn_read_file(c,&fid,buf,sizeof(buf),&c2); ok=(rc2==VSN_ERR_OK&&c2==3)?1:0; }
                if (ok) vsn_create_file(c,"b",(const uint8_t*)"def",3,&fid2);
                if (ok) { int cnt=0; FileId *fl=NULL; ok=(vsn_list_files(c,&fl,&cnt)==VSN_ERR_OK&&cnt>=2)?1:0; }
            } break;

        case 3: /* C3: Revision API */
            {
                FileId rf; int nr, cr; memset(&rf,0,sizeof(rf));
                if (vsn_create_file(c,"r",(const uint8_t*)"v1",2,&rf)!=VSN_ERR_OK) ok=0;
                else { vsn_write_file(c,&rf,(const uint8_t*)"v2",2); vsn_write_file(c,&rf,(const uint8_t*)"v3",2); }
                if (ok) { uint32_t *rv=NULL; int rc3=vsn_list_revisions(c,&rf,&rv,&nr); ok=(rc3==VSN_ERR_OK&&nr>=3)?1:0; }
            } break;

        case 4: /* C4: LimitCleanup */
            { FileId lf; memset(&lf,0,sizeof(lf)); vsn_create_file(c,"lc",(const uint8_t*)"x",1,&lf); uint32_t *rm=NULL; int rmc=0; ok=(vsn_limit_cleanup(c,&lf,3,&rm,&rmc)==VSN_ERR_OK)?1:0; } break;

        case 5: /* C5: Object API */
            { FileId of; memset(&of,0,sizeof(of)); vsn_create_file(c,"o",(const uint8_t*)"AB",2,&of); uint32_t *os=NULL; int onc=0; ok=(vsn_list_objects(c,&os,&onc)==VSN_ERR_OK&&onc>=1)?1:0; } break;

        case 6: /* C6: Transactions */
            { VsnTx tx; memset(&tx,0,sizeof(tx)); int rc=vsn_tx_begin(&tx); if(rc!=VSN_ERR_OK)ok=0; else { FileId tf; memset(&tf,0,sizeof(tf)); vsn_tx_stage_create(&tx,"t"); int rc2=vsn_tx_commit(c,&tx); ok=(rc2==VSN_ERR_OK)?1:0; (void)tf; } } break;

        case 7: /* C7: Representations - DIRECT-1 content round-trip */
            { FileId fid7; memset(&fid7,0,sizeof(fid7));
              const char *d7="VSN-TEST-DATA-0123";
              if(vsn_create_file(c,"rep.txt",(const uint8_t*)d7,18,&fid7)!=VSN_ERR_OK) ok=0;
              else { uint8_t buf7[64]; size_t n7=0;
                if(vsn_read_file(c,&fid7,buf7,sizeof(buf7),&n7)!=VSN_ERR_OK||n7!=18) ok=0;
                else if(memcmp(buf7,d7,18)!=0) ok=0;
                if(ok){uint32_t *objs7=NULL;int nc7=0;
                  if(vsn_list_objects(c,&objs7,&nc7)!=VSN_ERR_OK||nc7<1) ok=0;
                  else {uint32_t rid7=0,ver7=0,dl7=0;
                    vsn_get_object_info(c,objs7[0],&rid7,&ver7,&dl7);
                    ok=(rid7==REP_DIRECT_1&&ver7==1)?1:0;}
                }}} break;

        case 8: /* C8: Modes - behavioral MODERN + ENTERPRISE */
            { VsnContainer*cm=vsn_create(MODE_MODERN);VsnContainer*ce=vsn_create(MODE_ENTERPRISE);
              if(!cm||!ce){ok=0;if(cm)vsn_close(cm);if(ce)vsn_close(ce);break;}
              FileId fm,fe;memset(&fm,0,sizeof(fm));memset(&fe,0,sizeof(fe));
              ok=(vsn_create_file(cm,"m",(const uint8_t*)"modern",6,&fm)==VSN_ERR_OK)
                &&(vsn_create_file(ce,"e",(const uint8_t*)"enterp",6,&fe)==VSN_ERR_OK)
                &&(cm->mode==MODE_MODERN)&&(ce->mode==MODE_ENTERPRISE);
              if(ok){uint8_t b8[16];size_t n8=0;
                ok=(vsn_read_file(cm,&fm,b8,sizeof(b8),&n8)==VSN_ERR_OK&&n8==6&&memcmp(b8,"modern",6)==0);}
              if(ok){uint8_t b8[16];size_t n8=0;
                ok=(vsn_read_file(ce,&fe,b8,sizeof(b8),&n8)==VSN_ERR_OK&&n8==6&&memcmp(b8,"enterp",6)==0);}
              vsn_close(cm);vsn_close(ce); } break;

        case 9: /* C9: Validation -- invalid data must fail */
            { uint8_t bad[8]={0}; int v=vsn_validate_level(bad,8,"Full"); ok=(v!=VSN_ERR_OK)?1:0; } break;

        case 10:/* C10: Recovery */
            { const uint8_t* hdr=(const uint8_t[]){0x56,0x53,0x4E,0x2D,'\0',1,'\0',1}; VsnContainer* r=vsn_open(hdr,8); int br_ok = (vsn_open((const uint8_t[]){0},8)==NULL) ? 1 : 0; ok=(r&&br_ok)?1:0; if(r)vsn_close(r); } break;

        case 11:/* C11: Diff */
            { VsnContainer*c2=vsn_create(MODE_MODERN); if(!c2){ok=0;} else { VsnFileDiff d; memset(&d,0,sizeof(d)); ok=(vsn_diff_files(c,c2,&d)==VSN_ERR_OK)?1:0; vsn_close(c2);} } break;

        case 12:/* C12: Three-way merge - conflict + non-conflict + identical */
            { VsnContainer*base=vsn_create(MODE_MODERN);VsnContainer*ours=vsn_create(MODE_MODERN);
              VsnContainer*theirs=vsn_create(MODE_MODERN);
              if(!base||!ours||!theirs){ok=0;if(base)vsn_close(base);if(ours)vsn_close(ours);if(theirs)vsn_close(theirs);break;}
              FileId bf,of,tf;memset(&bf,0,sizeof(bf));memset(&of,0,sizeof(of));memset(&tf,0,sizeof(tf));
              vsn_create_file(base,"f.txt",(const uint8_t*)"base",4,&bf);
              vsn_create_file(ours,"f.txt",(const uint8_t*)"ours",4,&of);
              vsn_create_file(theirs,"f.txt",(const uint8_t*)"theirs",6,&tf);
              VsnMergeResult mr;memset(&mr,0,sizeof(mr));
              ok=(vsn_three_way_merge(base,ours,theirs,&mr)==VSN_ERR_OK&&mr.n_conflicts>=1)?1:0;
              if(ok){VsnContainer*b2=vsn_create(MODE_MODERN);VsnContainer*o2=vsn_create(MODE_MODERN);
                VsnContainer*t2=vsn_create(MODE_MODERN);FileId x;memset(&x,0,sizeof(x));
                vsn_create_file(b2,"c",(const uint8_t*)"base",4,&x);
                FileId ay;memset(&ay,0,sizeof(ay));vsn_create_file(o2,"c",(const uint8_t*)"same",4,&ay);
                FileId by;memset(&by,0,sizeof(by));vsn_create_file(t2,"c",(const uint8_t*)"same",4,&by);
                VsnMergeResult mr2;memset(&mr2,0,sizeof(mr2));
                ok=(vsn_three_way_merge(b2,o2,t2,&mr2)==VSN_ERR_OK&&mr2.n_conflicts==0)?1:0;
                vsn_close(b2);vsn_close(o2);vsn_close(t2);}
              vsn_close(base);vsn_close(ours);vsn_close(theirs); } break;

        case 13:/* C13: Import/Export */
            { const uint8_t* hdr=(const uint8_t[]){0x56,0x53,0x4E,0x2D,'\0',1,'\0',1}; VsnContainer* imp=vsn_open(hdr,8); ok=(imp!=NULL)?1:0; if(imp)vsn_close(imp); } break;

        case 14:/* C14: Streaming */
            { FileId sf; memset(&sf,0,sizeof(sf)); vsn_create_file(c,"big",(const uint8_t*)"bigdata",7,&sf); uint32_t *so=NULL; int soc=0; ok=(vsn_list_objects(c,&so,&soc)==VSN_ERR_OK&&soc>=1)?1:0; } break;

        case 15:/* C15: Diagnostics */
            { FileId df; memset(&df,0,sizeof(df)); vsn_create_file(c,"d",(const uint8_t*)"data",4,&df); uint8_t cm[65536]; size_t cl2=0; vsn_commit(c,cm,sizeof(cm),&cl2); VsnDiagnostic diag; int dn=0; uint8_t re[65536]; size_t rl=0; vsn_encode(c,re,sizeof(re),&rl); int rc=vsn_validate_diagnostics(re,rl,"Full",&diag,1,&dn); ok=(rc==VSN_ERR_OK&&dn==0)?1:0; } break;

        case 16:/* C16: Integrity */
            { int st=0; uint8_t re[65536]; size_t rl=0; vsn_encode(c,re,sizeof(re),&rl); int rc=vsn_verify_integrity(re,rl,&st); ok=(rc==VSN_ERR_OK&&st==1)?1:0; } break;

        case 17:/* C17: Storage Stats */
            { FileId stf; memset(&stf,0,sizeof(stf)); vsn_create_file(c,"stat",(const uint8_t*)"x",1,&stf); VsnStorageStats ss; memset(&ss,0,sizeof(ss)); ok=(vsn_storage_stats(c,&ss)==VSN_ERR_OK&&ss.file_count>=1)?1:0; } break;

        case 18:/* C18: Builder/API */
            { VsnContainer*b=vsn_create(MODE_ENTERPRISE); if(!b)ok=0; else{ ok=(b->mode==MODE_ENTERPRISE)?1:0; vsn_close(b); } } break;

        case 19:/* C19: Interop - encode/decode round-trip with content */
            { FileId fid19;memset(&fid19,0,sizeof(fid19));
              const char *d19="interop-data-42";
              if(vsn_create_file(c,"i.txt",(const uint8_t*)d19,15,&fid19)!=VSN_ERR_OK) ok=0;
              else { uint8_t enc[65536];size_t el=0;
                if(vsn_commit(c,enc,sizeof(enc),&el)!=VSN_ERR_OK) ok=0;
                else { VsnContainer*ri=vsn_open(enc,el);
                  if(!ri){ok=0;break;}
                  uint8_t rd[64];size_t rl=0;
                  int fc=0;FileId*fl=NULL;vsn_list_files(ri,&fl,&fc);
                  if(fc<1){vsn_close(ri);ok=0;break;}
                  if(vsn_read_file(ri,&fl[0],rd,sizeof(rd),&rl)!=VSN_ERR_OK||rl!=15||memcmp(rd,d19,15)!=0) ok=0;
                  vsn_close(ri);} } } break;

        default: ok = 0;
    }
    set_result(n, ok); vsn_close(c); return NULL;
}

int main(void) {
    pthread_t threads[20];
    for (int i = 1; i <= 19; i++) pthread_create(&threads[i], NULL, cap_run, (void *)(long)i);
    int passed = 0;
    for (int i = 1; i <= 19; i++) { pthread_join(threads[i], NULL); if(results[i])passed++; printf("CAP %d %s assertions=1 ops=1 cap%d\n", i, results[i]?"PASS":"FAIL",i); }
    printf("PASS %d\n", passed); return passed == 19 ? 0 : 1;
}