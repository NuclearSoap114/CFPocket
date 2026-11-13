import XCTest
@testable import PocketCore
import TrainingCore

final class PocketCoreTests: XCTestCase {
  let id = try! ProblemID(contest: 123, index:"A1")
  func fixture(index:String="A1",sample:String="1<br>2",extra:String="") -> String {
    """
    <html><head><link rel="canonical" href="https://codeforces.com/contest/123/problem/\(index)"></head><body><div class="problem-statement"><div class="header"><div class="title">\(index). Development fixture</div></div><p>This is an original development fixture, not a Codeforces problem or live result. Given integers $$$n$$$ between 1 and 10, output their sum. This text is intentionally long enough to verify the complete fragment requirement and preserve numeric constraints.</p><div class="input-specification">Read 2 integers.</div><div class="output-specification">Print 1 integer.</div><div class="sample-test"><div class="input"><pre>\(sample)</pre></div><div class="output"><pre>3</pre></div></div>\(extra)</div></body></html>
    """
  }
  func statement() throws -> Statement { try SourceParser.statement(fixture(),id:id,source:id.url) }
  func testVersionIdentityNeverMergesA1A2() throws {
    XCTAssertNotEqual(id,try ProblemID(contest:123,index:"A2"))
    XCTAssertThrowsError(try ProblemID(contest:0,index:"A"))
    XCTAssertThrowsError(try ProblemID(contest:123,index:"A/submit"))
    XCTAssertEqual(try ProblemID(contest:123,index:"a1").id,"123A1")
  }
  func testFullStatementAndSamplesPreserveLines() throws {
    let value=try statement();XCTAssertEqual(value.samples,[Sample(input:"1\n2\n",output:"3\n")]);XCTAssertEqual(value.problem,id)
    let newer=try SourceParser.statement(fixture(sample:"<div class='test-example-line'>1</div><div class='test-example-line'>2</div>"),id:id,source:id.url)
    XCTAssertEqual(newer.samples.first?.input,"1\n2\n")
  }
  func testRejectChallengePartialAndWrongProblem() {
    XCTAssertThrowsError(try SourceParser.statement("<title>Just a moment...</title>",id:id,source:id.url))
    XCTAssertThrowsError(try SourceParser.statement(fixture(index:"A2"),id:id,source:id.url))
    XCTAssertThrowsError(try SourceParser.statement(fixture().replacingOccurrences(of:"/123/problem/A1",with:"/123/problem/A12"),id:id,source:id.url))
    XCTAssertThrowsError(try SourceParser.statement(fixture().replacingOccurrences(of:"<pre>3</pre>",with:""),id:id,source:id.url))
  }
  func testSanitizerRemovesExecutableContentAndUnsafeLinks() throws {
    let s=try SourceParser.sanitize("<script>steal()</script><p onclick='steal()'>hello</p><a href='javascript:steal()'>bad</a><iframe src='https://evil.test'></iframe><img src='https://evil.test/x'><img src='//codeforces.com/picture.png'>",base:id.url)
    XCTAssertFalse(s.contains("script"));XCTAssertFalse(s.contains("onclick"));XCTAssertFalse(s.contains("evil.test"));XCTAssertFalse(s.contains("iframe"));XCTAssertTrue(s.contains("https://codeforces.com/picture.png"))
  }
  func testMetadataHasNoInventedStatementOrMerge() throws {
    let d=Data(#"{"status":"OK","result":{"problems":[{"contestId":123,"index":"A1","name":"First","rating":800,"tags":["math"]},{"contestId":123,"index":"A2","name":"Second","tags":[]}],"problemStatistics":[{"contestId":123,"index":"A1","solvedCount":45}]}}"#.utf8)
    let p=try SourceParser.problemList(d);XCTAssertEqual(p.count,2);XCTAssertEqual(p[0].solvedCount,45);XCTAssertEqual(p[1].key.index,"A2")
    XCTAssertThrowsError(try SourceParser.problemList(Data(#"{"status":"OK","result":{"problems":[]}}"#.utf8)))
    XCTAssertThrowsError(try SourceParser.problemList(Data(#"{"status":"FAILED"}"#.utf8)))
  }
  func testDuplicateMetadataRejected() {
    let row=#"{"contestId":123,"index":"A","name":"x"}"#
    XCTAssertThrowsError(try SourceParser.problemList(Data("{\"status\":\"OK\",\"result\":{\"problems\":[\(row),\(row)]}}".utf8)))
  }
  func testEditorialNotFromRecentBlogOrTitleAlone() throws {
    XCTAssertThrowsError(try SourceParser.editorialAssociation("<div class='roundbox'><h3>Recent posts</h3><a href='/blog/entry/99'>Editorial</a></div>",id:id))
    let association=try SourceParser.editorialAssociation("<div class='roundbox'><div class='caption'>Contest materials</div><a href='/blog/entry/99'>Tutorial</a></div>",id:id)
    XCTAssertEqual(association.blogID,99)
  }
  func editorialData(content:String) throws -> Data { try JSONSerialization.data(withJSONObject:["status":"OK","result":["id":99,"authorHandle":"fixture-author","content":content]]) }
  func testEditorialImageOrMissingExactVariantIsPartial() throws {
    let association=EditorialAssociation(blogID:99,evidence:"Explicit fixture association")
    let base="<h4><a href='/contest/123/problem/A1'>A1</a></h4><p>"+String(repeating:"development proof text ",count:40)+"</p>"
    let full=try SourceParser.editorial(editorialData(content:base),id:id,association:association)
    XCTAssertTrue(full.isUsable)
    let image=try SourceParser.editorial(editorialData(content:base+"<img src='/a.png'>"),id:id,association:association)
    XCTAssertFalse(image.isUsable)
    let other=try SourceParser.editorial(editorialData(content:base.replacingOccurrences(of:"/A1",with:"/A2")),id:id,association:association)
    XCTAssertFalse(other.isUsable)
    let external = try SourceParser.editorial(editorialData(content:base+"<a href='https://example.com/required-proof'>external proof</a>"),id:id,association:association); XCTAssertFalse(external.isUsable)
    let multi = try SourceParser.editorial(editorialData(content:base+"<h4><a href='/contest/123/problem/B'>B</a></h4><p>Other problem secret.</p><a href='https://example.com/'>External only for B</a>"),id:id,association:association); XCTAssertTrue(multi.isUsable); XCTAssertFalse(multi.content.contains("Other problem secret"))
  }
  func testTranslationNumbersFormulasAndQuantifiersBoundary() throws {
    try TranslationGuard.check(original:"n=10 and $$$a_1$$$ has 2",translated:"n=10，$$$a_1$$$ 有 2")
    XCTAssertThrowsError(try TranslationGuard.check(original:"1 <= n <= 10",translated:"1 <= n <= 100"))
    XCTAssertThrowsError(try TranslationGuard.check(original:"$$$a_1$$$",translated:"$$$b_1$$$"))
    // Semantic quantifiers are an explicit manual/model regression requirement, not a claimed deterministic proof.
  }
  func testSSEIgnoresReasoningRequiresDoneAndStop() throws {
    var s=SSEAccumulator()
    try s.accept(line:#"data: {"model":"test","choices":[{"index":0,"delta":{"reasoning_content":"SPOILER","content":"{\"ok\":"},"finish_reason":null}]}"#)
    try s.accept(line:#"data: {"choices":[{"index":0,"delta":{"content":"true}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":4}}"#)
    XCTAssertThrowsError(try s.finish(fallbackModel:"test"))
    try s.accept(line:"data: [DONE]")
    let r=try s.finish(fallbackModel:"test");XCTAssertEqual(r.content,#"{"ok":true}"#);XCTAssertFalse(r.content.contains("SPOILER"));XCTAssertEqual(r.inputTokens,10)
  }
  func testSSERejectsTruncationAndErrors() throws {
    var s=SSEAccumulator();try s.accept(line:#"data: {"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}"#);try s.accept(line:"data: [DONE]")
    XCTAssertThrowsError(try s.finish(fallbackModel:"test"))
    XCTAssertThrowsError(try s.accept(line:#"data: {"error":{"message":"fail"}}"#))
  }
  func testHintProtocolRejectsWrongLevelAndInventedOfficialRead() throws {
    let statement=try statement()
    func response(level:Int,editorial:String?=nil) throws -> TutorResponse {
      let row:[String:Any]=["schemaVersion":1,"intent":TutorIntent.nextHint.rawValue,"problemID":id.id,"statementHash":statement.hash,"editorialHash":editorial as Any? ?? NSNull(),"draftRevision":1,"revealLevel":level,"restatement":"","missingOrAssumed":[],"feedback":"text","evidence":[]]
      return try JSONDecoder().decode(TutorResponse.self,from:JSONSerialization.data(withJSONObject:row))
    }
    XCTAssertThrowsError(try TutorProtocol.validate(response( level:5),intent:.nextHint,statement:statement,editorial:nil,revision:1,allowedLevel:1))
    XCTAssertThrowsError(try TutorProtocol.validate(response(level:1,editorial:"invented"),intent:.nextHint,statement:statement,editorial:nil,revision:1,allowedLevel:1))
  }
  func testContestPolicyRequiresFreshFinishedPractice() {
    let s=ContestSafety(phase:"FINISHED",checkedAt:Date())
    XCTAssertTrue(s.allowsAI(mode:.practice));XCTAssertFalse(s.allowsAI(mode:.virtual));XCTAssertFalse(s.allowsAI(mode:.competition))
    XCTAssertFalse(s.allowsAI(mode:.practice,now:Date().addingTimeInterval(3700)))
    XCTAssertFalse(ContestSafety(phase:"CODING",checkedAt:Date()).allowsAI(mode:.practice))
  }
  func testAtomicPersistenceAndPrivateSeparationAcrossNewStore() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let store=try PocketStorage(root:root);var workspace=Workspace(problem:id);workspace.draft="my original algorithm";workspace.revisions=[DraftRevision(number:1,text:workspace.draft)];try await store.saveWorkspace(workspace)
    let fresh=try PocketStorage(root:root);let loaded=try await fresh.loadWorkspace(id);XCTAssertEqual(loaded.draft,workspace.draft);XCTAssertEqual(loaded.revisions.first?.id,workspace.revisions.first?.id)
    var oversized=workspace;oversized.stdin=String(repeating:"x",count:65_537)
    do{try await store.saveWorkspace(oversized);XCTFail("oversized input persisted")}catch{}
    let unchanged=try await fresh.loadWorkspace(id);XCTAssertEqual(unchanged.stdin,"");XCTAssertEqual(unchanged.draft,workspace.draft)
    try await store.saveStatement(statement());let cached=try await fresh.loadStatement(id);XCTAssertNotNil(cached)
    XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("private/123A1.json").path))
    try await store.clearPrivate();let empty=try await fresh.loadWorkspace(id);XCTAssertTrue(empty.draft.isEmpty);let preserved=try await fresh.loadStatement(id);XCTAssertNotNil(preserved)
  }
  func testNoLocalRunCanInventCFAC() throws {
    let r=LocalRun(revision:CodeRevision(source:"print(1)",language:.python),input:"",expected:"1\n",status:"ok",stdout:"1",stderr:"",durationMS:5,environment:"test only")
    XCTAssertEqual(r.textMatches,true)
    let attempt=SubmissionAttempt(problem:id,revision:r.revision,handle:"test")
    XCTAssertEqual(attempt.state,.awaitingAuthentication);XCTAssertNil(attempt.submissionID);XCTAssertNil(attempt.verdict)
  }
  func testCounterexampleExecutionEvidenceSeparate() {
    let e=CounterexampleEvidence(revisionID:UUID(),input:"1",inputLegality:"assumed",claimedUserOutput:"0",correctOutput:"1",basis:"unexecuted suggestion",executedRunIDs:[])
    XCTAssertFalse(e.hasExecutionEvidence)
  }
  func testObviousSpoilersAndInventedExecutionAreRejected() throws {
    XCTAssertThrowsError(try TutorOutputGuard.check("首先排序，然后使用线段树维护答案",intent:.nextHint,level:1,original:"Read the input."))
    XCTAssertThrowsError(try TutorOutputGuard.check("我已运行并验证你的程序",intent:.step,level:0,original:""))
    try TutorOutputGuard.check("先明确每一步允许改变什么。",intent:.nextHint,level:1,original:"Read the input.")
    try TutorOutputGuard.check("使用线段树维护区间",intent:.nextHint,level:5,original:"")
  }

  func testBudgetFollowsResolvedModelNotTaskSlot() {
    var config=ModelConfiguration();config.maxOutputTokens=4000
    XCTAssertEqual(config.upperCost(inputTokens:12000),0.0084,accuracy:0.0000001)
    config.fast=ModelConfiguration.defaultPro
    XCTAssertEqual(config.upperCost(inputTokens:12000),0.03168,accuracy:0.0000001)
    config.fast="unknown-unpriced-model"
    XCTAssertFalse(config.tariffKnown);XCTAssertFalse(config.upperCost(inputTokens:12000).isFinite)
  }

}
