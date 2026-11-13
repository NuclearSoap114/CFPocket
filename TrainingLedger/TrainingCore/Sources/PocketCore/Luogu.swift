import Foundation
import SwiftSoup

public struct LuoguProblem: Codable, Sendable, Equatable {
  public let pid: String
  public let name: String
  public let difficulty: Int
  public let fetchedAt: Date
  public var difficultyLabel: String { LuoguParser.difficulties.indices.contains(difficulty) ? LuoguParser.difficulties[difficulty] : "暂无评定" }
  public var url: URL { URL(string: "https://www.luogu.com.cn/problem/\(pid)")! }
}
public struct LuoguArticle: Codable, Sendable, Identifiable, Equatable {
  public let id: String
  public let title: String
  public let author: String
  public let authorID: Int
  public let publishedAt: Date
  public let markdown: String
  public let adminNote: String?
  public let votes: Int?
  public var url: URL { URL(string: "https://www.luogu.com.cn/article/\(id)")! }
  public var minutes: Int { max(1, Int(ceil(Double(markdown.count) / 450))) }
}
public struct LuoguPage: Codable, Sendable {
  public let pid: String
  public let page: Int
  public let pageSize: Int
  public let total: Int
  public let articles: [LuoguArticle]
  public let fetchedAt: Date
  public var hasMore: Bool { page * pageSize < total }
}
public enum LuoguParser {
  public static let difficulties = ["暂无评定", "入门", "普及−", "普及", "普及+/提高−", "提高", "提高+/省选−", "省选/NOI−", "NOI/NOI+/CTS"]
  public static func pid(_ problem: ProblemID) throws -> String {
    guard problem.contest < 100000, problem.index.first?.isLetter == true else {
      throw PocketError.unavailable("这类题号暂没有可靠的洛谷对应关系。")
    }
    return "CF\(problem.description)"
  }
  public static func context(_ html: String) throws -> Data {
    guard html.utf8.count <= 8_000_000, let element = try SwiftSoup.parse(html).select("script#lentille-context[type=application/json]").first() else {
      throw PocketError.source("洛谷页面尚未准备好，可能需要完成网站验证。原缓存保留。")
    }
    return Data(element.data().utf8)
  }
  private static func payload(_ bytes: Data, template: String) throws -> [String: Any] {
    guard bytes.count <= 8_000_000, let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw PocketError.source("洛谷返回了无法识别的数据。") }
    if root["status"] as? Int == 401 { throw PocketError.blocked("请先登录洛谷，再返回这里读取题解。") }
    if root["status"] as? Int == 404 { throw PocketError.unavailable("洛谷暂未收录这道题。") }
    guard root["status"] as? Int == 200, root["template"] as? String == template, let data = root["data"] as? [String: Any] else { throw PocketError.source("洛谷暂时未返回完整内容，请稍后重试；原缓存保留。") }
    return data
  }
  public static func problem(_ bytes: Data, pid: String, now: Date = Date()) throws -> LuoguProblem {
    let data = try payload(bytes, template: "problem.show")
    guard let p = data["problem"] as? [String: Any], p["pid"] as? String == pid, let name = p["name"] as? String, !name.isEmpty,
      let difficulty = p["difficulty"] as? Int, difficulties.indices.contains(difficulty) else { throw PocketError.source("洛谷题号或难度核对失败。") }
    return LuoguProblem(pid: pid, name: name, difficulty: difficulty, fetchedAt: now)
  }
  public static func solutions(_ bytes: Data, pid: String, page: Int, now: Date = Date()) throws -> LuoguPage {
    let data = try payload(bytes, template: "problem.solution")
    guard page > 0, page <= 1000, let problem = data["problem"] as? [String: Any], problem["pid"] as? String == pid,
      let list = data["solutions"] as? [String: Any], let total = list["count"] as? Int, total >= 0, total <= 100_000,
      let perPage = list["perPage"] as? Int, (1...100).contains(perPage), let rows = list["result"] as? [[String: Any]], rows.count <= perPage,
      rows.count == min(perPage, max(0, total - (page - 1) * perPage)) else { throw PocketError.source("洛谷题解列表不完整，未替换已有缓存。") }
    var seen = Set<String>()
    let articles = try rows.map { row -> LuoguArticle in
      guard row["contentFull"] as? Bool != false, (row["solutionFor"] as? [String: Any])?["pid"] as? String == nil || (row["solutionFor"] as? [String: Any])?["pid"] as? String == pid,
        let id = row["lid"] as? String, id.range(of: "^[a-zA-Z0-9]{6,32}$", options: .regularExpression) != nil, seen.insert(id).inserted,
        let author = row["author"] as? [String: Any], let name = author["name"] as? String, !name.isEmpty, let uid = author["uid"] as? Int, uid > 0,
        let time = row["time"] as? Double, time > 0, time < now.timeIntervalSince1970 + 86400,
        let content = row["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.utf8.count <= 262_144 else { throw PocketError.source("题解缺少作者、正文或有效标识，原缓存保留。") }
      let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      return LuoguArticle(id: id, title: title?.isEmpty == false ? title! : "\(pid) · \(name)的题解", author: name, authorID: uid, publishedAt: Date(timeIntervalSince1970: time), markdown: content, adminNote: row["adminNote"] as? String, votes: row["upvote"] as? Int)
    }
    return LuoguPage(pid: pid, page: page, pageSize: perPage, total: total, articles: articles, fetchedAt: now)
  }
  public static func safeLink(_ raw: String, base: URL) -> URL? {
    guard let url = URL(string: raw, relativeTo: base)?.absoluteURL, url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
      ["www.luogu.com.cn", "codeforces.com"].contains(url.host ?? "") else { return nil }; return url
  }
  public static func safeImage(_ raw: String, base: URL) -> URL? {
    ReaderImagePolicy.url(raw, base: base)
  }
}
