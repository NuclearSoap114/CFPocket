import Foundation
import SwiftSoup
import TrainingCore

public struct ProblemListCache: Codable, Sendable { public let fetchedAt: Date; public let problems: [PocketProblem] }
public actor ProblemRepository {
  private let http: any HTTPGetting
  public init(http: any HTTPGetting = PublicHTTPClient()) { self.http = http }
  public func list() async throws -> ProblemListCache {
    let data = try await http.get(URL(string: "https://codeforces.com/api/problemset.problems")!)
    return ProblemListCache(fetchedAt: Date(), problems: try SourceParser.problemList(data))
  }
  public func statement(_ id: ProblemID) async throws -> Statement {
    let data = try await http.get(id.url)
    guard let html = String(data: data, encoding: .utf8) else { throw PocketError.source("题面编码无法识别，保留已有缓存。") }
    return try SourceParser.statement(html, id: id, source: id.url)
  }
  public func safety(_ id: ProblemID) async throws -> ContestSafety {
    let data = try await http.get(URL(string: "https://codeforces.com/api/contest.list?gym=false")!)
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard root?["status"] as? String == "OK", let contests = root?["result"] as? [[String: Any]], let contest = contests.first(where: { $0["id"] as? Int == id.contest }), let phase = contest["phase"] as? String else { throw PocketError.source("无法核实比赛状态，AI 保持关闭。") }
    return ContestSafety(phase: phase, checkedAt: Date())
  }
  /// Only links explicitly published as a Tutorial in this contest's sidebar qualify.
  public func editorial(_ id: ProblemID) async throws -> EditorialEvidence {
    let url = URL(string: "https://codeforces.com/contest/\(id.contest)")!
    let data = try await http.get(url)
    guard let html = String(data: data, encoding: .utf8) else { throw PocketError.source("比赛页面无法读取。") }
    let association = try SourceParser.editorialAssociation(html, id: id)
    let body = try await http.get(URL(string: "https://codeforces.com/api/blogEntry.view?blogEntryId=\(association.blogID)")!)
    return try SourceParser.editorial(body, id: id, association: association)
  }
}
public struct EditorialAssociation: Sendable {
  public let blogID: Int
  public let evidence: String
  public init(blogID: Int, evidence: String) { self.blogID = blogID; self.evidence = evidence }
}
public enum SourceParser {
  public static let version = "cf-fragment-1.3"
  public static func problemList(_ data: Data) throws -> [PocketProblem] {
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard json?["status"] as? String == "OK", let result = json?["result"] as? [String: Any], let rows = result["problems"] as? [[String: Any]], !rows.isEmpty else { throw PocketError.source("官方题库没有返回有效列表，旧缓存未改变。") }
    var counts: [String: Int] = [:]
    for r in result["problemStatistics"] as? [[String: Any]] ?? [] {
      if let c = r["contestId"] as? Int, let i = r["index"] as? String { if let key = try? ProblemID(contest: c, index: i) { counts[key.id] = r["solvedCount"] as? Int } }
    }
    var seen = Set<ProblemID>(); var output: [PocketProblem] = []
    for row in rows {
      // acmsguru/other custom problemsets have no contestId and are intentionally excluded.
      guard let contest = row["contestId"] as? Int else { continue }
      guard let index = row["index"] as? String, let name = row["name"] as? String, !name.isEmpty else { throw PocketError.source("题库中出现不完整记录。") }
      let id = try ProblemID(contest: contest, index: index)
      guard seen.insert(id).inserted else { throw PocketError.source("题库返回重复题号，未覆盖缓存。") }
      guard let tags = row["tags"] as? [String], tags.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
        row["rating"] == nil || ((row["rating"] as? Int).map { $0 > 0 } == true) else { throw PocketError.source("CF 难度或标签字段不完整，未覆盖缓存。") }
      output.append(PocketProblem(key: id, name: name, rating: row["rating"] as? Int, tags: tags, solvedCount: counts[id.id]))
    }
    guard !output.isEmpty else { throw PocketError.source("题库没有可识别的比赛题。") }; return output
  }
  public static func statement(_ html: String, id: ProblemID, source: URL, now: Date = Date()) throws -> Statement {
    let doc = try SwiftSoup.parse(html, source.absoluteString)
    guard let statement = try doc.select(".problem-statement").first(), let header = try statement.select(".header .title").first(), try statement.select(".input-specification").size() > 0, try statement.select(".output-specification").size() > 0 else { throw PocketError.blocked("未取得完整题面；可能需要在官方网页完成站点验证。缓存保持不变。") }
    try canonicalizeMath(in: statement)
    let title = try header.text()
    guard title.hasPrefix(id.index + "."), try statement.text().count > 180 else { throw PocketError.source("题号或题面完整性核对失败。") }
    // Canonical URLs, if supplied, must agree; versions A1/A2 are never merged.
    for link in try doc.select("link[rel=canonical]").array() {
      let href = try link.attr("href")
      guard let canonical = safeCFURL(href, base: source), canonical.path == "/contest/\(id.contest)/problem/\(id.index)" || canonical.path == "/problemset/problem/\(id.contest)/\(id.index)" else { throw PocketError.source("题面与请求题号不一致。") }
    }
    let ins = try statement.select(".sample-test .input pre").array(), outs = try statement.select(".sample-test .output pre").array()
    guard ins.count == outs.count else { throw PocketError.source("样例输入输出数量不一致，未保存不完整题面。") }
    let samples = try zip(ins, outs).map { Sample(input: try preText($0), output: try preText($1)) }
    let plain = try statement.text()
    let sanitized = try sanitize(statement.outerHtml(), base: source)
    return Statement(problem: id, title: title, html: sanitized, plainText: plain, samples: samples, fetchedAt: now, source: source, hash: fingerprint(sanitized), parserVersion: version, requiresSpecialJudge: plain.lowercased().contains("interactive") || plain.lowercased().contains("any valid") || plain.lowercased().contains("absolute or relative error"))
  }
  /// Browser-captured pages may contain visual + assistive copies of a formula.
  /// Restore authoritative TeX before cleaning, rather than flattening both visual layers.
  private static func canonicalizeMath(in root: Element) throws {
    for script in try root.select("script[type^=math/tex]").array() {
      let tex = script.data()
      guard !tex.isEmpty else { throw PocketError.source("网页中的公式尚未加载完整，请稍后重新读取。") }
      if let previous = try script.previousElementSibling(), previous.hasClass("MathJax") || previous.hasClass("MathJax_Display") {
        if let preview = try previous.previousElementSibling(), preview.hasClass("MathJax_Preview") { try preview.remove() }
        try previous.remove()
      }
      let delimiter = try script.attr("type").contains("mode=display") ? "$$" : "$$$"
      try script.replaceWith(TextNode(delimiter + tex + delimiter, ""))
    }
    for wrapper in try root.select(".katex, .MathJax, .MathJax_Display, mjx-container, math").array() {
      guard wrapper.parent() != nil else { continue }
      if let tex = try wrapper.select("annotation[encoding=application/x-tex]").first() {
        let source = try tex.text(trimAndNormaliseWhitespace: false)
        guard !source.isEmpty else { throw PocketError.source("公式缺少原始 TeX，未保存不完整题面。") }
        try wrapper.replaceWith(TextNode("$$$" + source + "$$$", ""))
      } else if try wrapper.tagName() == "math" || wrapper.select("math").size() > 0 {
        throw PocketError.source("这份网页的公式没有可还原的 TeX。请重新获取官方原始题面，原缓存保留。")
      }
    }
    try root.select(".MathJax_Preview").remove()
  }
  public static func sanitize(_ html: String, base: URL, luogu: Bool = false) throws -> String {
    let doc = try SwiftSoup.parseBodyFragment(html, base.absoluteString)
    try canonicalizeMath(in: doc)
    try doc.select("script, style, iframe, object, embed, form, input, button, link, meta, svg, math, video, audio").remove()
    let allowed = Set(["div","span","p","br","pre","code","h1","h2","h3","h4","h5","h6","hr","del","strong","b","em","i","sub","sup","ul","ol","li","table","thead","tbody","tr","th","td","img","a","blockquote"])
    for e in try doc.body()!.getAllElements().array().reversed() where e.tagName() != "body" {
      if !allowed.contains(e.tagName()) { _ = try e.unwrap(); continue }
      let href = try e.attr("href"), src = try e.attr("src"), cls = try e.attr("class"), alt = try e.attr("alt")
      for attr in e.getAttributes()?.asList() ?? [] { try e.removeAttr(attr.getKey()) }
      // Only static classes used by the renderer are retained; event handlers and inline CSS are gone.
      let classes = cls.split(separator: " ").filter { $0.range(of: "^[a-zA-Z0-9_+.-]+$", options: .regularExpression) != nil }.joined(separator: " ")
      if !classes.isEmpty { try e.attr("class", classes) }
      if e.tagName() == "a", let u = luogu ? LuoguParser.safeLink(href, base: base) : safeCFURL(href, base: base) { try e.attr("href", u.absoluteString) }
      if e.tagName() == "img" {
        if let u = luogu ? LuoguParser.safeImage(src, base: base) : safeImageURL(src, base: base) { try e.attr("src", u.absoluteString); try e.attr("alt", alt.isEmpty ? "文章配图（离线时可能不可用）" : alt); try e.attr("referrerpolicy", "no-referrer"); try e.attr("loading", "lazy") }
        else { _ = try e.replaceWith(TextNode("图片链接无效，无法加载", "")) }
      }
    }
    return try doc.body()!.html()
  }
  public static func safeCFURL(_ string: String, base: URL) -> URL? {
    guard let u = URL(string: string, relativeTo: base)?.absoluteURL, u.scheme == "https", u.user == nil, u.password == nil, u.host == "codeforces.com" else { return nil }; return u
  }
  public static func safeImageURL(_ string: String, base: URL) -> URL? {
    ReaderImagePolicy.url(string, base: base)
  }
  private static func preText(_ element: Element) throws -> String {
    func raw(_ node: Node) -> String {
      if let text = node as? TextNode { return text.getWholeText() }
      if let el = node as? Element {
        if el.tagName() == "br" { return "\n" }
        let content = el.getChildNodes().map(raw).joined()
        return el.tagName() == "div" ? content + "\n" : content
      }
      return node.getChildNodes().map(raw).joined()
    }
    let lines = try element.select(".test-example-line").array()
    let text = lines.isEmpty ? raw(element) : lines.map { $0.getChildNodes().map(raw).joined() + "\n" }.joined()
    return text.hasSuffix("\n") ? text : text + "\n"
  }
  public static func editorialAssociation(_ html: String, id: ProblemID) throws -> EditorialAssociation {
    let doc = try SwiftSoup.parse(html)
    // Explicit tutorial links in contest materials only, never arbitrary recent-blog/search links.
    for box in try doc.select(".roundbox, .sidebox").array() {
      let caption = try box.select(".caption, h3").text().lowercased()
      guard caption.contains("contest materials") || caption.contains("материалы") else { continue }
      for a in try box.select("a[href]").array() {
        let name = try a.text().lowercased(), href = try a.attr("href")
        guard name.contains("tutorial") || name.contains("editorial") || name.contains("разбор") else { continue }
        if let u = safeCFURL(href, base: URL(string: "https://codeforces.com/contest/\(id.contest)")!), let blog = Int(u.lastPathComponent), u.path.hasPrefix("/blog/entry/") {
          return EditorialAssociation(blogID: blog, evidence: "官方比赛 \(id.contest) 的 Contest materials 区明确链接 Tutorial；\(u.absoluteString)")
        }
      }
    }
    throw PocketError.unavailable("未找到比赛材料区明确关联的官方题解。未把搜索结果或近期博客当成官方依据。")
  }
  public static func editorial(_ data: Data, id: ProblemID, association: EditorialAssociation) throws -> EditorialEvidence {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard root?["status"] as? String == "OK", let row = root?["result"] as? [String: Any], row["id"] as? Int == association.blogID, let content = row["content"] as? String, let author = row["authorHandle"] as? String else { throw PocketError.source("官方博客正文未成功读取。") }
    let source = URL(string: "https://codeforces.com/blog/entry/\(association.blogID)")!
    let doc = try SwiftSoup.parseBodyFragment(content, source.absoluteString)
    let links = try doc.select("a[href]").array().filter {
      guard let url = safeCFURL(try $0.attr("href"), base: source) else { return false }
      return url.path == "/contest/\(id.contest)/problem/\(id.index)" || url.path == "/problemset/problem/\(id.contest)/\(id.index)"
    }
    let headingTags = ["h1","h2","h3","h4","h5","h6","hr","del","h5","h6"]
    let heading = links.compactMap { link in link.parents().array().first(where: { headingTags.contains($0.tagName()) }) }.first
    var section = content
    var sectionLocated = false
    if let heading, let level = headingTags.firstIndex(of: heading.tagName()) {
      var parts = [try heading.outerHtml()]
      var node = heading.nextSibling()
      while let current = node {
        if let element = current as? Element, let nextLevel = headingTags.firstIndex(of: element.tagName()), nextLevel <= level { break }
        parts.append(try current.outerHtml()); node = current.nextSibling()
      }
      section = parts.joined(); sectionLocated = true
    }
    let selected = try SwiftSoup.parseBodyFragment(section, source.absoluteString)
    let text = try selected.text()
    let externalLinks = try selected.select("a[href]").array().contains { try safeCFURL($0.attr("href"), base: source) == nil }
    let unresolved = try selected.select(".problemTutorial, iframe, img, video, object").size() > 0 || externalLinks || text.lowercased().contains("coming soon")
    let otherProblemHeading = try selected.select("h1 a[href],h2 a[href],h3 a[href],h4 a[href],h5 a[href],h6 a[href]").array().contains {
      guard let url = safeCFURL(try $0.attr("href"), base: source) else { return false }
      let prefix = "/contest/\(id.contest)/problem/"
      return url.path.hasPrefix(prefix) && url.path != "/contest/\(id.contest)/problem/\(id.index)"
    }
    let complete = !links.isEmpty && sectionLocated && text.count > 200 && !unresolved && !otherProblemHeading && !author.isEmpty
    let sanitized = try sanitize(section, base: source)
    return EditorialEvidence(problem: id, source: source, author: author, fetchedAt: Date(), modifiedAt: (row["modificationTimeSeconds"] as? Double).map(Date.init(timeIntervalSince1970:)), association: association.evidence + (!links.isEmpty ? "；正文含本题精确官方链接" : "；正文缺少本题精确链接") + (sectionLocated ? "；从对应标题提取至下一同级或更高标题，保留折叠内容" : "；尚不能可靠定位分题边界"), content: sanitized, hash: fingerprint(sanitized), completeness: complete ? .complete : .partial, reason: complete ? "官方关联、题号与分题边界已匹配；本题正文及折叠部分完整获取。" : "正文已获取，但分题边界、精确题号或外部/动态内容尚不能完整核实；不会声明 AI 已读完整官方题解。", parserVersion: version)
  }
}
