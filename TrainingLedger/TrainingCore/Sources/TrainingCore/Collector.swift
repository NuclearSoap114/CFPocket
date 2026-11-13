import Foundation

public actor SubmissionCollector {
  private let http: any HTTPGetting
  private var atTitles: [String: String] = [:]
  private var atModels: [String: Int] = [:]
  private var cfProblems: [String: (String, Int?)] = [:]
  public init(http: any HTTPGetting = PublicHTTPClient()) { self.http = http }
  public static func startURL(_ account: OJAccount, page: Int = 1, cursor: Int = 0) -> URL {
    switch account.oj {
    case .codeforces:
      var c = URLComponents(string: "https://codeforces.com/api/user.status")!
      c.queryItems = [
        .init(name: "handle", value: account.handle),
        .init(name: "from", value: String((page - 1) * 1000 + 1)),
        .init(name: "count", value: "1000"),
      ]
      return c.url!
    case .atcoder:
      var c = URLComponents(string: "https://kenkoooo.com/atcoder/atcoder-api/v3/user/submissions")!
      c.queryItems = [
        .init(name: "user", value: account.handle),
        .init(name: "from_second", value: String(cursor)),
      ]
      return c.url!
    case .vjudge:
      var c = URLComponents(string: "https://vjudge.net/status/data")!
      c.queryItems = [
        .init(name: "draw", value: "1"), .init(name: "start", value: String((page - 1) * 100)),
        .init(name: "length", value: "100"), .init(name: "un", value: account.handle),
        .init(name: "OJId", value: "All"), .init(name: "probNum", value: ""),
        .init(name: "res", value: "all"), .init(name: "orderBy", value: "run_id"),
        .init(name: "language", value: ""),
      ]
      return c.url!
    case .nowcoder:
      var c = URLComponents(url: account.recordsURL, resolvingAgainstBaseURL: false)!
      c.queryItems = [
        .init(name: "page", value: String(page)), .init(name: "pageSize", value: "100"),
      ]
      return c.url!
    default:
      var c = URLComponents(url: account.recordsURL, resolvingAgainstBaseURL: false)!
      c.queryItems =
        (c.queryItems ?? []).filter { $0.name != "page" } + [
          .init(name: "page", value: String(page))
        ]
      return c.url!
    }
  }
  public func page(account: OJAccount, url: URL, cursor: Int = 0) async throws -> SubmissionPage {
    try account.validate()
    let data = try await http.get(url)
    return try await parse(data, account: account, url: url, cursor: cursor)
  }
  public func parse(_ data: Data, account: OJAccount, url: URL, cursor: Int = 0) async throws
    -> SubmissionPage
  {
    let body = String(data: data, encoding: .utf8) ?? ""
    let trim = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let page =
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "page"
      })?.value.flatMap(Int.init) ?? 1
    switch account.oj {
    case .codeforces:
      let from =
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
          $0.name == "from"
        })?.value.flatMap(Int.init) ?? 1
      return try APIParser.codeforces(data, account: account, from: from, count: 1000)
    case .atcoder:
      var result = try APIParser.atcoder(data, account: account, cursor: cursor)
      if atTitles.isEmpty { await loadAtMetadata() }
      result.rows = result.rows.map { r in
        var r = r
        if let name = atTitles[r.problemID] { r.title = name }
        if let d = atModels[r.problemID] {
          r.difficulty = Difficulty(
            value: d, label: String(d), source: "AtCoder Problems模型估计原值，非官方评分")
        }
        return r
      }
      return result
    case .luogu:
      if trim.hasPrefix("{") { return try APIParser.luogu(data, account: account, page: page) }
      return try TrainingHTML.parse(body, account: account, url: url)
    case .vjudge:
      if trim.hasPrefix("{") { return try APIParser.vjudge(data, account: account, url: url) }
      return try TrainingHTML.parse(body, account: account, url: url)
    default: return try TrainingHTML.parse(body, account: account, url: url)
    }
  }
  private func loadAtMetadata() async {
    do {
      let titles = try await http.get(
        URL(string: "https://kenkoooo.com/atcoder/resources/problems.json")!)
      if let data = try JSONSerialization.jsonObject(with: titles) as? [[String: Any]] {
        for p in data {
          if let id = p["id"] as? String, let name = p["name"] as? String { atTitles[id] = name }
        }
      }
      let models = try await http.get(
        URL(string: "https://kenkoooo.com/atcoder/resources/problem-models.json")!)
      if let data = try JSONSerialization.jsonObject(with: models) as? [String: [String: Any]] {
        for (id, p) in data { if let d = JSONHelpers.int(p["difficulty"]) { atModels[id] = d } }
      }
    } catch { /* Missing metadata never turns a successful submission fetch into zero records. */  }
  }
  public func metadata(for row: Submission, oj: OJ) async throws -> (String?, Difficulty?) {
    if oj == .vjudge, row.problemID.hasPrefix("CodeForces-") {
      if cfProblems.isEmpty {
        let data = try await http.get(
          URL(string: "https://codeforces.com/api/problemset.problems")!)
        let object = try JSONHelpers.object(data)
        guard object["status"] as? String == "OK", let result = object["result"] as? [String: Any],
          let problems = result["problems"] as? [[String: Any]]
        else { throw TrainingError.invalid("CF题库元数据暂时不可用。") }
        for p in problems {
          if let contest = JSONHelpers.int(p["contestId"]), let index = p["index"] as? String,
            let name = p["name"] as? String
          {
            cfProblems["\(contest)\(index)"] = (name, JSONHelpers.int(p["rating"]))
          }
        }
      }
      if let (name, rating) = cfProblems[String(row.problemID.dropFirst("CodeForces-".count))] {
        return (
          name,
          rating.map { Difficulty(value: $0, label: String($0), source: "原题 Codeforces 官方rating") }
        )
      }
    }
    if oj == .vjudge, row.problemID.hasPrefix("AtCoder-") {
      if atTitles.isEmpty { await loadAtMetadata() }
      let key = String(row.problemID.dropFirst("AtCoder-".count))
      if let name = atTitles[key] {
        return (
          name,
          atModels[key].map {
            Difficulty(value: $0, label: String($0), source: "原题 AtCoder Problems 模型估计原值")
          }
        )
      }
    }
    let data = try await http.get(URL(string: row.problemURL)!)
    guard let html = String(data: data, encoding: .utf8) else {
      throw TrainingError.invalid("题目元数据无法读取。")
    }
    return try TrainingHTML.problemMetadata(html, oj: oj)
  }
}
