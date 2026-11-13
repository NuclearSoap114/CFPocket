import XCTest
@testable import PocketCore

final class PlanSynchronizationTests: XCTestCase {
  func source() -> (String,[String:String]) {
    let files = Dictionary(uniqueKeysWithValues:(65...90).map { value in
      (String(UnicodeScalar(value)!),"### [Title \(value)](https://codeforces.com/problemset/problem/\(value)/A)\r\n- [ ] AC\r\n- [ ] 收藏\r\n")
    })
    return ("---\n训练组: h # keep this note\ncssclasses:\n  - cf-dashboard\n---\n\n```tasks\nall original query text\n```\n",files)
  }
  func plan() throws -> TrainingPlan {
    let (overview,files)=source();return try ObsidianPlanParser.parse(title:"训练",overview:overview,files:files)
  }
  func testThreeWayMergeKeepsIndependentChangesAndUnchecks() throws {
    let base=try plan();var local=base;var remote=base
    local.groups[0].problems[0].accepted=true;remote.groups[0].problems[0].favorite=true
    let merged=try local.mergingObsidian(remote)
    XCTAssertTrue(merged.groups[0].problems[0].accepted);XCTAssertTrue(merged.groups[0].problems[0].favorite)
    XCTAssertFalse(merged.hasUnsyncedChanges)
    var unchecked=merged;unchecked.groups[0].problems[0].accepted=false
    let again=try unchecked.mergingObsidian(merged)
    XCTAssertFalse(again.groups[0].problems[0].accepted);XCTAssertTrue(again.groups[0].problems[0].favorite)
  }
  func testConflictingGroupAndRemovedDirtyProblemDoNotOverwrite() throws {
    var local=try plan();var remote=local
    local.selectedGroup="A";remote.selectedGroup="B"
    XCTAssertThrowsError(try local.mergingObsidian(remote))
    local=try plan();remote=local
    local.groups[0].problems[0].accepted=true;remote.groups.removeFirst()
    XCTAssertThrowsError(try local.mergingObsidian(remote))
  }
  func testUncheckAfterPartiallyFailedPushIsNotMistakenForNoLocalEdit() throws {
    let baseline = try plan(); var local = baseline; var remote = baseline
    local.groups[0].problems[0].accepted = true; local.recordEdits(comparedTo: baseline)
    // The previous push reached this source file, but failed before saving its new baseline.
    remote.groups[0].problems[0].accepted = true
    let beforeUndo = local
    local.groups[0].problems[0].accepted = false; local.recordEdits(comparedTo: beforeUndo)
    XCTAssertTrue(local.hasUnsyncedChanges)
    let merged = try local.mergingObsidian(remote)
    XCTAssertFalse(merged.groups[0].problems[0].accepted)
    XCTAssertFalse(merged.hasUnsyncedChanges)
  }
  func testPatchesPreserveQueriesTitlesSpacingAndCRLF() throws {
    let (overview,files)=source();var value=try plan();value.groups[0].problems[0].favorite=true
    let patched=try ObsidianPlanPatcher.patchGroup(files["A"]!,target:value.groups[0])
    XCTAssertEqual(patched,files["A"]!.replacingOccurrences(of:"[ ] 收藏",with:"[x] 收藏"))
    let updated=try ObsidianPlanPatcher.patchOverview(overview,selected:"A",previous:"H")
    XCTAssertEqual(updated,overview.replacingOccurrences(of:"训练组: h #",with:"训练组: A #"))
    XCTAssertEqual(try ObsidianPlanPatcher.patchOverview(overview,selected:"H",previous:"H"),overview)
  }
  func testExportDoesNotIncludeFolderGrant() throws {
    var value=try plan();value.connection=PlanFolderConnection(bookmark:Data("opaque-private-grant".utf8),folderName:"训练")
    let data=try value.encoded();let decoded=try TrainingPlan.decode(data)
    XCTAssertNil(decoded.connection);XCTAssertEqual(decoded.groups,value.groups)
    XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("bookmark"))
    var legacy = try JSONSerialization.jsonObject(with:data) as! [String:Any]
    legacy.removeValue(forKey:"sourceBaseline")
    let migrated = try TrainingPlan.decode(JSONSerialization.data(withJSONObject:legacy))
    XCTAssertNotNil(migrated.sourceBaseline);XCTAssertFalse(migrated.hasUnsyncedChanges)
  }
  func testRealCoordinatedFolderRoundTripAndBackups() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder=root.appendingPathComponent("Notes")
    let backups=root.appendingPathComponent("backups")
    defer { try? FileManager.default.removeItem(at:root) }
    try FileManager.default.createDirectory(at:folder.appendingPathComponent("cf"),withIntermediateDirectories:true)
    let (overview,files)=source()
    try Data(overview.utf8).write(to:folder.appendingPathComponent("训练总览.md"))
    for (group,text) in files { try Data(text.utf8).write(to:folder.appendingPathComponent("cf/\(group).md")) }
    var local=try plan();local.groups[0].problems[0].accepted=true;local.selectedGroup="A"
    // The other application changes a separate checkbox before sync.
    try Data(files["A"]!.replacingOccurrences(of:"[ ] 收藏",with:"[x] 收藏").utf8).write(to:folder.appendingPathComponent("cf/A.md"))
    var result=try await ObsidianPlanFolder.synchronize(root:folder,local:local,backupDirectory:backups)
    XCTAssertTrue(result.groups[0].problems[0].accepted);XCTAssertTrue(result.groups[0].problems[0].favorite)
    XCTAssertFalse(result.hasUnsyncedChanges)
    XCTAssertEqual(try String(contentsOf:folder.appendingPathComponent("cf/A.md"),encoding:.utf8),files["A"]!.replacingOccurrences(of:"[ ]",with:"[x]"))
    XCTAssertEqual(try String(contentsOf:folder.appendingPathComponent("cf/B.md"),encoding:.utf8),files["B"])
    XCTAssertEqual(try String(contentsOf:folder.appendingPathComponent("训练总览.md"),encoding:.utf8),overview.replacingOccurrences(of:"训练组: h #",with:"训练组: A #"))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:backups,includingPropertiesForKeys:nil).count,1)
    // A local uncheck and an unrelated remote AC both survive the next round trip.
    result.groups[0].problems[0].accepted=false
    try Data(files["B"]!.replacingOccurrences(of:"[ ] AC",with:"[x] AC").utf8).write(to:folder.appendingPathComponent("cf/B.md"))
    let second=try await ObsidianPlanFolder.synchronize(root:folder,local:result,backupDirectory:backups)
    XCTAssertFalse(second.groups[0].problems[0].accepted);XCTAssertTrue(second.groups[1].problems[0].accepted)
    XCTAssertTrue(second.groups[0].problems[0].favorite)
    // A missing source prevents partial publication.
    try FileManager.default.removeItem(at:folder.appendingPathComponent("cf/Z.md"))
    let before=try Data(contentsOf:folder.appendingPathComponent("cf/A.md"))
    var dirty=second;dirty.groups[0].problems[0].accepted=true
    do { _ = try await ObsidianPlanFolder.synchronize(root:folder,local:dirty,backupDirectory:backups);XCTFail("Incomplete folder accepted") } catch {}
    XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent("cf/A.md")),before)
  }
}
