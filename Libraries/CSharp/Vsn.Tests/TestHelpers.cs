using Vsn;
using Xunit;

namespace Vsn.Tests;

public static class TestVectors
{
    public static readonly string Dir = Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "TestVectors"));

    public static readonly string[] Names =
        { "DIRECT-01", "DIRECT-02", "DIRECT-03", "EXT-01", "EXT-02-and-EXT-03" };

    public static byte[] Load(string name) =>
        File.ReadAllBytes(Path.Combine(Dir, name + ".vsn"));

    public static VsnException AssertThrowsVsn(Action action, int code)
    {
        var ex = Assert.Throws<VsnException>(action);
        Assert.Equal(code, ex.Code);
        return ex;
    }
}
