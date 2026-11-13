import XCTest
@testable import PocketCore

final class ResultVerdictTests: XCTestCase {
  func makeRun(_ status: String = "ok", expected: String? = "1 2", stdout: String = "1\n2\n") -> LocalRun {
    LocalRun(revision: CodeRevision(source: "test", language: .cpp), input: "", expected: expected, status: status, stdout: stdout, stderr: "", durationMS: 1, environment: "test")
  }
  func testOnlyCompletedMatchingTextIsLocalAC() {
    XCTAssertEqual(ResultVerdict.local(makeRun(), specialJudge: false).code, "AC")
    XCTAssertEqual(ResultVerdict.local(makeRun(stdout: "3"), specialJudge: false).code, "WA")
    XCTAssertEqual(ResultVerdict.local(makeRun(expected: "", stdout: "\n"), specialJudge: false).code, "AC")
    XCTAssertEqual(ResultVerdict.local(makeRun(expected: nil), specialJudge: false).code, "RUN")
    for status in ["compile-error", "runtime-error", "timeout", "output-limit", "compile-timeout", "stopped", "setup-error", "resource-error", "unknown"] {
      let result = ResultVerdict.local(makeRun(status), specialJudge: false)
      XCTAssertNotEqual(result.code, "AC"); XCTAssertNotEqual(result.code, "WA")
    }
  }
  func testSpecialJudgeNeitherMatchNorMismatchClaimsAcceptance() {
    XCTAssertEqual(ResultVerdict.local(makeRun(), specialJudge: true).code, "MATCH")
    XCTAssertEqual(ResultVerdict.local(makeRun(stdout: "another valid construction"), specialJudge: true).code, "DIFF")
  }
  func testBatchCannotAcceptPartialStoppedOrFailedRun() {
    XCTAssertEqual(ResultVerdict.batch([makeRun(), makeRun()], total: 2, specialJudge: false).code, "AC")
    XCTAssertEqual(ResultVerdict.batch([makeRun(), makeRun(stdout: "3")], total: 2, specialJudge: false).code, "WA")
    XCTAssertEqual(ResultVerdict.batch([makeRun(), makeRun("compile-error")], total: 2, specialJudge: false).code, "CE")
    XCTAssertEqual(ResultVerdict.batch([makeRun()], total: 2, specialJudge: false).code, "STOP")
    XCTAssertEqual(ResultVerdict.batch([], total: 0, specialJudge: false).code, "STOP")
    XCTAssertNotEqual(ResultVerdict.batch([makeRun()], total: 1, specialJudge: true).code, "AC")
  }
  func testNewMetadataIsOptionalAndOldRunsRemainReadable() throws {
    let encoder = JSONEncoder(), decoder = JSONDecoder()
    var value = makeRun(); value.batchID = UUID(); value.batchSize = 3; value.sampleNumber = 2
    let bytes = try encoder.encode(value)
    let restored = try decoder.decode(LocalRun.self, from: bytes)
    XCTAssertEqual(restored.batchID, value.batchID); XCTAssertEqual(restored.sampleNumber, 2)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for key in ["batchID", "batchSize", "sampleNumber"] { legacy.removeValue(forKey: key) }
    let old = try decoder.decode(LocalRun.self, from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(old.batchID); XCTAssertEqual(old.textMatches, true)
  }
  func testOfficialVerdictsAndUnconfirmedSend() throws {
    var attempt = SubmissionAttempt(problem: try ProblemID(contest: 4, index: "A"), revision: CodeRevision(source: "x", language: .cpp), handle: "test")
    attempt.verdict = "OK"; attempt.state = .uncertain
    XCTAssertEqual(ResultVerdict.official(attempt).code, "WAIT")
    attempt.state = .final; attempt.submissionID = 123
    let pairs = ["OK": "AC", "WRONG_ANSWER": "WA", "COMPILATION_ERROR": "CE", "RUNTIME_ERROR": "RE", "TIME_LIMIT_EXCEEDED": "TLE", "MEMORY_LIMIT_EXCEEDED": "MLE", "SUBMITTED": "WAIT", "TESTING": "JUDGE", "SOMETHING_NEW": "OTHER", "PARTIAL": "PART"]
    for (raw, code) in pairs { attempt.verdict = raw; XCTAssertEqual(ResultVerdict.official(attempt).code, code) }
    attempt.verdict = nil; XCTAssertEqual(ResultVerdict.official(attempt).code, "WAIT")
    attempt.verdict = "OK"; attempt.testset = "PRETESTS"
    XCTAssertEqual(ResultVerdict.official(attempt).title, "预测试通过")
  }
}
