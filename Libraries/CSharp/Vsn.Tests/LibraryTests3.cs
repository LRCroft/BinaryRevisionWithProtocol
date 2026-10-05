using Vsn;
using Xunit;

namespace Vsn.Tests;

public class TransactionTests
{
    [Fact]
    public void TransactionStageInspectRollback()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "base"u8.ToArray());
        var tx = new Transaction();
        tx.StageUpdate(fid, "changed"u8.ToArray());
        tx.StageCreate("new.txt", "new"u8.ToArray());
        Assert.Equal(2, tx.ChangeCount);
        Assert.Equal("update", tx.Inspect()[0].Operation);
        tx.Rollback();
        Assert.Equal(0, tx.ChangeCount);
        Assert.Equal("base"u8.ToArray(), store.ReadFile(fid));
    }

    [Fact]
    public void TransactionCommitAppliesStagedChangesAndCommits()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "base"u8.ToArray());
        var tx = new Transaction();
        tx.StageUpdate(fid, "updated"u8.ToArray());
        tx.StageDelete(fid);
        var data = tx.Commit(store);
        Assert.False(store.FileExists(fid));
        var re = VsnStore.Open(data);
        Assert.False(re.FileExists(re.GetFileId("a.txt") ?? new byte[16]));
    }

    [Fact]
    public void ExpectedRevisionIdSuccessAndFailureAsPrecondition()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "base"u8.ToArray());
        var ok = new Transaction(1);
        ok.StageUpdate(fid, "ok"u8.ToArray());
        var data = ok.Commit(store);
        // ExpectedRevisionId must NEVER be persisted as canonical state (RC-01).
        Assert.DoesNotContain("expected_revision"u8.ToArray(), data);
        Assert.Equal("RECOVERED", Recovery.Recover(data).Status);
        var store2 = VsnStore.Open(data);
        var bad = new Transaction(1); // head is now 2
        bad.StageUpdate(fid, "no"u8.ToArray());
        TestVectors.AssertThrowsVsn(() => bad.Commit(store2), 0x000D);
    }

    [Fact]
    public void CommitTwiceOnSameTransactionRejected()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "x"u8.ToArray());
        var tx = new Transaction();
        tx.StageCreate("b.txt", "y"u8.ToArray());
        tx.Commit(store);
        TestVectors.AssertThrowsVsn(() => tx.Commit(store), 0x000C);
    }
}
