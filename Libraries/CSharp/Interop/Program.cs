// Interop CLI used by the cross-language driver.
//
//   dotnet run -- write <dir>
//   dotnet run -- read  <dir>
//
// `read` prints a JSON report describing every peer artifact it can interpret.
using System.Text.Json;
using Vsn.Tests;

if (args.Length != 2 || (args[0] != "write" && args[0] != "read"))
{
    Console.Error.WriteLine("usage: Interop <write|read> <dir>");
    return 2;
}

if (args[0] == "write")
{
    InteropCommon.WriteAll(args[1]);
    Console.WriteLine(JsonSerializer.Serialize(new { lang = "csharp", wrote = InteropCommon.Scenarios }));
    return 0;
}

var report = new Dictionary<string, object>();
foreach (var peer in new[] { "python", "csharp", "typescript" })
{
    foreach (var s in InteropCommon.Scenarios)
    {
        var file = Path.Combine(args[1], peer, s + ".vsn");
        if (!File.Exists(file)) continue;
        try
        {
            var expected = InteropCommon.Describe(InteropCommon.BuildScenario(s));
            var actual = InteropCommon.Describe(File.ReadAllBytes(file));
            report[$"{peer}/{s}"] = new Dictionary<string, object>
            {
                ["ok"] = InteropCommon.CanonicalJson(actual) == InteropCommon.CanonicalJson(expected),
                ["status"] = actual["recoveryStatus"]!,
            };
        }
        catch (Exception ex)
        {
            report[$"{peer}/{s}"] = new Dictionary<string, object> { ["ok"] = false, ["error"] = ex.Message };
        }
    }
}
Console.WriteLine(JsonSerializer.Serialize(new { lang = "csharp", results = report }));
return 0;
