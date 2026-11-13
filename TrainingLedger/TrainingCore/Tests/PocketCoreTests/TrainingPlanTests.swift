import XCTest
@testable import PocketCore

final class TrainingPlanTests: XCTestCase {
  func group(_ letter: String, count: Int = 2, accepted: Bool = false) throws -> PlanGroup {
    try PlanGroup(id: letter, problems: (1...count).map { PlanProblem(problem: try ProblemID(contest: Int(letter.unicodeScalars.first!.value) * 10 + $0, index: "A"), title: "题目 \(letter)\($0)", accepted: accepted) })
  }
  func testProgressCountsOnlyACAndFixedOrAutomaticGroup() throws {
    var plan = try TrainingPlan(title: "题单", groups: [group("A", accepted: true),group("B"),group("C")], selectedGroup: "C")
    plan.groups[2].problems[0].favorite = true
    XCTAssertEqual(plan.completed,2); XCTAssertEqual(plan.total,6); XCTAssertEqual(plan.favorites,1)
    XCTAssertEqual(plan.currentGroup?.id,"C"); XCTAssertEqual(plan.completedGroups,1)
    plan.selectedGroup = nil; XCTAssertEqual(plan.currentGroup?.id,"B")
    for g in plan.groups.indices { for p in plan.groups[g].problems.indices { plan.groups[g].problems[p].accepted = true } }
    XCTAssertNil(plan.currentGroup); XCTAssertEqual(plan.fraction,1)
    plan.selectedGroup = "A"; XCTAssertEqual(plan.currentGroup?.id,"A")
  }
  func testReimportKeepsBothChecksAndIntentionalUnchecks() throws {
    var existing = try TrainingPlan(title:"旧题单",groups:[group("A")],selectedGroup:"A")
    existing.groups[0].problems[0].accepted = true
    existing.groups[0].problems[1].favorite = true
    var incoming = try TrainingPlan(title:"新版",groups:[group("A",count:3,accepted:true),group("B")])
    incoming.groups[0].problems[0].favorite = true
    let merged = try existing.mergingRoster(incoming)
    XCTAssertTrue(merged.groups[0].problems[0].accepted)
    XCTAssertFalse(merged.groups[0].problems[0].favorite)
    XCTAssertFalse(merged.groups[0].problems[1].accepted)
    XCTAssertTrue(merged.groups[0].problems[1].favorite)
    XCTAssertTrue(merged.groups[0].problems[2].accepted)
    XCTAssertEqual(merged.currentGroup?.id,"A"); XCTAssertEqual(merged.total,5)
  }
  func files() -> [String:String] {
    Dictionary(uniqueKeysWithValues:(65...90).map { value in
      (String(UnicodeScalar(value)!),"### [Title \(value)](https://codeforces.com/problemset/problem/\(value)/A)\n- [ ] AC\n- [x] 收藏\n")
    })
  }
  func testMarkdownImportReadsLowercaseGroupAndBothCheckboxesWithoutExecutingQueries() throws {
    let plan = try ObsidianPlanParser.parse(title:"题单",overview:"---\n训练组: h\n---\n```tasks\nthrow new Error('must not execute');\n```",files:files())
    XCTAssertEqual(plan.currentGroup?.id,"H");XCTAssertEqual(plan.total,26)
    XCTAssertEqual(plan.completed,0);XCTAssertEqual(plan.favorites,26)
  }
  func testIncompleteDuplicateAndUnsafeSourceAreRejected() throws {
    var values = files(); values.removeValue(forKey:"Z")
    XCTAssertThrowsError(try ObsidianPlanParser.parse(title:"题单",overview:"",files:values))
    values=files(); values["A"] = values["A"]!.replacingOccurrences(of:"- [ ] AC",with:"")
    XCTAssertThrowsError(try ObsidianPlanParser.parse(title:"题单",overview:"",files:values))
    values=files(); values["B"] = values["A"]
    XCTAssertThrowsError(try ObsidianPlanParser.parse(title:"题单",overview:"",files:values))
    values=files(); values["A"] = values["A"]!.replacingOccurrences(of:"https://codeforces.com",with:"https://example.com")
    XCTAssertThrowsError(try ObsidianPlanParser.parse(title:"题单",overview:"",files:values))
  }
  func testPersistenceExportValidationAndDeletionEpoch() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let storage=try PocketStorage(root:root)
    let plan=try TrainingPlan(title:"题单",groups:[group("A")],selectedGroup:"A")
    try await storage.saveTrainingPlan(plan,expectedEpoch:0)
    let reopened=try PocketStorage(root:root)
    let read=try await reopened.loadTrainingPlan()
    XCTAssertEqual(read?.groups,plan.groups)
    let exported=try plan.encoded(); XCTAssertEqual(try TrainingPlan.decode(exported).groups,plan.groups)
    var invalid=try JSONSerialization.jsonObject(with:exported) as! [String:Any];invalid["schemaVersion"]=999
    XCTAssertThrowsError(try TrainingPlan.decode(JSONSerialization.data(withJSONObject:invalid)))
    try await storage.clearPrivate()
    do { try await storage.saveTrainingPlan(plan,expectedEpoch:0);XCTFail("Stale plan resurrected") } catch {}
    let cleared=try await storage.loadTrainingPlan();XCTAssertNil(cleared)
  }
  func testActualObsidianRosterAndOptionalExport() throws {
    guard let path=ProcessInfo.processInfo.environment["CFPOCKET_OBSIDIAN_PLAN"] else { throw XCTSkip("Actual user-supplied Obsidian folder optional") }
    let root=URL(fileURLWithPath:path)
    var contents:[String:String]=[:]
    for value in 65...90 { let group=String(UnicodeScalar(value)!);contents[group]=try String(contentsOf:root.appendingPathComponent("cf/\(group).md"),encoding:.utf8) }
    let overview=try String(contentsOf:root.appendingPathComponent("训练总览.md"),encoding:.utf8)
    let plan=try ObsidianPlanParser.parse(title:root.lastPathComponent,overview:overview,files:contents)
    XCTAssertEqual(plan.groups.count,26);XCTAssertEqual(plan.total,170)
    XCTAssertEqual(plan.completed,39);XCTAssertEqual(plan.favorites,5);XCTAssertEqual(plan.completedGroups,6)
    XCTAssertEqual(plan.selectedGroup,"H");XCTAssertEqual(plan.currentGroup?.completed,3)
    XCTAssertEqual(plan.currentGroup?.problems.first(where:{!$0.accepted})?.id,"949C")
    if let output=ProcessInfo.processInfo.environment["CFPOCKET_PLAN_EXPORT"] { try plan.encoded().write(to:URL(fileURLWithPath:output),options:.atomic) }
  }
}
