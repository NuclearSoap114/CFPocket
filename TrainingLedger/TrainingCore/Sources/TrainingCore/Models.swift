import Foundation

public enum OJ: String, Codable, CaseIterable, Identifiable, Sendable {
  case codeforces, atcoder, luogu, nowcoder, qoj, hydro, vjudge
  public var id: String { rawValue }
  public var name: String {
    switch self {
    case .codeforces: "Codeforces"
    case .atcoder: "AtCoder"
    case .luogu: "洛谷"
    case .nowcoder: "牛客"
    case .qoj: "QOJ"
    case .hydro: "Hydro"
    case .vjudge: "VJudge"
    }
  }
  public var shortName: String { self == .codeforces ? "CF" : name }
  public var host: String {
    switch self {
    case .codeforces: "codeforces.com"
    case .atcoder: "atcoder.jp"
    case .luogu: "www.luogu.com.cn"
    case .nowcoder: "ac.nowcoder.com"
    case .qoj: "qoj.ac"
    case .hydro: "hydro.ac"
    case .vjudge: "vjudge.net"
    }
  }
  public var hint: String {
    switch self {
    case .luogu, .nowcoder: "数字 UID"
    case .hydro: "用户名或数字 UID"
    default: "用户名 / handle"
    }
  }
}
public struct OJAccount: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var oj: OJ
  public var handle: String
  public var site: String
  public var platformName: String = ""
  public var extraFields: [String: JSONValue] = [:]
  public init(
    id: UUID = UUID(), oj: OJ, handle: String, site: String = "", platformName: String = ""
  ) {
    self.id = id
    self.oj = oj
    self.handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
    self.site = site.trimmingCharacters(in: .whitespacesAndNewlines)
    self.platformName = platformName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  public var problemNamespace: String {
    "\(oj.rawValue)|\(baseURL.host?.lowercased() ?? oj.host)|\(baseURL.path.trimmingCharacters(in:CharacterSet(charactersIn:"/")))"
  }
  public var identity: String {
    "\(oj.rawValue)|\(baseURL.absoluteString.lowercased())|\(handle.lowercased())"
  }
  public var baseURL: URL {
    URL(string: site.isEmpty ? "https://\(oj.host)" : site) ?? URL(string: "https://\(oj.host)")!
  }
  public func validate() throws {
    guard !handle.isEmpty, handle.count <= 80,
      handle.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
      !handle.contains("/"), !handle.contains("?"), !handle.contains("#"), !handle.contains("&"),
      !handle.contains("=")
    else { throw TrainingError.invalid("请填写有效的\(oj.hint)，不要填写完整链接。") }
    if oj == .luogu || oj == .nowcoder {
      guard handle.allSatisfy(\.isNumber) else {
        throw TrainingError.invalid("\(oj.name)请填写数字 UID。")
      }
    }
    if !site.isEmpty {
      guard oj == .hydro, let u = URL(string: site), u.scheme == "https", let host = u.host,
        !host.isEmpty, u.user == nil, u.password == nil, u.query == nil, u.fragment == nil
      else { throw TrainingError.invalid("Hydro 站点请填写 HTTPS 地址，可包含 /d/域名，不能包含账号密码或查询参数。") }
    }
  }
  public var recordsURL: URL {
    let path: String
    let query: [URLQueryItem]
    switch oj {
    case .codeforces:
      path = "/submissions/\(handle)"
      query = []
    case .atcoder:
      path = "/users/\(handle)"
      query = []
    case .luogu:
      path = "/record/list"
      query = [.init(name: "user", value: handle)]
    case .nowcoder:
      path = "/acm/contest/profile/\(handle)/practice-coding"
      query = []
    case .qoj:
      path = "/submissions"
      query = [.init(name: "submitter", value: handle)]
    case .hydro:
      path = "/record"
      query = [.init(name: "uidOrName", value: handle)]
    case .vjudge:
      path = "/status"
      query = []
    }
    var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    c.path =
      c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
      ? path : "/" + c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
    c.queryItems = query.isEmpty ? nil : query
    if oj == .vjudge {
      c.fragment = "un=\(handle)&OJId=All&probNum=&res=all&orderBy=run_id&language="
    }
    return c.url!
  }
}
public struct Person: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var realName: String = ""
  public var extraFields: [String: JSONValue] = [:]
  public var favorite: Bool
  public var accounts: [OJAccount]
  public var createdAt: Date
  public init(
    id: UUID = UUID(), name: String, favorite: Bool = false, accounts: [OJAccount] = [],
    createdAt: Date = Date(), realName: String = ""
  ) {
    self.id = id
    self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    self.realName = realName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.favorite = favorite
    self.accounts = accounts
    self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
  }
  public var displayName: String { realName.isEmpty ? name : realName }
  public var alias: String? { !realName.isEmpty && !name.isEmpty && name != realName ? name : nil }
  public func matches(_ query: String) -> Bool {
    query.isEmpty
      || ([name, realName] + accounts.flatMap { [$0.handle, $0.platformName] }).contains {
        $0.localizedCaseInsensitiveContains(query)
      }
  }
  public func validate() throws {
    guard !name.isEmpty || !realName.isEmpty, name.count <= 100, realName.count <= 100 else {
      throw TrainingError.invalid("请填写真名或显示昵称（各最多100字）。")
    }
    guard Set(accounts.map(\.id)).count == accounts.count,
      Set(accounts.map(\.identity)).count == accounts.count
    else { throw TrainingError.invalid("同一个人不能重复绑定相同 OJ 账号。") }
    for a in accounts { try a.validate() }
  }
}
public struct Difficulty: Codable, Equatable, Sendable {
  public var value: Int?
  public var label: String
  public var source: String
  public var extraFields: [String: JSONValue] = [:]
  public init(value: Int? = nil, label: String, source: String) {
    self.value = value
    self.label = label
    self.source = source
  }
}
public struct Submission: Codable, Identifiable, Equatable, Sendable {
  public var accountID: UUID
  public var recordID: String
  public var timestamp: Date
  public var problemID: String
  public var title: String
  public var problemURL: String
  public var verdict: String
  public var accepted: Bool
  public var language: String?
  public var difficulty: Difficulty?
  public var recordURL: String?
  public var extraFields: [String: JSONValue] = [:]
  public var id: String { "\(accountID.uuidString):\(recordID)" }
  public init(
    accountID: UUID, recordID: String, timestamp: Date, problemID: String, title: String,
    problemURL: String, verdict: String, accepted: Bool, language: String? = nil,
    difficulty: Difficulty? = nil, recordURL: String? = nil
  ) {
    self.accountID = accountID
    self.recordID = recordID
    self.timestamp = timestamp
    self.problemID = problemID
    self.title = title
    self.problemURL = problemURL
    self.verdict = verdict
    self.accepted = accepted
    self.language = language
    self.difficulty = difficulty
    self.recordURL = recordURL
  }
  public func validate(now: Date = Date()) throws {
    guard !recordID.isEmpty, recordID.count < 200, !problemID.isEmpty, !title.isEmpty,
      title.count < 2000, timestamp.timeIntervalSince1970 > 0,
      timestamp < now.addingTimeInterval(600)
    else { throw TrainingError.invalid("提交记录的题目、ID或时间不完整。") }
    for s in [problemURL, recordURL].compactMap({ $0 }) {
      guard let u = URL(string: s), u.scheme == "https", u.host != nil, u.user == nil,
        u.password == nil
      else { throw TrainingError.invalid("提交记录包含无效题目链接。") }
    }
  }
}
public struct SyncInfo: Codable, Equatable, Sendable {
  public var accountID: UUID
  public var lastSuccess: Date?
  public var lastAttempt: Date?
  public var error: String?
  public var coverage: String
  public var complete: Bool
  public var nextPage: Int
  public var cursor: Int
  public var extraFields: [String: JSONValue] = [:]
  public init(
    accountID: UUID, lastSuccess: Date? = nil, lastAttempt: Date? = nil, error: String? = nil,
    coverage: String = "尚未采集", complete: Bool = false, nextPage: Int = 1, cursor: Int = 0
  ) {
    self.accountID = accountID
    self.lastSuccess = lastSuccess
    self.lastAttempt = lastAttempt
    self.error = error
    self.coverage = coverage
    self.complete = complete
    self.nextPage = nextPage
    self.cursor = cursor
  }
}
public struct TrainingArchive: Codable, Equatable, Sendable {
  public var version = 2
  public var schemaMinor = 0
  public var archiveID = UUID()
  public var revision = 0
  public var extraFields: [String: JSONValue] = [:]
  public var people: [Person]
  public var submissions: [Submission]
  public var sync: [SyncInfo]
  public init(people: [Person] = [], submissions: [Submission] = [], sync: [SyncInfo] = []) {
    self.people = people
    self.submissions = submissions
    self.sync = sync
  }
  public func validate() throws {
    guard version == 2, schemaMinor >= 0, revision >= 0 else {
      throw TrainingError.invalid("不支持的数据格式版本或修订号。请更新App后导入。")
    }
    guard people.count <= 1000, submissions.count <= 500_000,
      Set(people.map(\.id)).count == people.count
    else { throw TrainingError.invalid("人物数量或数据标识异常。") }
    for p in people { try p.validate() }
    let accounts = people.flatMap(\.accounts)
    let ids = Set(accounts.map(\.id))
    guard ids.count == accounts.count, Set(submissions.map(\.id)).count == submissions.count,
      Set(sync.map(\.accountID)).count == sync.count
    else { throw TrainingError.invalid("存在重复账号或重复记录。") }
    let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    for r in submissions {
      guard ids.contains(r.accountID) else { throw TrainingError.invalid("记录引用了不存在的账号。") }
      try r.validate()
      if let account = accountMap[r.accountID] {
        let expected = account.baseURL.host?.lowercased()
        for value in [r.problemURL, r.recordURL].compactMap({ $0 }) {
          guard URL(string: value)?.host?.lowercased() == expected else {
            throw TrainingError.invalid("记录链接与绑定的OJ来源不一致。")
          }
        }
      }
    }
    for s in sync {
      guard ids.contains(s.accountID), s.nextPage > 0, s.cursor >= 0 else {
        throw TrainingError.invalid("采集进度异常。")
      }
    }
  }
}
public enum TrainingError: LocalizedError, Equatable {
  case invalid(String)
  case network(String)
  case needsBrowser(String)
  case cancelled
  public var errorDescription: String? {
    switch self {
    case .invalid(let s), .network(let s), .needsBrowser(let s): s
    case .cancelled: "已停止同步，已保存的记录继续可用。"
    }
  }
}
public enum TrainingDates {
  public static let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    c.firstWeekday = 2
    return c
  }()
  public static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
  public static func text(_ d: Date, format: String = "yyyy-MM-dd HH:mm") -> String {
    TrainingFormatters.shared.text(d, format: format)
  }
  public static func parse(_ s: String) -> Date? {
    if let t = Double(s), t > 1_000_000_000 {
      return Date(timeIntervalSince1970: t > 10_000_000_000 ? t / 1000 : t)
    }
    return TrainingFormatters.shared.parse(s)
  }
}
private final class TrainingFormatters: @unchecked Sendable {
  static let shared = TrainingFormatters()
  private let lock = NSLock()
  private var formats: [String: DateFormatter] = [:]
  private let iso = ISO8601DateFormatter()
  private let fractional = ISO8601DateFormatter()
  private init() { fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds] }
  private func formatter(_ format: String) -> DateFormatter {
    if let f = formats[format] { return f }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TrainingDates.calendar.timeZone
    f.dateFormat = format
    f.isLenient = false
    if formats.count < 32 { formats[format] = f }
    return f
  }
  func text(_ date: Date, format: String) -> String {
    lock.lock()
    defer { lock.unlock() }
    return formatter(format).string(from: date)
  }
  func parse(_ text: String) -> Date? {
    lock.lock()
    defer { lock.unlock() }
    if text.contains("T") {
      if let d = fractional.date(from: text) ?? iso.date(from: text) { return d }
    }
    for format in ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
      if let d = formatter(format).date(from: text) { return d }
    }
    return nil
  }
}
