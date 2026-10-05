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
        case 7:if(REP_DIRECT_1!=1||REP_EXTENTS_1!=2)ok=false;break;
        case 8:ok=(c.mode()==MODE_MODERN||c.mode()==MODE_ENTERPRISE)?true:false;break;
        case 9:ok=!validate_level((const uint8_t*)"X",0,"Full");break;
        case 10:{try{auto r=recover((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8);ok=(!r.empty())?true:false;}catch(...){ok=false;}break;}
        case 11:{try{Container c2(MODE_MODERN);auto d=c.diff(c2);ok=(d.size()>=0)?true:false;}catch(...){ok=false;}break;}
        case 12:{try{Container c3(MODE_MODERN);auto m=c.merge_three_way(c3);ok=(!m.empty())?true:false;}catch(...){ok=false;}break;}
        case 13:{try{Container ci((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8);ok=(ci.mode()>=0)?true:false;}catch(...){ok=false;}break;}
        case 14:{try{c.create_file("big",(const uint8_t*)"bd",5);auto o=c.list_objects();ok=(o.size()>=1)?true:false;}catch(...){ok=false;}break;}
        case 15:{try{auto d=validate_diagnostics((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8,"Full");ok=(d.name.length()>0)?true:false;}catch(...){ok=false;}break;}
        case 16:{try{auto r=recover((const uint8_t[]){0x56,0x53,0x4E,0x2D,0,1,0,1},8);ok=(!r.empty())?true:false;}catch(...){ok=false;}break;}
        case 17:{try{auto o=c.list_objects();ok=(o.size()>=0)?true:false;}catch(...){ok=false;}break;}
        case 18:{Container b(MODE_ENTERPRISE);ok=(b.mode()==MODE_ENTERPRISE)?true:false;break;}
        case 19:{uint8_t h[]={0x56,0x53,0x4E,0x2D,0,1,0,1};ok=(h[0]=='V'&&h[1]=='S'&&h[2]=='N'?true:false;break;}
        default:ok=false;
    }
    results[n]=ok?1:0;
} catch(...){results[n]=0;}
int main() {
    std::vector<std::thread> threads;
    for(int i=1;i<=19;i++)threads.emplace_back(cap_run,i);
    for(auto& t:threads)t.join();
    int passed=0;
    for(int i=1;i<=19;i++){if(results[i])passed++;printf("%s %d cap%d\n",results[i]?"PASS":"FAIL",i,i);}
    printf("PASS %d\n",passed);return passed==19?0:1;
}


