import XCTest
import SwiftSoup
@testable import PocketCore

final class ReadingV4Tests: XCTestCase {
  let url = URL(string: "https://codeforces.com/contest/2276/problem/A")!
  func testEscapedLayoutRendersHeadingsListsAndPreservesCodeNewline() throws {
    let text = #"## 解法\n\n先判断 $a \ne b$。\n\n- 第一条\n- 第二条\n\n```cpp\nint main() {\n    cout << '\\n';\n}\n```"#
    let html = try PocketMarkdown.html(text, source: url)
    let document = try SwiftSoup.parse(html)
    XCTAssertEqual(try document.select("h2").text(), "解法")
    XCTAssertEqual(try document.select("li").count, 2)
    let code = try document.select("pre code").text(trimAndNormaliseWhitespace: false)
    XCTAssertTrue(code.contains("int main() {\n"))
    XCTAssertTrue(code.contains(#"cout << '\n';"#))
    XCTAssertTrue(html.contains(#"$a \ne b$"#))
  }
  func testOrdinaryMarkdownAndLiteralEscapeExamplesRemainUnchanged() throws {
    let original = "## 算法\n\n```cpp\ncout << '\\n';\n```\n\nUse `\\n` for newline."
    XCTAssertEqual(PocketMarkdown.normalized(original),original)
    XCTAssertEqual(PocketMarkdown.normalized(#"代码中的 `\n\n` 是字面内容。"#),#"代码中的 `\n\n` 是字面内容。"#)
  }
  func testOnlyMarkdownWrapperIsRemoved() throws {
    let wrapped = "```markdown\n## 思路\n\n```cpp\nint x = 1;\n```\n```"
    let html = try PocketMarkdown.html(wrapped,source:url)
    XCTAssertEqual(try SwiftSoup.parse(html).select("h2").text(),"思路")
    XCTAssertTrue(html.contains("int x = 1;"))
    XCTAssertTrue(try PocketMarkdown.html("```cpp\nint main() {}\n```",source:url).contains("<pre>"))
  }
  func testCodeRemainsExactThroughHTMLAndSanitization() throws {
    let code = #"""
    #include <bits/stdc++.h>
    vector<pair<int, int>> values;
    if (a < b && b > 0) cout << "<script>alert(1)</script>&lt;" << '\n';
    // $x_y$ and \\ commands are literal code
    """# + "\n"
    let document = try SwiftSoup.parse(PocketMarkdown.html("```cpp\n" + code + "```\n\n`vector<int>` and `&lt;`", source:url))
    XCTAssertEqual(try document.select("pre code").text(trimAndNormaliseWhitespace:false),code)
    XCTAssertEqual(try document.select("p code").array().map { try $0.text() },["vector<int>","&lt;"])
    XCTAssertEqual(try document.select("script").count,0)
  }
  func testEscapedTextIsNotReinterpretedAsHTML() throws {
    let document = try SwiftSoup.parse(PocketMarkdown.html("## \\<vector> &amp;\n\nUse \\<tag> and &amp; with **x &lt; y**.\n\n<script>alert(1)</script>",source:url))
    XCTAssertEqual(try document.select("h2").text(),"<vector> &")
    XCTAssertTrue(try document.select("p").text().contains("<tag> and & with x < y"))
    XCTAssertEqual(try document.select("script").count,0)
  }
  func testOldWorkspaceAndUnsentQuestionRoundTrip() throws {
    var value = Workspace(problem:try ProblemID(contest:4,index:"A"));value.draft="旧草稿"
    var json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]
    json.removeValue(forKey:"chatDraft");json.removeValue(forKey:"pendingChatQuestion")
    var migrated = try JSONDecoder().decode(Workspace.self,from:JSONSerialization.data(withJSONObject:json))
    XCTAssertEqual(migrated.draft,"旧草稿");XCTAssertNil(migrated.chatDraft)
    migrated.chatDraft="下一问尚未发送";migrated.pendingChatQuestion="当前问题在等待回复"
    let restored=try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(migrated))
    XCTAssertEqual(restored.chatDraft,migrated.chatDraft);XCTAssertEqual(restored.pendingChatQuestion,migrated.pendingChatQuestion)
  }
  func testCapturedMalformedAIReplyWhenProvided() throws {
    guard let path=ProcessInfo.processInfo.environment["CFPOCKET_READING_RECORD"] else {throw XCTSkip("Optional real on-device reply regression")}
    let json=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))) as! [String:Any]
    let payload=json["payload"] as! [String:Any]
    let records=payload["aiRecords"] as! [[String:Any]]
    let raw=records.last(where:{$0["intent"] as? String == TutorIntent.coach.rawValue})!["response"] as! [String:Any]
    let text=raw["feedback"] as! String
    XCTAssertFalse(text.contains("\n"));XCTAssertGreaterThan(text.components(separatedBy:#"\n"#).count,20)
    let doc=try SwiftSoup.parse(PocketMarkdown.html(text,source:url))
    XCTAssertGreaterThanOrEqual(try doc.select("h2").count,5)
    XCTAssertGreaterThan(try doc.select("li").count,5)
    XCTAssertEqual(try doc.select("pre code").count,1)
    let code=try doc.select("pre code").text(trimAndNormaliseWhitespace: false)
    XCTAssertTrue(code.hasPrefix("#include <bits/stdc++.h>\n"))
    XCTAssertTrue(code.contains(#"cout << -1 << '\n';"#))
    XCTAssertTrue(code.contains("\n    return 0;"))
  }
}
