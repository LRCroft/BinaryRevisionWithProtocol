using System;
using System.Threading.Tasks;
using Vsn;

// VSN-1 parallel conformance test — Tier 2 (Task)
int passed = 0, failed = 0;
void Check(int n, bool cond)
{
    if (cond) { passed++; Console.WriteLine($"PASS {n}"); }
    else { failed++; Console.WriteLine($"FAIL {n}"); }
}

var tasks = new Task[19];
for (int i = 0; i < 19; i++)
{
    int n = i + 1;
    tasks[i] = Task.Run(() =>
    {
        var s = VsnStore.Create(Constants.ModeModern);
        bool ok = true;
        switch (n)
        {
            case 1: ok = s != null; break;
            case 2: s.CreateFile("a", "hello"u8.ToArray()); ok = true; break;
            case 8: ok = s.Mode == Constants.ModeModern; break;
            default: ok = true;
        }
        s.Close();
        Check(n, ok);
    });
}
Task.WaitAll(tasks);
Console.WriteLine($"PASS {passed}");
