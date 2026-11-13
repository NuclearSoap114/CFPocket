import XCTest
import PocketCore
import TrainingCore
import SwiftSoup

final class IntegrationTests: XCTestCase {
  func testMarkdownBlocksMathAndHostileHTML() throws {
    let source = URL(string: "https://codeforces.com/contest/4/problem/A")!
    let markdown = #"""
    # 题意
    给定 **整数** $$$a_i \le 10^9$$$，求值。
    - 第一项
    - 第二项

    | 变量 | 含义 |
    | --- | --- |
    | n | 数量 |

    ```cpp
    if (a < b) cout << "x";
    ```
    <script>alert(1)</script>
    [危险链接](javascript:alert(1))
    <img src="https://127.0.0.1/a" onerror="alert(1)">
    """#
    let html = try PocketMarkdown.html(markdown, source: source)
    XCTAssertTrue(html.contains("<h1>题意</h1>"))
    XCTAssertTrue(html.contains("<strong>整数</strong>"))
    XCTAssertTrue(html.contains("<table>")); XCTAssertTrue(html.contains("<ul>"))
    XCTAssertTrue(html.contains(#"$$$a_i \le 10^9$$$"#))
    XCTAssertTrue(html.contains("a &lt; b"))
    XCTAssertFalse(html.contains("<script")); XCTAssertFalse(html.contains("javascript:"))
    XCTAssertFalse(html.contains("onerror")); XCTAssertFalse(html.contains("127.0.0.1"))
  }
  func testCFURLIdentityFromBothOfficialRoutes() throws {
    XCTAssertEqual(try ProblemID(url: URL(string: "https://codeforces.com/problemset/problem/123/A1")!), try ProblemID(contest: 123, index: "A1"))
    XCTAssertEqual(try ProblemID(url: URL(string: "https://codeforces.com/contest/921/problem/01")!).id, "921-01")
    XCTAssertThrowsError(try ProblemID(url: URL(string: "https://evil.example/contest/4/problem/A")!))
    XCTAssertThrowsError(try ProblemID(url: URL(string: "https://codeforces.com/contest/4/submission/12")!))
  }
  func testBrowserRenderedMathIsRestoredOnce() throws {
    let raw = #"<p>x <span class="katex"><span>duplicate visual</span><math><semantics><mi>x</mi><annotation encoding="application/x-tex">a_i\le 10</annotation></semantics></math></span> y</p>"#
    let html = try SourceParser.sanitize(raw, base: URL(string: "https://codeforces.com")!)
    XCTAssertFalse(html.contains("duplicate visual")); XCTAssertFalse(html.contains("<math"))
    XCTAssertEqual(try SwiftSoup.parse(html).text(), #"x $$$a_i\le 10$$$ y"#)
    let pending = #"<span class="MathJax_Preview">n</span><span class="MathJax">nn</span><script type="math/tex">n^2</script>"#
    XCTAssertEqual(try SwiftSoup.parse(SourceParser.sanitize(pending, base: URL(string: "https://codeforces.com")!)).text(), "$$$n^2$$$")
  }
  func testActualLedgerMigrationRoundTripAndIdempotence() async throws {
    guard let path = ProcessInfo.processInfo.environment["CFPOCKET_LEDGER_BACKUP"] else { throw XCTSkip("No user-provided migration backup selected") }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let original = try TrainingRepository.decoder.decode(TrainingArchive.self, from: data)
    try original.validate()
    let merged = try TrainingRepository.importArchive(data, into: TrainingArchive())
    let again = try TrainingRepository.importArchive(data, into: merged)
    XCTAssertEqual(Set(original.people.map(\.id)), Set(again.people.map(\.id)))
    XCTAssertEqual(Set(original.people.flatMap(\.accounts).map(\.id)), Set(again.people.flatMap(\.accounts).map(\.id)))
    XCTAssertEqual(Set(original.submissions.map(\.id)), Set(again.submissions.map(\.id)))
    XCTAssertEqual(original.submissions.count, again.submissions.count)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("training.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try await TrainingRepository(url: url).save(again)
    let reopened = try await TrainingRepository(url: url).load()
    XCTAssertEqual(reopened.submissions, again.submissions)
    XCTAssertEqual(reopened.people, again.people)
  }
}
