import XCTest
@testable import PocketCore
import TrainingCore

private struct StubHTTP: HTTPGetting {
  let data:Data
  func get(_ url:URL)async throws->Data{data}
}
final class PocketSubmissionTests:XCTestCase {
  func testSubmissionUsesCanonicalContestFormAndSpecificFailureMessages() throws {
    let service = OfficialWebSubmissionAdapter()
    XCTAssertEqual(service.officialURL(problem: try ProblemID(contest: 4, index: "A")).absoluteString, "https://codeforces.com/contest/4/submit")
    XCTAssertTrue(CFWebForm.failureMessage("FORM_ACTION_UNSUPPORTED").contains("地址"))
    XCTAssertTrue(CFWebForm.failureMessage("BASELINE_UNAVAILABLE").contains("无需重新登录"))
    XCTAssertTrue(CFWebForm.failureMessage("VERIFICATION_REQUIRED").contains("验证"))
    XCTAssertNotEqual(CFWebForm.failureMessage("LOGIN_REQUIRED"), CFWebForm.failureMessage("FORM_FIELDS_MISSING"))
  }
  func testSubmissionFreezesCodeWithJSONEscaping() throws {
    let source = "const char *s = \"quote\\\" and newline\\n\";\n// </script> 😀"
    let script = try CFWebForm.submit(problem: ProblemID(contest: 4, index: "A"), source: source, languageID: "89", handle: "Fixture", nonce: UUID())
    let first = try XCTUnwrap(script.components(separatedBy: "\n").first)
    let json = String(first.dropFirst("const input = ".count).dropLast())
    let frozen = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    XCTAssertEqual(frozen["source"] as? String, source)
    XCTAssertEqual(frozen["index"] as? String, "A")
  }
  func data(id:Int=345,contest:Int=123,index:String="A1",handle:String="test",language:String="GNU C++20",verdict:String?="OK")throws->Data{
    var row:[String:Any]=["id":id,"problem":["contestId":contest,"index":index],"author":["members":[["handle":handle]]],"programmingLanguage":language,"passedTestCount":12]
    if let verdict{row["verdict"]=verdict}
    return try JSONSerialization.data(withJSONObject:["status":"OK","result":[row]])
  }
  func attempt()throws->SubmissionAttempt{SubmissionAttempt(problem:try ProblemID(contest:123,index:"A1"),revision:CodeRevision(source:"my exact local source",language:.cpp),handle:"test")}
  func testOfficialVerdictIsAttachedOnlyToExplicitMatchingID()async throws{
    let service=OfficialWebSubmissionAdapter(http:StubHTTP(data:try data()))
    let value=try await service.reconcile(attempt(),submissionID:345)
    XCTAssertEqual(value.state,.final);XCTAssertEqual(value.verdict,"OK");XCTAssertEqual(value.submissionID,345)
    XCTAssertNil(value.sourceVerified)
    XCTAssertTrue(value.note.contains("手动关联"))
    XCTAssertTrue(value.note.contains("尚未核对"))
  }
  func testGNUCompilerLabelVariantsAndVerifiedSourceRetained() async throws {
    for label in ["GNU C++17", "GNU G++20 13.2 (64 bit)", "Clang++20"] {
      let service = OfficialWebSubmissionAdapter(http: StubHTTP(data: try data(language: label)))
      var frozen = try attempt(); frozen.sourceVerified = true
      let value = try await service.reconcile(frozen, submissionID: 345)
      XCTAssertEqual(value.sourceVerified, true); XCTAssertEqual(value.state, .final)
      XCTAssertTrue(value.note.contains("已核对官网提交源码"))
    }
  }
  func testNoVerdictIsJudgingNotAC()async throws{
    let service=OfficialWebSubmissionAdapter(http:StubHTTP(data:try data(verdict:nil)))
    let value=try await service.reconcile(attempt(),submissionID:345);XCTAssertEqual(value.state,.judging);XCTAssertNil(value.verdict)
  }
  func testSubmittedAndTestingRemainPending() async throws {
    for verdict in ["SUBMITTED", "TESTING", ""] {
      let service = OfficialWebSubmissionAdapter(http: StubHTTP(data: try data(verdict: verdict)))
      let value = try await service.reconcile(attempt(), submissionID: 345)
      XCTAssertEqual(value.state, .judging)
      XCTAssertNotEqual(ResultVerdict.official(value).code, "AC")
    }
  }
  func testOfficialMetricsAndLegacySubmissionDecode() async throws {
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data()) as? [String: Any])
    var rows = root["result"] as! [[String: Any]]
    rows[0]["testset"] = "PRETESTS"; rows[0]["timeConsumedMillis"] = 31; rows[0]["memoryConsumedBytes"] = 2048
    root["result"] = rows
    let service = OfficialWebSubmissionAdapter(http: StubHTTP(data: try JSONSerialization.data(withJSONObject: root)))
    let value = try await service.reconcile(attempt(), submissionID: 345)
    XCTAssertEqual(value.testset, "PRETESTS"); XCTAssertEqual(value.timeConsumedMillis, 31); XCTAssertEqual(value.memoryConsumedBytes, 2048)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    for key in ["testset", "timeConsumedMillis", "memoryConsumedBytes"] { legacy.removeValue(forKey: key) }
    let old = try JSONDecoder().decode(SubmissionAttempt.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(old.testset); XCTAssertEqual(old.verdict, "OK")
  }
  func testWrongProblemLanguageHandleAndMissingIDNeverAutoAttach()async throws{
    for bytes in [try data(index:"A2"),try data(handle:"other"),try data(language:"Python 3"),try data(id:346)]{
      let service=OfficialWebSubmissionAdapter(http:StubHTTP(data:bytes))
      do{_ = try await service.reconcile(attempt(),submissionID:345);XCTFail("invalid match accepted")}catch{}
    }
  }
  func testEraseRejectsDelayedOldWorkspaceSave()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let store=try PocketStorage(root:root);let old=Workspace(problem:try ProblemID(contest:123,index:"A1"));let epoch=await store.currentEpoch()
    try await store.saveWorkspace(old,expectedEpoch:epoch);try await store.clearPrivate()
    do{try await store.saveWorkspace(old,expectedEpoch:epoch);XCTFail("erased draft resurrected")}catch{}
    let rows=try await store.allWorkspaces();XCTAssertTrue(rows.isEmpty)
  }
  func testActuallyFetchedAPIEvidenceWhenProvided()throws{
    guard let root=ProcessInfo.processInfo.environment["CFPOCKET_EVIDENCE_ROOT"]else{throw XCTSkip("Use CFPOCKET_EVIDENCE_ROOT for captured official response checks")}
    let path=URL(fileURLWithPath:root).appendingPathComponent("problemset-implementation.json")
    let list=try SourceParser.problemList(Data(contentsOf:path));XCTAssertGreaterThan(list.count,100)
    let all = try SourceParser.problemList(Data(contentsOf:URL(fileURLWithPath:root).appendingPathComponent("problemset-all.json"))); XCTAssertEqual(all.count,11511); XCTAssertTrue(all.contains(where:{$0.key.contest == 921 && $0.key.index == "01"})); XCTAssertEqual(try ProblemID(contest:921,index:"01").id,"921-01")
    let data=try Data(contentsOf:URL(fileURLWithPath:root).appendingPathComponent("editorial-144363.json"))
    let e=try SourceParser.editorial(data,id:ProblemID(contest:2123,index:"A"),association:EditorialAssociation(blogID:144363,evidence:"Manually checked actual 2123A official Contest materials → Tutorial via web source on 2026-11-12; this is not an automated discovery success."))
    XCTAssertTrue(e.isUsable);XCTAssertEqual(e.author,"reirugan");XCTAssertTrue(e.content.contains("spoiler-content"))
    XCTAssertTrue(e.content.contains("Step 4")); XCTAssertFalse(e.content.contains("/contest/2123/problem/B")); XCTAssertFalse(e.content.contains("Modular_multiplicative_inverse"))
    let proof: [String:Any] = ["problemID":e.problem.id,"blogURL":e.source.absoluteString,"author":e.author,"selectedChars":e.content.count,"contentHash":e.hash,"parserVersion":e.parserVersion,"completeness":e.completeness.rawValue,"association":e.association,"reason":e.reason,"input":"Previously captured official API response, not a new network request"]
    print("CFPOCKET_SOURCE_PROOF " + String(data:try JSONSerialization.data(withJSONObject:proof,options:.sortedKeys),encoding:.utf8)!)
  }
}
