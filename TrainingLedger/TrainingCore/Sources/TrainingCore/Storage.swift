import Foundation

public actor TrainingRepository {
  public let url: URL
  public let legacyURL: URL?
  public init(url: URL, legacyURL: URL? = nil) {
    self.url = url
    self.legacyURL = legacyURL
  }
  public static var encoder: JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .custom { date, encoder in
      var c = encoder.singleValueContainer()
      let f = ISO8601DateFormatter()
      f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try c.encode(f.string(from: date))
    }
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
  }
  public static var decoder: JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder in
      let c = try decoder.singleValueContainer()
      let s = try c.decode(String.self)
      guard let date = TrainingDates.parse(s) else {
        throw TrainingError.invalid("JSON包含无效的ISO8601时间。")
      }
      return date
    }
    return d
  }
  public func load() throws -> TrainingArchive {
    let source: URL
    if FileManager.default.fileExists(atPath: url.path) {
      source = url
    } else if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
      source = legacyURL
    } else {
      return TrainingArchive()
    }
    let data = try Data(contentsOf: source)
    guard data.count <= 200_000_000 else { throw TrainingError.invalid("历史文件过大，请保留文件后联系开发者。") }
    let archive = try Self.decoder.decode(TrainingArchive.self, from: data)
    try archive.validate()
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    if source != url || (root?["version"] as? Int) == 1 { try save(archive) }
    return archive
  }
  public func save(_ archive: TrainingArchive) throws {
    try archive.validate()
    let data = try Self.encoder.encode(archive)
    guard data.count <= 200_000_000 else { throw TrainingError.invalid("历史文件达到200MB上限，请先导出备份。") }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: url.path) {
      try Data(contentsOf: url).write(to: url.appendingPathExtension("backup"), options: .atomic)
    }
    try data.write(to: url, options: .atomic)
  }
  public static func importArchive(_ data: Data, into old: TrainingArchive) throws
    -> TrainingArchive
  {
    guard data.count <= 200_000_000 else { throw TrainingError.invalid("导入文件不能超过200MB。") }
    let incoming = try decoder.decode(TrainingArchive.self, from: data)
    try incoming.validate()
    var result = old
    // Import never overwrites a locally edited real name or rolls back a newer verdict.
    for p in incoming.people {
      if let i = result.people.firstIndex(where: { $0.id == p.id }) {
        var local = result.people[i]
        if local.realName.isEmpty { local.realName = p.realName }
        if local.name.isEmpty { local.name = p.name }
        for account in p.accounts {
          if let j = local.accounts.firstIndex(where: { $0.id == account.id }) {
            guard local.accounts[j].identity == account.identity else {
              throw TrainingError.invalid("账号ID冲突：\(p.displayName) / \(account.oj.name)，原数据保留。")
            }
            if local.accounts[j].platformName.isEmpty {
              local.accounts[j].platformName = account.platformName
            }
            local.accounts[j].extraFields = account.extraFields.merging(
              local.accounts[j].extraFields
            ) { _, local in local }
          } else {
            local.accounts.append(account)
          }
        }
        local.extraFields = p.extraFields.merging(local.extraFields) { _, local in local }
        result.people[i] = local
      } else {
        result.people.append(p)
      }
    }
    result.schemaMinor = max(result.schemaMinor, incoming.schemaMinor)
    result.extraFields = incoming.extraFields.merging(result.extraFields) { _, local in local }
    result.submissions = try TrainingAnalysis.merge(
      result.submissions, incoming.submissions, preferIncoming: false)
    for s in incoming.sync where !result.sync.contains(where: { $0.accountID == s.accountID }) {
      var imported = s
      imported.coverage = "导入记录 · " + s.coverage
      imported.complete = false
      result.sync.append(imported)
    }
    try result.validate()
    return result
  }
}
