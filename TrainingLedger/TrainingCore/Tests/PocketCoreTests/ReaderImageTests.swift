import XCTest
@testable import PocketCore

final class ReaderImageTests: XCTestCase {
  let base = URL(string: "https://www.luogu.com.cn/article/abcdefgh")!
  func testPublicAndLegacyImages() throws {
    XCTAssertEqual(ReaderImagePolicy.url("http://cdn.luogu.org/upload/pic/123.png", base: base)?.absoluteString, "https://cdn.luogu.com.cn/upload/pic/123.png")
    XCTAssertEqual(ReaderImagePolicy.url("//i.loli.net/2020/12/04/a.png", base: base)?.host, "i.loli.net")
    XCTAssertNotNil(ReaderImagePolicy.url("https://raw.githubusercontent.com/github/explore/main/topics/cpp/cpp.png", base: base))
    let html = try PocketMarkdown.html("![图](https://i.loli.net/2020/12/04/a.png)\n\n<img src=\"https://raw.githubusercontent.com/a/b/main/image.png\" onerror=\"evil()\">", source: base, luogu: true)
    XCTAssertTrue(html.contains("i.loli.net")); XCTAssertTrue(html.contains("raw.githubusercontent.com")); XCTAssertFalse(html.contains("onerror")); XCTAssertFalse(html.contains("未通过安全检查"))
  }
  func testLocalExecutableCredentialAndNonstandardPortURLsStayBlocked() {
    for raw in ["", "javascript:alert(1)", "file:///etc/passwd", "data:image/svg+xml,bad", "https://127.0.0.1/x", "https://[::1]/x", "https://router.local/x", "https://localhost/x", "https://user:secret@images.example.com/a", "https://images.example.com:8080/a"] {
      XCTAssertNil(ReaderImagePolicy.url(raw, base: base), raw)
    }
  }
}
