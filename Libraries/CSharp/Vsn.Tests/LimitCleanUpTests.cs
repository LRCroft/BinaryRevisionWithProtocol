using Vsn;
using Xunit;

namespace Vsn.Tests;

/// <summary>
/// Behavioural tests for the LimitCleanUp library capability.
///
/// LimitCleanUp is a LIBRARY capability, not a VSN-1 protocol rule. It manages
/// canonical history at the Library level and must not alter VSN grammar,
/// identity, or the frozen error registry.
///
/// Contract under test (Libraries/Documentation/library_api_contract.md):
/// scope is one file's history; `limit` is the max retained revisions and must
/// be >= 1; limit 0 is rejected; newest `limit` retained; retained
/// RevisionIds/contents/ObjectSerials never rewritten; head never removed;
/// idempotent; persisted via the normal Commit(); recovery still works.
/// </summary>
public class LimitCleanUpTests
{
    private static byte[] Fid(byte seed) => Enumerable.Repeat(seed, 16).ToArray();

    private static (VsnStore Store, byte[] FileId) StoreWith(int n)
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "v1"u8.ToArray());
        for (var i = 2; i <= n; i++)
            store.WriteFile(fid, System.Text.Encoding.ASCII.GetBytes($"v{i}"));
        return (store, fid);
    }

    [Fact]
    public void OneRevisionLimitFiveRemovesNothing()
    {
        var (store, fid) = StoreWith(1);
        Assert.Empty(store.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 1 }, store.ListRevisions(fid));
    }

    [Fact]
    public void ThreeRevisionsLimitFiveRemovesNothing()
    {
        var (store, fid) = StoreWith(3);
        Assert.Empty(store.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 1, 2, 3 }, store.ListRevisions(fid));
    }

    [Fact]
    public void FiveRevisionsLimitFiveRemovesNothing()
    {
        var (store, fid) = StoreWith(5);
        Assert.Empty(store.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 1, 2, 3, 4, 5 }, store.ListRevisions(fid));
    }

    [Fact]
    public void SixRevisionsLimitFiveKeepsNewestFive()
    {
        var (store, fid) = StoreWith(6);
        Assert.Equal(new ulong[] { 1 }, store.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 2, 3, 4, 5, 6 }, store.ListRevisions(fid));
    }

    [Fact]
    public void TenRevisionsLimitFiveKeepsSixThroughTen()
    {
        var (store, fid) = StoreWith(10);
        Assert.Equal(new ulong[] { 1, 2, 3, 4, 5 }, store.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 6, 7, 8, 9, 10 }, store.ListRevisions(fid));
    }

    [Fact]
    public void LimitOneKeepsOnlyHead()
    {
        var (store, fid) = StoreWith(4);
        Assert.Equal(new ulong[] { 1, 2, 3 }, store.LimitCleanUp(fid, 1));
        Assert.Equal(new ulong[] { 4 }, store.ListRevisions(fid));
    }

    [Fact]
    public void LimitZeroIsRejectedAndHistoryIsUntouched()
    {
        var (store, fid) = StoreWith(3);
        TestVectors.AssertThrowsVsn(() => store.LimitCleanUp(fid, 0), 0x000C);
        Assert.Equal(new ulong[] { 1, 2, 3 }, store.ListRevisions(fid));
    }

    [Fact]
    public void RepeatedCleanupIsIdempotent()
    {
        var (store, fid) = StoreWith(10);
        Assert.Equal(new ulong[] { 1, 2, 3, 4, 5 }, store.LimitCleanUp(fid, 5));
        Assert.Empty(store.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 6, 7, 8, 9, 10 }, store.ListRevisions(fid));
    }

    [Fact]
    public void SmallerThenLargerLimitDoesNotRecreateHistory()
    {
        var (store, fid) = StoreWith(10);
        store.LimitCleanUp(fid, 3);
        Assert.Equal(new ulong[] { 8, 9, 10 }, store.ListRevisions(fid));
        store.LimitCleanUp(fid, 5);
        Assert.Equal(new ulong[] { 8, 9, 10 }, store.ListRevisions(fid));
        Assert.Equal(new ulong[] { 8, 9, 10 },
                     VsnStore.Open(store.Commit()).ListRevisions(fid));
    }

    [Fact]
    public void RetainedRevisionsAndObjectSerialsAreByteIdentical()
    {
        var (store, fid) = StoreWith(10);
        var before = store.ListRevisions(fid)
            .ToDictionary(r => r, r => store.GetRevision(r).ObjectSerial);
        store.LimitCleanUp(fid, 5);
        var reopened = VsnStore.Open(store.Commit());
        foreach (var rid in new ulong[] { 6, 7, 8, 9, 10 })
        {
            var now = reopened.GetRevision(rid).ObjectSerial;
            Assert.Equal(before[rid], now);
            Assert.Equal(store.Materialize(before[rid]!.Value),
                         reopened.Materialize(now!.Value));
        }
    }

    [Fact]
    public void RemovedRevisionsAreUnavailableAfterReopen()
    {
        var (store, fid) = StoreWith(6);
        store.LimitCleanUp(fid, 5);
        var reopened = VsnStore.Open(store.Commit());
        Assert.Equal(new ulong[] { 2, 3, 4, 5, 6 }, reopened.ListRevisions(fid));
        TestVectors.AssertThrowsVsn(() => reopened.GetRevision(1), 0x0009);
    }

    [Fact]
    public void HeadContentPathAndIdentitySurviveCleanup()
    {
        var (store, fid) = StoreWith(6);
        var head = store.GetCurrentRevision(fid);
        var content = store.ReadFile(fid);
        store.LimitCleanUp(fid, 5);
        var reopened = VsnStore.Open(store.Commit());
        Assert.Equal(head, reopened.GetCurrentRevision(fid));
        Assert.Equal(content, reopened.ReadFile(fid));
        Assert.Equal(fid, reopened.GetFileId("a.txt"));
        Assert.Contains(reopened.ListFiles(), e => e.Path == "a.txt");
    }

    [Fact]
    public void RecoveryStillWorksAfterCleanup()
    {
        var (store, fid) = StoreWith(10);
        store.LimitCleanUp(fid, 5);
        var data = store.Commit();
        var result = Recovery.Recover(data);
        Assert.True(result.Recovered);
        Assert.Equal(store.Generation, result.AcceptedGeneration);
        Assert.Equal(new ulong[] { 6, 7, 8, 9, 10 },
                     VsnStore.Open(data).ListRevisions(fid));
    }

    [Fact]
    public void CleanupThenNewCommitThenCleanup()
    {
        var (store, fid) = StoreWith(6);
        store.LimitCleanUp(fid, 5);
        var reopened = VsnStore.Open(store.Commit());
        reopened.WriteFile(fid, "v7"u8.ToArray());
        Assert.Equal(new ulong[] { 2, 3, 4, 5, 6, 7 }, reopened.ListRevisions(fid));
        Assert.Equal(new ulong[] { 2 }, reopened.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 3, 4, 5, 6, 7 }, reopened.ListRevisions(fid));
    }

    [Fact]
    public void ObjectStoreIsPreservedForSharedReferences()
    {
        var (store, fid) = StoreWith(6);
        var objects = store.ListObjects();
        store.LimitCleanUp(fid, 5);
        Assert.Equal(objects, store.ListObjects());
    }

    [Fact]
    public void ScopeIsPerFile()
    {
        var store = VsnStore.Create();
        var a = store.CreateFile("a.txt", "a1"u8.ToArray());
        var b = store.CreateFile("b.txt", "b1"u8.ToArray());
        for (var i = 2; i <= 4; i++)
        {
            store.WriteFile(a, System.Text.Encoding.ASCII.GetBytes($"a{i}"));
            store.WriteFile(b, System.Text.Encoding.ASCII.GetBytes($"b{i}"));
        }
        Assert.Equal(new ulong[] { 1, 3 }, store.LimitCleanUp(a, 2));
        Assert.Equal(new ulong[] { 5, 7 }, store.ListRevisions(a));
        Assert.Equal(new ulong[] { 2, 4, 6, 8 }, store.ListRevisions(b));
    }

    [Fact]
    public void UnknownFileIsRejected()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "v1"u8.ToArray());
        TestVectors.AssertThrowsVsn(() => store.LimitCleanUp(Fid(0xEE), 5), 0x0009);
    }

    [Fact]
    public void FailureDoesNotReportFalseSuccess()
    {
        var (store, fid) = StoreWith(4);
        var before = store.ListRevisions(fid);
        TestVectors.AssertThrowsVsn(() => store.LimitCleanUp(fid, 0), 0x000C);
        Assert.Equal(before, store.ListRevisions(fid));
    }

    [Fact]
    public void NoFileHeadIsLeftDangling()
    {
        var (store, fid) = StoreWith(6);
        store.LimitCleanUp(fid, 5);
        var reopened = VsnStore.Open(store.Commit());
        foreach (var rec in ContainerParser.Parse(store.Commit()).Records)
            if (rec.RType == Constants.RecFileHead)
            {
                var head = rec.GetField(Constants.FidHeadRevId);
                Assert.NotNull(head);
                Assert.Contains(head!.AsUvarint(), reopened.ListRevisions());
            }
    }

    [Fact]
    public void ModeIsUnchangedAndNoNewRecordTypeAppears()
    {
        var (store, fid) = StoreWith(6);
        store.LimitCleanUp(fid, 5);
        var reopened = VsnStore.Open(store.Commit());
        Assert.Equal(Constants.ModeModern, reopened.Mode);
        var allowed = new[]
        {
            Constants.RecFileIdentity, Constants.RecRevision, Constants.RecRevisionSet,
            Constants.RecFileHead, Constants.RecContentObject, Constants.RecCommitMarker,
            Constants.RecModeDeclaration, Constants.RecRepresentationDescriptor,
        };
        foreach (var rec in ContainerParser.Parse(store.Commit()).Records)
            Assert.Contains(rec.RType, allowed);
    }
}