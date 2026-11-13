import Foundation

/// Unknown optional JSON fields round-trip unchanged; integral IDs never pass through Double.
public enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case integer(Int64)
  case number(Decimal)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(Int64.self) {
      self = .integer(v)
    } else if let v = try? c.decode(Decimal.self) {
      self = .number(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .integer(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}
struct JSONKey: CodingKey, ExpressibleByStringLiteral {
  var stringValue: String
  var intValue: Int? { nil }
  init(_ s: String) { stringValue = s }
  init(stringLiteral value: String) { stringValue = value }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
extension KeyedDecodingContainer where Key == JSONKey {
  func extras(excluding known: Set<String>) throws -> [String: JSONValue] {
    try Dictionary(
      uniqueKeysWithValues: allKeys.filter { !known.contains($0.stringValue) }.map {
        ($0.stringValue, try decode(JSONValue.self, forKey: $0))
      })
  }
}
extension KeyedEncodingContainer where Key == JSONKey {
  mutating func extras(_ extra: [String: JSONValue], excluding known: Set<String>) throws {
    for (k, v) in extra where !known.contains(k) { try encode(v, forKey: JSONKey(k)) }
  }
}
extension TrainingArchive {
  public static let formatIdentifier = "com.codex.training-ledger"
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: JSONKey.self)
    let incoming =
      try c.decodeIfPresent(Int.self, forKey: "schemaVersion")
      ?? c.decode(Int.self, forKey: "version")
    guard incoming == 1 || incoming == 2 else {
      throw TrainingError.invalid("此文件的数据版本较新或不受支持（\(incoming)），请更新App；原数据不会被覆盖。")
    }
    if incoming == 2 {
      guard try c.decode(String.self, forKey: "format") == Self.formatIdentifier else {
        throw TrainingError.invalid("这不是题迹的JSON数据文件。")
      }
    }
    self.init(
      people: try c.decode([Person].self, forKey: "people"),
      submissions: try c.decode([Submission].self, forKey: "submissions"),
      sync: try c.decode([SyncInfo].self, forKey: "sync"))
    version = 2
    schemaMinor = try c.decodeIfPresent(Int.self, forKey: "schemaMinor") ?? 0
    archiveID = try c.decodeIfPresent(UUID.self, forKey: "archiveID") ?? UUID()
    revision = try c.decodeIfPresent(Int.self, forKey: "revision") ?? 0
    extraFields = try c.extras(excluding: [
      "format", "schemaVersion", "schemaMinor", "archiveID", "revision", "version", "people",
      "submissions", "sync",
    ])
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: JSONKey.self)
    try c.extras(
      extraFields,
      excluding: [
        "format", "schemaVersion", "schemaMinor", "archiveID", "revision", "version", "people",
        "submissions", "sync",
      ])
    try c.encode(Self.formatIdentifier, forKey: "format")
    try c.encode(version, forKey: "schemaVersion")
    try c.encode(schemaMinor, forKey: "schemaMinor")
    try c.encode(archiveID, forKey: "archiveID")
    try c.encode(revision, forKey: "revision")
    try c.encode(people, forKey: "people")
    try c.encode(submissions, forKey: "submissions")
    try c.encode(sync, forKey: "sync")
  }
}

extension OJAccount {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: JSONKey.self)
    self.init(
      id: try c.decode(UUID.self, forKey: "id"),
      oj: try c.decode(OJ.self, forKey: "oj"),
      handle: try c.decodeIfPresent(String.self, forKey: "platformID")
        ?? c.decode(String.self, forKey: "handle"),
      site: try c.decodeIfPresent(String.self, forKey: "site") ?? "",
      platformName: try c.decodeIfPresent(String.self, forKey: "platformName") ?? "")
    extraFields = try c.extras(excluding: [
      "id", "oj", "platformID", "site", "platformName", "handle",
    ])
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: JSONKey.self)
    try c.extras(
      extraFields, excluding: ["id", "oj", "platformID", "site", "platformName", "handle"])
    try c.encode(id, forKey: "id")
    try c.encode(oj, forKey: "oj")
    try c.encode(handle, forKey: "platformID")
    try c.encode(site, forKey: "site")
    try c.encode(platformName, forKey: "platformName")
  }
}

extension Person {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: JSONKey.self)
    self.init(
      id: try c.decode(UUID.self, forKey: "id"),
      name: try c.decodeIfPresent(String.self, forKey: "nickname") ?? c.decodeIfPresent(
        String.self, forKey: "name") ?? "",
      favorite: try c.decodeIfPresent(Bool.self, forKey: "favorite") ?? false,
      accounts: try c.decode([OJAccount].self, forKey: "accounts"),
      createdAt: try c.decode(Date.self, forKey: "createdAt"),
      realName: try c.decodeIfPresent(String.self, forKey: "realName") ?? "")
    extraFields = try c.extras(excluding: [
      "id", "nickname", "favorite", "accounts", "createdAt", "realName", "name",
    ])
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: JSONKey.self)
    try c.extras(
      extraFields,
      excluding: ["id", "nickname", "favorite", "accounts", "createdAt", "realName", "name"])
    try c.encode(id, forKey: "id")
    try c.encode(name, forKey: "nickname")
    try c.encode(favorite, forKey: "favorite")
    try c.encode(accounts, forKey: "accounts")
    try c.encode(createdAt, forKey: "createdAt")
    try c.encode(realName, forKey: "realName")
  }
}

extension Difficulty {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: JSONKey.self)
    self.init(
      value: try c.decodeIfPresent(Int.self, forKey: "value"),
      label: try c.decode(String.self, forKey: "label"),
      source: try c.decode(String.self, forKey: "source"))
    extraFields = try c.extras(excluding: ["value", "label", "source"])
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: JSONKey.self)
    try c.extras(extraFields, excluding: ["value", "label", "source"])
    try c.encodeIfPresent(value, forKey: "value")
    try c.encode(label, forKey: "label")
    try c.encode(source, forKey: "source")
  }
}

extension Submission {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: JSONKey.self)
    self.init(
      accountID: try c.decode(UUID.self, forKey: "accountID"),
      recordID: try c.decode(String.self, forKey: "recordID"),
      timestamp: try c.decode(Date.self, forKey: "timestamp"),
      problemID: try c.decode(String.self, forKey: "problemID"),
      title: try c.decode(String.self, forKey: "title"),
      problemURL: try c.decode(String.self, forKey: "problemURL"),
      verdict: try c.decode(String.self, forKey: "verdict"),
      accepted: try c.decode(Bool.self, forKey: "accepted"),
      language: try c.decodeIfPresent(String.self, forKey: "language"),
      difficulty: try c.decodeIfPresent(Difficulty.self, forKey: "difficulty"),
      recordURL: try c.decodeIfPresent(String.self, forKey: "recordURL"))
    extraFields = try c.extras(excluding: [
      "accountID", "recordID", "timestamp", "problemID", "title", "problemURL", "verdict",
      "accepted", "language", "difficulty", "recordURL",
    ])
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: JSONKey.self)
    try c.extras(
      extraFields,
      excluding: [
        "accountID", "recordID", "timestamp", "problemID", "title", "problemURL", "verdict",
        "accepted", "language", "difficulty", "recordURL",
      ])
    try c.encode(accountID, forKey: "accountID")
    try c.encode(recordID, forKey: "recordID")
    try c.encode(timestamp, forKey: "timestamp")
    try c.encode(problemID, forKey: "problemID")
    try c.encode(title, forKey: "title")
    try c.encode(problemURL, forKey: "problemURL")
    try c.encode(verdict, forKey: "verdict")
    try c.encode(accepted, forKey: "accepted")
    try c.encodeIfPresent(language, forKey: "language")
    try c.encodeIfPresent(difficulty, forKey: "difficulty")
    try c.encodeIfPresent(recordURL, forKey: "recordURL")
  }
}

extension SyncInfo {
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: JSONKey.self)
    self.init(
      accountID: try c.decode(UUID.self, forKey: "accountID"),
      lastSuccess: try c.decodeIfPresent(Date.self, forKey: "lastSuccess"),
      lastAttempt: try c.decodeIfPresent(Date.self, forKey: "lastAttempt"),
      error: try c.decodeIfPresent(String.self, forKey: "error"),
      coverage: try c.decodeIfPresent(String.self, forKey: "coverage") ?? "尚未采集",
      complete: try c.decodeIfPresent(Bool.self, forKey: "complete") ?? false,
      nextPage: try c.decodeIfPresent(Int.self, forKey: "nextPage") ?? 1,
      cursor: try c.decodeIfPresent(Int.self, forKey: "cursor") ?? 0)
    extraFields = try c.extras(excluding: [
      "accountID", "lastSuccess", "lastAttempt", "error", "coverage", "complete", "nextPage",
      "cursor",
    ])
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: JSONKey.self)
    try c.extras(
      extraFields,
      excluding: [
        "accountID", "lastSuccess", "lastAttempt", "error", "coverage", "complete", "nextPage",
        "cursor",
      ])
    try c.encode(accountID, forKey: "accountID")
    try c.encodeIfPresent(lastSuccess, forKey: "lastSuccess")
    try c.encodeIfPresent(lastAttempt, forKey: "lastAttempt")
    try c.encodeIfPresent(error, forKey: "error")
    try c.encode(coverage, forKey: "coverage")
    try c.encode(complete, forKey: "complete")
    try c.encode(nextPage, forKey: "nextPage")
    try c.encode(cursor, forKey: "cursor")
  }
}
