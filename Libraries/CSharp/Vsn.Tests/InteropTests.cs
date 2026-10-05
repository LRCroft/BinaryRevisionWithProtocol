using Vsn;
using Xunit;

namespace Vsn.Tests;

public class InteropTests
{
    private static string InteropDir =>
        Environment.GetEnvironmentVariable("VSN_INTEROP_DIR")
        ?? Path.Combine(Path.GetTempPath(), "vsn-interop");

    private static readonly string[] Peers = { "python", "typescript" };

    [Fact]
    public void CSharpWritesAllInteropScenarios()
    {
        InteropCommon.WriteAll(InteropDir);
        foreach (var s in InteropCommon.Scenarios)
            Assert.True(File.Exists(Path.Combine(InteropDir, "csharp", s + ".vsn")), s);
    }

    [Fact]
    public void CSharpRoundTripsItsOwnScenarios()
    {
        InteropCommon.WriteAll(InteropDir); // self-contained: write before reading
        foreach (var s in InteropCommon.Scenarios)
        {
            var expected = InteropCommon.CanonicalJson(InteropCommon.Describe(InteropCommon.BuildScenario(s)));
            var actual = InteropCommon.CanonicalJson(InteropCommon.Describe(
                File.ReadAllBytes(Path.Combine(InteropDir, "csharp", s + ".vsn"))));
            Assert.Equal(expected, actual);
        }
    }

    [Theory]
    [InlineData("python", "basic")]
    [InlineData("python", "extents")]
    [InlineData("python", "enterprise")]
    [InlineData("python", "multifile")]
    [InlineData("typescript", "basic")]
    [InlineData("typescript", "extents")]
    [InlineData("typescript", "enterprise")]
    [InlineData("typescript", "multifile")]
    public void CSharpReadsPeerScenario(string peer, string scenario)
    {
        var file = Path.Combine(InteropDir, peer, scenario + ".vsn");
        if (!File.Exists(file)) return; // peer artifact absent: skip
        var expected = InteropCommon.Describe(InteropCommon.BuildScenario(scenario));
        var actual = InteropCommon.Describe(File.ReadAllBytes(file));
        Assert.Equal(InteropCommon.CanonicalJson(expected), InteropCommon.CanonicalJson(actual));
        Assert.Equal("RECOVERED", actual["recoveryStatus"]);
    }
}
