using Vsn;

namespace VsnTest;

/// <summary>P01-P12 Storage Policy corpus tests for C#.</summary>
public class StoragePolicyCorpus
{
    private readonly Dictionary<string, int> _results = new();
    private void Record(string cap, bool pass) => _results[cap] = pass ? 1 : 0;
    private int PassCount() => _results.Values.Sum();
    private void CAP01() { bool ok = (int)StoragePolicy.HIGHLY_VERTICAL == 1 && (int)StoragePolicy.VERTICAL == 2 && (int)StoragePolicy.HORIZONTAL == 3 && (int)StoragePolicy.HIGHLY_HORIZONTAL == 4; Record("P01", ok); }
    private void CAP02() { bool ok = StoragePolicyMapping.Resolve(StoragePolicy.HIGHLY_VERTICAL) == 0x01 && StoragePolicyMapping.Resolve(StoragePolicy.VERTICAL) == 0x01 && StoragePolicyMapping.Resolve(StoragePolicy.HORIZONTAL) == 0x02 && StoragePolicyMapping.Resolve(StoragePolicy.HIGHLY_HORIZONTAL) == 0x02; Record("P02", ok); }
    private void CAP03()
    {
        try { var hv = VsnStore.Create(StoragePolicy.HIGHLY_VERTICAL); byte[] fhv=hv.CreateFile("t",new byte[]{0xAA}); var hb=hv.Commit();
            var h = VsnStore.Create(StoragePolicy.HORIZONTAL); byte[] fha=h.CreateFile("t",new byte[]{0xBB}); var ha=h.Commit();
            Record("P03", ContainerParser.Parse(hb).Mode==0x01 && ContainerParser.Parse(ha).Mode==0x02 && hv.ReadFile(fhv)!=null && h.ReadFile(fha)!=null); }
        catch { Record("P03", false); }
    }
    private void CAP04()
    {
        try { var s1=VsnStore.Create(StoragePolicy.HIGHLY_VERTICAL); s1.CreateFile("f",new byte[]{1}); var b1=s1.Commit();
            var s2=VsnStore.Create(StoragePolicy.HORIZONTAL); s2.CreateFile("f",new byte[]{2}); var b2=s2.Commit();
            Record("P04", ContainerParser.Parse(b1).Mode!=0 && ContainerParser.Parse(b2).Mode!=0 && ContainerParser.Parse(b1).Mode!=ContainerParser.Parse(b2).Mode); }
        catch { Record("P04", false); }
    }
    private void CAP05()
    {
        try { var sHV=VsnStore.Create(StoragePolicy.HIGHLY_VERTICAL); var sV=VsnStore.Create(StoragePolicy.VERTICAL);
            byte[] f1=sHV.CreateFile("doc",new byte[]{0xDE,0xAD}), f2=sV.CreateFile("doc",new byte[]{0xDE,0xAD});
            bool ids = f1.Length == f2.Length; bool cont = sHV.ReadFile(f1) != null && sV.ReadFile(f2) != null;
            var pH=ContainerParser.Parse(sHV.Commit()); var pV=ContainerParser.Parse(sV.Commit());
            Record("P05", ids && cont && pH.Mode==pV.Mode); }
        catch { Record("P05", false); }
    }
    private void CAP06() { try { var s=VsnStore.Create(StoragePolicy.HIGHLY_VERTICAL); s.CreateFile("a",new byte[]{0xAA}); int o1=s.ListObjects().Count; s.CreateFile("b",new byte[]{0xBB}); var s2=VsnStore.Create(StoragePolicy.HORIZONTAL); var r2=VsnStore.Open(s.Commit()); Record("P06", s.ListObjects().Count>=2 && r2.Mode!=0); } catch { Record("P06", false); } }
    private void CAP07()
    {
        try { bool ok=true; foreach(var p in new[] { StoragePolicy.HIGHLY_VERTICAL,StoragePolicy.VERTICAL,StoragePolicy.HORIZONTAL,StoragePolicy.HIGHLY_HORIZONTAL }) { var s=VsnStore.Create(p); byte[] f=s.CreateFile("r",new byte[]{1}); var d=s.Commit(); var r=VsnStore.Open(d); if(r.Mode==0||r.ReadFile(f)==null) ok=false; } Record("P07",ok); } catch { Record("P07",false); }
    }
    private void CAP08()
    {
        try { bool ti=false,tc=false;
            try { new WriterOptions(StoragePolicy.HIGHLY_VERTICAL,null,new OptimizationConfiguration(-1)).OptimizationConfig.Validate(); } catch(InvalidOptimizationConfiguration) { ti=true; }
            try { var c=new WriterOptions(StoragePolicy.HIGHLY_VERTICAL,0x02); _=c.EffectiveWireMode; } catch(PolicyWireModeConflict) { tc=true; }
            Record("P08",ti&&tc); } catch { Record("P08",false); }
    }
    private void CAP09() { try { var sHV=VsnStore.Create(StoragePolicy.HIGHLY_VERTICAL); byte[] f=sHV.CreateFile("s",new byte[]{0x10}); var d=sHV.Commit(); var se=VsnStore.Open(d); var sH=VsnStore.Create(StoragePolicy.HORIZONTAL); byte[] fh=sH.CreateFile("s",new byte[]{0x20}); var dh=sH.Commit(); Record("P09",se.ReadFile(f)!=null&&se.Mode==Constants.ModeModern&&ContainerParser.Parse(dh).Mode==Constants.ModeEnterprise); } catch { Record("P09",false); } }
    private void CAP10() { try { var s=VsnStore.Create(StoragePolicy.HIGHLY_HORIZONTAL); s.CreateFile("p",new byte[]{0xFF}); Record("P10",ContainerParser.Parse(s.Commit()).Mode==Constants.ModeEnterprise); } catch { Record("P10",false); } }
    private void CAP11() { try { var m=VsnStore.Create(Constants.ModeModern); m.CreateFile("mb",new byte[]{1}); var bm=m.Commit(); var e=VsnStore.Create(Constants.ModeEnterprise); e.CreateFile("eb",new byte[]{2}); var be=e.Commit(); Record("P11",ContainerParser.Parse(bm).Mode==Constants.ModeModern&&ContainerParser.Parse(be).Mode==Constants.ModeEnterprise); } catch { Record("P11",false); } }
    private void CAP12() { try {
        bool c1=new WriterOptions(StoragePolicy.HIGHLY_VERTICAL).EffectiveWireMode==0x01;
        bool c2=new WriterOptions(StoragePolicy.VERTICAL).EffectiveWireMode==0x01;
        bool c3=new WriterOptions(StoragePolicy.HORIZONTAL).EffectiveWireMode==0x02;
        bool c4=new WriterOptions(StoragePolicy.HIGHLY_HORIZONTAL).EffectiveWireMode==0x02;
        bool c5=new WriterOptions(StoragePolicy.HIGHLY_VERTICAL,Constants.ModeModern).EffectiveWireMode==0x01;
        bool c6=new WriterOptions(null,Constants.ModeEnterprise).EffectiveWireMode==0x02;
        Record("P12",c1&&c2&&c3&&c4&&c5&&c6); } catch { Record("P12",false); } }

    public void RunAll()
    {
        CAP01();CAP02();CAP03();CAP04();CAP05();CAP06();CAP07();CAP08();CAP09();CAP10();CAP11();CAP12();
        Console.WriteLine("P01: "+(_results["P01"]==1?"PASS":"FAIL"));
        Console.WriteLine("P02: "+(_results["P02"]==1?"PASS":"FAIL"));
        Console.WriteLine("P03: "+(_results["P03"]==1?"PASS":"FAIL"));
        Console.WriteLine("P04: "+(_results["P04"]==1?"PASS":"FAIL"));
        Console.WriteLine("P05: "+(_results["P05"]==1?"PASS":"FAIL"));
        Console.WriteLine("P06: "+(_results["P06"]==1?"PASS":"FAIL"));
        Console.WriteLine("P07: "+(_results["P07"]==1?"PASS":"FAIL"));
        Console.WriteLine("P08: "+(_results["P08"]==1?"PASS":"FAIL"));
        Console.WriteLine("P09: "+(_results["P09"]==1?"PASS":"FAIL"));
        Console.WriteLine("P10: "+(_results["P10"]==1?"PASS":"FAIL"));
        Console.WriteLine("P11: "+(_results["P11"]==1?"PASS":"FAIL"));
        Console.WriteLine("P12: "+(_results["P12"]==1?"PASS":"FAIL"));
        Console.WriteLine("Results: "+PassCount()+"/12 PASS");
        int pc = PassCount();
        string spStatus = pc >= 12 ? "PASS" : "FAIL";
        Console.WriteLine("SP 01-12 " + spStatus + " assertions=" + pc + " ops=4 storage policy wire conformance");
    }
}
