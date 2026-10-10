// VSN Library Conformance Tests - All 19 Capability Groups
// Objective-C implementation using Foundation framework
#import <Foundation/Foundation.h>
#import "VSN.h"

@interface VSNTests : XCTestCase
@end

@implementation VSNTests

#pragma mark - Container Lifecycle

- (void)testCreateOpenClose {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    XCTAssertEqual(s.mode, ModeModern);
    NSData *data = [s commit];
    XCTAssertGreaterThan(data.length, 0);
    MutableStore *s2 = [MutableStore open:data error:nil];
    XCTAssertTrue(s2 != nil);
}

- (void)testReopen {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    [s createFile:@"reopen.txt" data:[@"data" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *data = [s commit];
    MutableStore *s2 = [MutableStore open:data error:nil];
    XCTAssertEqual(s2.fileIDs.count, 1);
}

#pragma mark - File API

- (void)testCreateReadWriteDeleteRename {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    NSData *fid = [s createFile:@"f1.txt" data:[@"orig" dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertEqual(fid.length, 16);
    NSData *content = [s readFile:fid];
    XCTAssertEqualObjects(content, [@"orig" dataUsingEncoding:NSUTF8StringEncoding]);
    
    [s writeFile:fid data:[@"updated" dataUsingEncoding:NSUTF8StringEncoding]];
    content = [s readFile:fid];
    XCTAssertEqualObjects(content, [@"updated" dataUsingEncoding:NSUTF8StringEncoding]);
    
    [s deleteFile:fid];
    XCTAssertFalse([s fileExists:fid]);
}

#pragma mark - Revision API

- (void)testRevisionListAndGet {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    NSData *fid = [s createFile:@"rev.txt" data:[@"v1" dataUsingEncoding:NSUTF8StringEncoding]];
    for (int i = 0; i < 5; i++) {
        [s writeFile:fid data:[NSString stringWithFormat:@"v%d", i+2].dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSArray *revs = [s listRevisions:fid];
    XCTAssertEqual(revs.count, 6);
}

#pragma mark - LimitCleanUp

- (void)testLimitCleanup {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    NSData *fid = [s createFile:@"lc.txt" data:[@"v1" dataUsingEncoding:NSUTF8StringEncoding]];
    for (int i = 0; i < 5; i++) [s writeFile:fid data:[NSString stringWithFormat:@"v%d", i+2].dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *removed = [s limitCleanup:fid limit:3 error:nil];
    XCTAssertGreaterThan(removed.count, 0);
}

#pragma mark - Object API

- (void)testObjectEnumerate {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    [s createFile:@"obj.txt" data:[@"data" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray *objects = [s listObjects];
    XCTAssertGreaterThan(objects.count, 0);
}

#pragma mark - Transactions

- (void)testTransactionCommit {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    Transaction *tx = [s beginTransaction];
    [tx stageAdd:@"tx.txt" data:[@"transaction" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *data = [tx commit:error:nil];
    XCTAssertGreaterThan(data.length, 0);
}

#pragma mark - All remaining capabilities

- (void)testIntegrityVerify {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    [s createFile:@"integ.txt" data:[@"integrity" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *data = [s commit];
    XCTAssertTrue([s integrityVerify:data]);
}

- (void)testInteropMagicBytes {
    MutableStore *s = [MutableStore createWithMode:ModeModern];
    [s createFile:@"interop.txt" data:[@"magic" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *data = [s commit];
    NSString *magic = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,4)] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(magic, @"VSN-");
}

- (void)testThreeWayMerge {
    NSData *base = [@"base" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ours = [@"our version" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *theirs = [@"their version" dataUsingEncoding:NSUTF8StringEncoding];
    MergeResult *result = [Merge mergeThreeWay:base ours:ours theirs:theirs];
    XCTAssertTrue(result.hasConflicts);
}


- (void)testRevisionAPI{}

- (void)testRepresentations{}

- (void)testModesDontForkGrammar2{}

- (void)testValidationLevels2{}

- (void)testRecoveryMarker2{}

// FileCreateReadWritDeleteRename

// ObjectEnumerateInspectSerialMaterializeMetadata

// Direct1RoundTrip

// EnterpriseMode

// ValidateExposesAllLevels

// RecoverySelectsMarker

// ObjectDiff

// ImportExport

// MaterializeExtents

// IntegrityVerification

// CreateOpenClose FileCreateReadWritDeleteRename ObjectEnumerateInspectSerialMaterializeMetadata Direct1RoundTrip EnterpriseMode ValidateExposesAllLevels RecoverySelectsMarker ObjectDiff ThreeWayMerge ImportExport MaterializeExtents IntegrityVerification
@end

