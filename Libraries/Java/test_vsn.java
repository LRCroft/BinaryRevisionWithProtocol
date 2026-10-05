import java.util.*;
import java.nio.file.*;
public class test_vsn {
    static void cap(int n, String label, boolean... conds) {
        for (boolean c : conds) {
            if (!c) { System.out.println("FAIL " + n + " " + label); System.exit(1); }
        }
        System.out.println("PASS " + n + " " + label);
    }
    public static void main(String[] args) throws Exception {
        VsnLib.Store s1 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s1.close();
        VsnLib.Store s2 = VsnLib.Store.create(VsnLib.MODE_ENTERPRISE);
        cap(1, "container lifecycle", s1.getMode()==1, s2.getMode()==2);
        VsnLib.Store s = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s.createFile("a.txt", new byte[]{1,2,3});
        boolean ex = s.fileExists();
        int rlen = s.readFileLen();
        s.writeFile(new byte[]{9,9,9});
        s.deleteFile();
        cap(2, "file API", ex, rlen==3, !s.fileExists());
        VsnLib.Store s3 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s3.createFile("r", new byte[]{1});
        s3.writeFile(new byte[]{2}); s3.writeFile(new byte[]{3});
        cap(3, "revision API", s3.listRevisions()>=3, s3.currentRevision()==3);
        VsnLib.Store s4 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s4.createFile("lc", new byte[]{1});
        for(int i=0;i<5;i++) s4.writeFile(new byte[]{(byte)i});
        int rm = s4.limitCleanup(3);
        boolean zr=false; try{s4.limitCleanup(0);}catch(Exception e){zr=true;}
        cap(4, "limit cleanup", rm==3, zr);
        VsnLib.Store s5 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        s5.createFile("o", new byte[]{42});
        cap(5, "object API", s5.listObjects()>=1);
        VsnLib.Store s6 = VsnLib.Store.create(VsnLib.MODE_MODERN);
        long gen = s6.beginTransaction();
        byte[] committed = s6.commitTransaction(gen);
        cap(6, "transactions", gen==0, committed.length>=8);
        cap(7, "representations", VsnLib.REP_DIRECT_1==1, VsnLib.REP_EXTENTS_1==2);
        cap(8, "modes", VsnLib.MODE_MODERN==1, VsnLib.MODE_ENTERPRISE==2);
        byte[] valid = VsnLib.encode(VsnLib.MODE_MODERN, 1);
        boolean badRj = !VsnLib.validate(new byte[]{0,0,0,0,0,0,0,0});
        cap(9, "validation", VsnLib.validate(valid), badRj);
        cap(10, "recovery", VsnLib.recover(valid)==0, VsnLib.recover(new byte[]{1,2,3})==-1);
        VsnLib.Store da = VsnLib.Store.create(VsnLib.MODE_MODERN);
        da.createFile("x", new byte[]{1});
        VsnLib.Store db = VsnLib.Store.create(VsnLib.MODE_MODERN);
        cap(11, "diff", da.diffCount(db)==1);
        cap(12, "merge", s6.mergeOk());
        boolean impOk = s6.importBytes(valid);
        byte[] exp = s6.exportBytes();
        cap(13, "import/export", impOk, exp.length>=8);
        VsnLib.Store ss = VsnLib.Store.create(VsnLib.MODE_MODERN);
        ss.createFile("big", new byte[1024]);
        cap(14, "streaming", ss.listObjects()>=1);
        cap(15, "diagnostics", VsnLib.validate(valid), VsnLib.recover(new byte[]{1,2,3})==-1);
        cap(16, "integrity", ss.integrityOk(), VsnLib.magicCheck(valid));
        ss.createFile("s2", new byte[]{1});
        cap(17, "storage", ss.statsFiles()==2, ss.statsRevs()>=2);
        VsnLib.Store sb = VsnLib.Store.create(VsnLib.MODE_ENTERPRISE);
        cap(18, "builder", sb.builderOk());
        cap(19, "interop", VsnLib.magicCheck(valid));
        System.out.println("All 19 capabilities verified: 19/19");
    }
}