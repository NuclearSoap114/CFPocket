import XCTest
@testable import PocketCore
final class LuoguTests: XCTestCase {
  let id = try! ProblemID(contest: 4, index: "A")
  func article(_ id: String = "abc12345") -> [String: Any] { ["lid": id, "author": ["name": "测试作者", "uid": 12], "time": 1700000000, "content": "## 思路\n\n计算 $x_1+x_2$。", "upvote": 5] }
  func data(_ rows: [[String: Any]], total: Int? = nil, perPage: Int = 20) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["template": "problem.solution", "status": 200, "data": ["problem": ["pid": "CF4A"], "solutions": ["perPage": perPage, "count": total ?? rows.count, "result": rows]]])
  }
  func testMappingAndDifficulty() throws {
    XCTAssertEqual(try LuoguParser.pid(id), "CF4A")
    XCTAssertThrowsError(try LuoguParser.pid(ProblemID(contest: 100001, index: "A")))
    XCTAssertThrowsError(try LuoguParser.pid(ProblemID(contest: 10, index: "01")))
    let raw = Data(#"{"status":200,"template":"problem.show","data":{"problem":{"pid":"CF4A","name":"Watermelon","difficulty":1}}}"#.utf8)
    XCTAssertEqual(try LuoguParser.problem(raw, pid: "CF4A").difficultyLabel, "入门")
    XCTAssertThrowsError(try LuoguParser.problem(raw, pid: "CF4B"))
  }
  func testIncompleteErrorAndDuplicateAreNotEmptySuccess() throws {
    XCTAssertThrowsError(try LuoguParser.solutions(Data(#"{"status":401}"#.utf8), pid: "CF4A", page: 1)) { XCTAssertTrue($0 is PocketError) }
    XCTAssertThrowsError(try LuoguParser.context("<html>verify</html>"))
    XCTAssertThrowsError(try LuoguParser.solutions(data([], total: 2), pid: "CF4A", page: 1))
    XCTAssertThrowsError(try LuoguParser.solutions(data([article(), article()]), pid: "CF4A", page: 1))
    XCTAssertThrowsError(try LuoguParser.solutions(data([article("../evil")]), pid: "CF4A", page: 1))
    var partial = article(); partial["contentFull"] = false
    XCTAssertThrowsError(try LuoguParser.solutions(data([partial]), pid: "CF4A", page: 1))
    partial = article(); partial["solutionFor"] = ["pid": "CF5A"]
    XCTAssertThrowsError(try LuoguParser.solutions(data([partial]), pid: "CF4A", page: 1))
    XCTAssertEqual(try LuoguParser.solutions(data([]), pid: "CF4A", page: 1).total, 0)
  }
  func testPaginationAuthorshipAndPersistence() async throws {
    let page = try LuoguParser.solutions(data([article()], total: 2, perPage: 1), pid: "CF4A", page: 1)
    XCTAssertTrue(page.hasMore); XCTAssertEqual(page.articles[0].author, "测试作者")
    XCTAssertFalse(try LuoguParser.solutions(data([article("xyz12345")], total: 2, perPage: 1), pid: "CF4A", page: 2).hasMore)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try PocketStorage(root: root); try await store.saveLuoguPage(page, id: id)
    let reopened = try PocketStorage(root: root); let saved = try await reopened.loadLuoguPage(id, page: 1)
    XCTAssertEqual(saved?.articles, page.articles)
    let page2 = try LuoguParser.solutions(data([article("xyz12345")], total: 2, perPage: 1), pid: "CF4A", page: 2)
    try await store.saveLuoguPages([page, page2], id: id)
    let pages = try await reopened.loadLuoguPages(id)
    XCTAssertEqual(pages.count, 2); XCTAssertEqual(pages.last?.articles.first?.id, "xyz12345")
  }
  func testReaderMathCodeImagesAndUnsafeLinks() throws {
    let md = "# 标题\n\n$x_1 + \\frac{a}{b}$\n\n```cpp\n#include <vector>\ncout << 1;\n```\n\n|列|值|\n|--|--|\n|A|B|\n\n![图](https://cdn.luogu.com.cn/upload/image_hosting/test.png)\n\n<script>alert(1)</script><img src=\"https://127.0.0.1/track\" onerror=\"evil()\">"
    let html = try PocketMarkdown.html(md, source: URL(string: "https://www.luogu.com.cn/article/abc12345")!, luogu: true)
    XCTAssertTrue(html.contains("x_1")); XCTAssertTrue(html.contains("&lt;vector&gt;")); XCTAssertTrue(html.contains("<table>")); XCTAssertTrue(html.contains("cdn.luogu.com.cn")); XCTAssertFalse(html.contains("<script>")); XCTAssertFalse(html.contains("onerror")); XCTAssertFalse(html.contains("127.0.0.1"))
    XCTAssertNil(LuoguParser.safeImage("https://user:password@cdn.luogu.com.cn/image.png", base: URL(string: "https://www.luogu.com.cn")!))
  }
}
