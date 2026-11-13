import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
public protocol HTTPGetting: Sendable { func get(_ url: URL) async throws -> Data }
public actor PublicHTTPClient: HTTPGetting {
  private static let gate = PublicRequestGate()
  private let session: URLSession
  public init() {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 25
    c.timeoutIntervalForResource = 40
    c.httpAdditionalHeaders = [
      "Accept": "application/json,text/html;q=0.9",
      "User-Agent": "TrainingLedger/1.0 (public training records)",
    ]
    session = URLSession(configuration: c)
  }
  public func get(_ url: URL) async throws -> Data {
    try Task.checkCancellation()
    guard url.scheme == "https", let host = url.host else {
      throw TrainingError.invalid("数据源必须使用HTTPS。")
    }
    try await Self.gate.wait(host: host)
    var req = URLRequest(url: url)
    req.cachePolicy = .reloadIgnoringLocalCacheData
    if !host.contains("codeforces"), !host.contains("kenkoooo"), !url.path.hasSuffix("/status/data")
    {
      req.setValue("text/html", forHTTPHeaderField: "Accept")
    }
    let (data, response) = try await session.data(for: req)
    guard let r = response as? HTTPURLResponse else { throw TrainingError.network("没有收到有效的网络响应。") }
    if r.statusCode == 403 || r.statusCode == 401 || r.statusCode == 429 {
      throw TrainingError.needsBrowser("\(host)需要网页连接或暂时限制访问，请在App内连接后重试。")
    }
    guard r.statusCode == 200 else {
      throw TrainingError.network("来源暂时无法访问（HTTP \(r.statusCode)），已保留原记录。")
    }
    guard data.count <= 20_000_000 else { throw TrainingError.invalid("来源单页数据异常过大。") }
    if let text = String(data: data.prefix(10000), encoding: .utf8),
      text.contains("Cerberus Challenge") || text.contains("Just a moment...")
        || text.contains("cf-chl-")
    {
      throw TrainingError.needsBrowser("来源需要网页安全校验，请在App内连接。")
    }
    return data
  }
}
public struct SubmissionPage: Sendable {
  public var rows: [Submission]
  public var nextURL: URL?
  public var nextCursor: Int?
  public var finished: Bool
  public var source: String
  public init(
    rows: [Submission], nextURL: URL? = nil, nextCursor: Int? = nil, finished: Bool, source: String
  ) {
    self.rows = rows
    self.nextURL = nextURL
    self.nextCursor = nextCursor
    self.finished = finished
    self.source = source
  }
}
public enum JSONHelpers {
  public static func object(_ data: Data) throws -> [String: Any] {
    guard let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw TrainingError.invalid("接口未返回有效数据。")
    }
    return d
  }
  public static func int(_ value: Any?) -> Int? {
    if let n = value as? NSNumber { return n.intValue }
    if let s = value as? String { return Int(s) }
    return nil
  }
  public static func string(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
  }
  public static func clean(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
public enum APIParser {
  public static func codeforces(_ data: Data, account: OJAccount, from: Int, count: Int) throws
    -> SubmissionPage
  {
    let d = try JSONHelpers.object(data)
    guard d["status"] as? String == "OK", let raw = d["result"] as? [[String: Any]] else {
      throw TrainingError.invalid(d["comment"] as? String ?? "Codeforces返回失败，未清空原记录。")
    }
    var rows: [Submission] = []
    for s in raw {
      guard let id = JSONHelpers.string(s["id"]),
        let time = JSONHelpers.int(s["creationTimeSeconds"]),
        let p = s["problem"] as? [String: Any], let index = p["index"] as? String,
        let name = p["name"] as? String
      else { throw TrainingError.invalid("Codeforces提交字段不完整。") }
      if let members = (s["author"] as? [String: Any])?["members"] as? [[String: Any]],
        !members.contains(where: {
          ($0["handle"] as? String)?.lowercased() == account.handle.lowercased()
        })
      {
        throw TrainingError.invalid("Codeforces返回了其他账号的数据。")
      }
      let contest = JSONHelpers.int(p["contestId"])
      let pid =
        "\(contest.map(String.init) ?? (p["problemsetName"] as? String ?? "unknown"))\(index)"
      let url =
        contest.map {
          "https://codeforces.com/\($0>=100000 ? "gym":"contest")/\($0)/problem/\(index)"
        } ?? "https://codeforces.com/problemset"
      let rating = JSONHelpers.int(p["rating"])
      let verdict = s["verdict"] as? String ?? "TESTING"
      let row = Submission(
        accountID: account.id, recordID: id, timestamp: Date(timeIntervalSince1970: Double(time)),
        problemID: pid, title: name, problemURL: url, verdict: verdict, accepted: verdict == "OK",
        language: s["programmingLanguage"] as? String,
        difficulty: rating.map {
          Difficulty(value: $0, label: String($0), source: "Codeforces rating")
        }, recordURL: contest.map { "https://codeforces.com/contest/\($0)/submission/\(id)" })
      try row.validate()
      rows.append(row)
    }
    guard Set(rows.map(\.id)).count == rows.count else {
      throw TrainingError.invalid("Codeforces单页包含重复记录。")
    }
    let finished = rows.count < count
    let next = URL(
      string:
        "https://codeforces.com/api/user.status?handle=\(account.handle.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? "")&from=\(from+count)&count=\(count)"
    )
    return SubmissionPage(
      rows: rows, nextURL: finished ? nil : next, finished: finished, source: "Codeforces公开API")
  }
  public static func atcoder(_ data: Data, account: OJAccount, cursor: Int) throws -> SubmissionPage
  {
    guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw TrainingError.invalid("AtCoder Problems返回的提交列表无效。")
    }
    var rows: [Submission] = []
    for s in raw {
      guard let id = JSONHelpers.string(s["id"]), let sec = JSONHelpers.int(s["epoch_second"]),
        let pid = s["problem_id"] as? String, let contest = s["contest_id"] as? String,
        let result = s["result"] as? String, let user = s["user_id"] as? String,
        user.lowercased() == account.handle.lowercased(), sec >= cursor
      else { throw TrainingError.invalid("AtCoder记录字段或账号不匹配。") }
      let r = Submission(
        accountID: account.id, recordID: id, timestamp: Date(timeIntervalSince1970: Double(sec)),
        problemID: pid, title: pid,
        problemURL: "https://atcoder.jp/contests/\(contest)/tasks/\(pid)", verdict: result,
        accepted: result == "AC", language: s["language"] as? String,
        recordURL: "https://atcoder.jp/contests/\(contest)/submissions/\(id)")
      try r.validate()
      rows.append(r)
    }
    let finished = rows.count < 500
    let next = (raw.compactMap { JSONHelpers.int($0["epoch_second"]) }.max() ?? cursor)
    // Overlap the final second and deduplicate by submission ID; never skip a boundary second.
    if !finished, next <= cursor { throw TrainingError.invalid("AtCoder同一秒记录达到接口上限，无法确认完整性。") }
    return SubmissionPage(
      rows: rows, nextCursor: finished ? nil : next, finished: finished,
      source: "AtCoder Problems第三方收录，可能有延迟")
  }
  public static func luogu(_ data: Data, account: OJAccount, page: Int) throws -> SubmissionPage {
    let root = try JSONHelpers.object(data)
    let body = root["data"] as? [String: Any] ?? root
    guard let list = body["records"] as? [String: Any],
      let raw = list["result"] as? [[String: Any]], let count = JSONHelpers.int(list["count"]),
      let size = JSONHelpers.int(list["perPage"]), size > 0, count >= 0
    else { throw TrainingError.invalid("洛谷记录列表未识别，请重新连接。") }
    let levels = ["暂无评定", "入门", "普及−", "普及/提高−", "普及+/提高", "提高+/省选−", "省选/NOI−", "NOI/NOI+/CTSC"]
    var rows: [Submission] = []
    for s in raw {
      guard let id = JSONHelpers.string(s["id"]), let sec = JSONHelpers.int(s["submitTime"]),
        let status = JSONHelpers.int(s["status"]), let p = s["problem"] as? [String: Any],
        let pid = p["pid"] as? String, let name = p["name"] as? String,
        let u = s["user"] as? [String: Any], JSONHelpers.string(u["uid"]) == account.handle
      else { throw TrainingError.invalid("洛谷记录字段或用户不匹配。") }
      let level = JSONHelpers.int(p["difficulty"]) ?? 0
      let statuses = [
        12: "Accepted", 11: "Wrong Answer", 7: "Compile Error", 6: "Output Limit Exceeded",
        5: "Time Limit Exceeded", 4: "Memory Limit Exceeded", 2: "Runtime Error", 0: "Waiting",
        1: "Judging",
      ]
      let r = Submission(
        accountID: account.id, recordID: id, timestamp: Date(timeIntervalSince1970: Double(sec)),
        problemID: pid, title: name, problemURL: "https://www.luogu.com.cn/problem/\(pid)",
        verdict: statuses[status] ?? "状态\(status)", accepted: status == 12,
        language: JSONHelpers.string(s["language"]).map { "洛谷语言编号 \($0)" },
        difficulty: level > 0 && level < levels.count
          ? Difficulty(value: level, label: levels[level], source: "洛谷官方难度分级") : nil,
        recordURL: "https://www.luogu.com.cn/record/\(id)")
      try r.validate()
      rows.append(r)
    }
    guard rows.count <= size, !rows.isEmpty || count == 0 else {
      throw TrainingError.invalid("洛谷分页为空但总数非零，原数据保留。")
    }
    let done = page * size >= count
    var c = URLComponents(url: account.recordsURL, resolvingAgainstBaseURL: false)!
    c.queryItems = (c.queryItems ?? []) + [.init(name: "page", value: String(page + 1))]
    return SubmissionPage(
      rows: rows, nextURL: done ? nil : c.url, finished: done, source: "洛谷公开评测记录")
  }
}

/// All feature clients in one app share CF's public API limit, including concurrent syncs.
private actor PublicRequestGate {
  private var slots: [String: Date] = [:]
  func wait(host: String) async throws {
    let now = Date(), key = host.lowercased()
    let slot = max(now, slots[key] ?? now)
    slots[key] = slot.addingTimeInterval(key.contains("codeforces") ? 2.2 : 1.2)
    if slot > now { try await Task.sleep(for: .seconds(slot.timeIntervalSince(now))) }
    try Task.checkCancellation()
  }
}
