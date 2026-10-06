/* VSN-1 C++ parallel conformance test -- full 19 caps */
#include "vsn.hpp"
#include <cstdio>
#include <thread>
#include <vector>
#include <cstring>
using namespace vsn;
static int results[20]={0};

static void cap_run(int n) {
    try { Container c(MODE_MODERN); bool ok=true; switch(n) {
        case 1: { Container c2(MODE_ENTERPRISE); ok=(c2.mode()==MODE_ENTERPRISE)?true:false; } break;
        case 2:{try{auto fid=c.create_file("a",(const uint8_t*)"hello",5);auto rd=c.read_file(fid);ok=(rd.size()==5)?true:false;c.write_file(fid,(const uint8_t*)"xyz",3);rd=c.read_file(fid);ok=(ok&&rd.size()==3)?true:false;}catch(...){ok=false;}break;}
        case 3:{try{auto fid=c.create_file("r",(const uint8_t*)"v1",2);c.write_file(fid,(const uint8_t*)"v2",2);c.write_file(fid,(const uint8_t*)"v3",2);auto r=c.list_revisions(fid);ok=(r.size()>=3)?true:false;}catch(...){ok=false;}break;}
        case 4:{try{auto fid=c.create_file("lc",(const uint8_t*)"x",1);for(int i=0;i<5;i++)c.write_file(fid,(const uint8_t*)"a",1);(void)c.limit_cleanup(fid,3);}catch(...){ok=false;}break;}
        case 5:{try{c.create_file("o",(const uint8_t*)"AB",2);auto o=c.list_objects();ok=(o.size()>=1)?true:false;}catch(...){ok=false;}break;}
        case 6:{try{auto out=c.commit();ok=(out.size()>=8)?true:false;}catch(...){ok=false;}break;}
        case 7:{try{auto fid=c.create_file("rep",(const uint8_t*)"VSN-TEST-DATA-0123",18);auto rd=c.read_file(fid);ok=(rd.size()==18&&memcmp(rd.data(),"VSN-TEST-DATA-0123",18)==0)?true:false;}catch(...){ok=false;}break;}
        case 8:{try{Container cm(MODE_MODERN);Container ce(MODE_ENTERPRISE);auto fm=cm.create_file("m",(const uint8_t*)"modern",6);auto fe=ce.create_file("e",(const uint8_t*)"enterp",6);auto rm=cm.read_file(fm);auto re=ce.read_file(fe);ok=(cm.mode()==MODE_MODERN&&ce.mode()==MODE_ENTERPRISE&&rm.size()==6&&memcmp(rm.data(),"modern",6)==0&&re.size()==6&&memcmp(re.data(),"enterp",6)==0)?true:false;}catch(...){ok=false;}break;}
        case 9:ok=!validate_level((const uint8_t*)"X",0,"Full");break;
        case 10:{try{auto r=recover((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8);ok=(!r.empty())?true:false;}catch(...){ok=false;}break;}
        case 11:{try{c.create_file("x",(const uint8_t*)"1",1);auto f1=c.list_files();Container c2(MODE_MODERN);auto f2=c2.list_files();ok=(f1.size()>f2.size())?true:false;}catch(...){ok=false;}break;}
        case 12:{try{Container base(MODE_MODERN);Container ours(MODE_MODERN);Container theirs(MODE_MODERN);base.create_file("f",(const uint8_t*)"base",4);ours.create_file("f",(const uint8_t*)"ours",4);theirs.create_file("f",(const uint8_t*)"theirs",6);VsnMergeResult mr;memset(&mr,0,sizeof(mr));int rc=vsn_three_way_merge(base.raw(),ours.raw(),theirs.raw(),&mr);ok=(rc==VSN_ERR_OK&&mr.n_conflicts>=1)?true:false;Container b2(MODE_MODERN);Container o2(MODE_MODERN);Container t2(MODE_MODERN);b2.create_file("c",(const uint8_t*)"base",4);o2.create_file("c",(const uint8_t*)"same",4);t2.create_file("c",(const uint8_t*)"same",4);VsnMergeResult mr2;memset(&mr2,0,sizeof(mr2));ok=(ok&&vsn_three_way_merge(b2.raw(),o2.raw(),t2.raw(),&mr2)==VSN_ERR_OK&&mr2.n_conflicts==0)?true:false;}catch(...){ok=false;}break;}
        case 13:{try{Container ci((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8);ok=(ci.mode()==MODE_MODERN)?true:false;}catch(...){ok=false;}break;}
        case 14:{try{auto fid=c.create_file("big",(const uint8_t*)"bd",2);auto rd=c.read_file(fid);ok=(rd.size()==2&&memcmp(rd.data(),"bd",2)==0)?true:false;}catch(...){ok=false;}break;}
        case 15:{try{auto d=validate_diagnostics((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8,"Full");ok=(d.name.length()>0)?true:false;}catch(...){ok=false;}break;}
        case 16:{try{auto r=recover((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8);ok=(!r.empty())?true:false;}catch(...){ok=false;}break;}
        case 17:{try{c.create_file("stat",(const uint8_t*)"x",1);auto o=c.list_objects();ok=(o.size()>=1)?true:false;}catch(...){ok=false;}break;}
        case 18:{Container b(MODE_ENTERPRISE);ok=(b.mode()==MODE_ENTERPRISE)?true:false;break;}
        case 19:{try{auto fid=c.create_file("i",(const uint8_t*)"interop-data-42",15);auto enc=c.commit();Container ri(enc.data(),enc.size());auto rl=ri.list_files();ok=(rl.size()>=1)?true:false;if(ok){auto rd=ri.read_file(rl[0]);ok=(rd.size()==15&&memcmp(rd.data(),"interop-data-42",15)==0)?true:false;}}catch(...){ok=false;}break;}
        default:ok=false;
    }
    results[n]=ok?1:0;
} catch(...){results[n]=0;}
}
int main() {
    std::vector<std::thread> threads;
    for(int i=1;i<=19;i++)threads.emplace_back(cap_run,i);
    for(auto& t:threads)t.join();
    int passed=0;
    for(int i=1;i<=19;i++){if(results[i])passed++;printf("CAP %d %s assertions=1 ops=1 cap%d\n",i,results[i]?"PASS":"FAIL",i);}
    printf("PASS %d\n",passed);return passed==19?0:1;
}


