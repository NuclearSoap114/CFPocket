import Foundation
import Markdown

public struct PlanProblem: Codable, Equatable, Identifiable, Sendable {
  public let problem: ProblemID
  public var title: String
  public var accepted: Bool
  public var favorite: Bool
  public var id: String { problem.id }
  public init(problem: ProblemID, title: String, accepted: Bool = false, favorite: Bool = false) {
    self.problem = problem; self.title = title; self.accepted = accepted; self.favorite = favorite
  }
}
public struct PlanGroup: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var problems: [PlanProblem]
  public var completed: Int { problems.filter(\.accepted).count }
  public var fraction: Double { problems.isEmpty ? 0 : Double(completed) / Double(problems.count) }
  public init(id: String, problems: [PlanProblem]) { self.id = id; self.problems = problems }
}
public struct TrainingPlan: Codable, Equatable, Sendable {
  public let format: String
  public let schemaVersion: Int
  public let id: String
  public var title: String
  public let importedAt: Date
  public var updatedAt: Date
  public var selectedGroup: String?
  public var groups: [PlanGroup]
  public var sourceBaseline: PlanProgressBaseline?
  public var connection: PlanFolderConnection?
  public var editedAC: Set<String>?
  public var editedFavorites: Set<String>?
  public var editedGroup: Bool?
  public var total: Int { groups.reduce(0) { $0 + $1.problems.count } }
  public var completed: Int { groups.reduce(0) { $0 + $1.completed } }
  public var favorites: Int { groups.reduce(0) { $0 + $1.problems.filter(\.favorite).count } }
  public var completedGroups: Int { groups.filter { $0.completed == $0.problems.count }.count }
  public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
  public var currentGroup: PlanGroup? {
    if let selectedGroup { return groups.first { $0.id == selectedGroup } }
    return groups.first { $0.completed < $0.problems.count }
  }
  public init(title: String, groups: [PlanGroup], selectedGroup: String? = nil, now: Date = Date()) {
    format = "CFPocket.TrainingPlan"; schemaVersion = 1
    id = "obsidian-cf-az"; self.title = title; self.groups = groups
    self.selectedGroup = selectedGroup; importedAt = now; updatedAt = now
    sourceBaseline = PlanProgressBaseline(groups: groups, selectedGroup: selectedGroup)
    connection = nil
  }
  public func validate() throws {
    guard format == "CFPocket.TrainingPlan", schemaVersion == 1, id == "obsidian-cf-az",
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120,
      !groups.isEmpty, groups.count <= 26, total <= 3000,
      Set(groups.map(\.id)).count == groups.count,
      selectedGroup == nil || groups.contains(where: { $0.id == selectedGroup }),
      importedAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite
    else { throw PocketError.invalid("题单格式或分组信息不完整，原进度未改动。") }
    var seen = Set<String>()
    for group in groups {
      guard group.id.range(of: #"\A[A-Z]\z"#, options: .regularExpression) != nil, !group.problems.isEmpty else { throw PocketError.invalid("题单包含无效或空的分组。") }
      for item in group.problems {
        guard seen.insert(item.id).inserted, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.title.count <= 500 else { throw PocketError.invalid("题单包含重复题目或无效名称。") }
      }
    }
    if let connection, connection.bookmark.count > 1_000_000 { throw PocketError.invalid("题单文件夹凭据过大。") }
    if let sourceBaseline, sourceBaseline.flags.count > 3000 { throw PocketError.invalid("题单同步基线过大。") }
    guard (editedAC?.count ?? 0) <= 3000, (editedFavorites?.count ?? 0) <= 3000 else { throw PocketError.invalid("题单待同步标记过多。") }
  }
  /// Reimport changes the roster, but never resets a local checkbox (including an intentional uncheck).
  public func mergingRoster(_ incoming: TrainingPlan) throws -> TrainingPlan {
    try validate(); try incoming.validate()
    var result = incoming
    let old = Dictionary(uniqueKeysWithValues: groups.flatMap(\.problems).map { ($0.id, $0) })
    for g in result.groups.indices {
      for p in result.groups[g].problems.indices {
        if let saved = old[result.groups[g].problems[p].id] {
          result.groups[g].problems[p].accepted = saved.accepted
          result.groups[g].problems[p].favorite = saved.favorite
        }
      }
    }
    result.selectedGroup = selectedGroup.flatMap { selected in result.groups.contains { $0.id == selected } ? selected : nil }
    result.connection = connection
    var baseline = sourceBaseline ?? PlanProgressBaseline(groups: groups, selectedGroup: selectedGroup)
    for item in incoming.groups.flatMap(\.problems) where baseline.flags[item.id] == nil { baseline.flags[item.id] = PlanFlags(item) }
    result.sourceBaseline = baseline
    result.editedAC = editedAC; result.editedFavorites = editedFavorites; result.editedGroup = editedGroup
    result.updatedAt = Date(); return result
  }
  public static func decode(_ data: Data) throws -> TrainingPlan {
    guard data.count <= 2_000_000 else { throw PocketError.invalid("题单文件超过 2 MB，未导入。") }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    var value = try decoder.decode(Self.self, from: data); value.connection = nil
    if value.sourceBaseline == nil { value.sourceBaseline = PlanProgressBaseline(groups: value.groups, selectedGroup: value.selectedGroup) }
    try value.validate(); return value
  }
  public func encoded() throws -> Data {
    try validate(); let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var portable = self; portable.connection = nil
    return try encoder.encode(portable)
  }
}

/// Parses the source Markdown structure, never evaluates Obsidian Tasks JavaScript.
public enum ObsidianPlanParser {
  public static func parse(title: String, overview: String, files: [String: String], now: Date = Date()) throws -> TrainingPlan {
    let letters = (65...90).map { String(UnicodeScalar($0)!) }
    guard Set(files.keys) == Set(letters) else { throw PocketError.invalid("需要 cf 文件夹内完整的 A.md～Z.md。请确认 iCloud 文件已经下载。") }
    guard overview.utf8.count <= 262_144 else { throw PocketError.invalid("训练总览文件过大。") }
    var selected: String?
    let lines = overview.components(separatedBy: .newlines)
    if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
      for line in lines.dropFirst() {
        if line.trimmingCharacters(in: .whitespaces) == "---" { break }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "训练组" {
          let group = String(parts[1]).components(separatedBy: " #")[0].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).uppercased()
          if letters.contains(group) { selected = group }
        }
      }
    }
    let groups = try letters.map { try parseGroup($0, markdown: files[$0]!) }
    let result = TrainingPlan(title: title, groups: groups, selectedGroup: selected, now: now)
    try result.validate(); return result
  }
  private static func parseGroup(_ group: String, markdown: String) throws -> PlanGroup {
    guard markdown.utf8.count <= 262_144 else { throw PocketError.invalid("\(group) 组文件过大。") }
    var entries: [PlanProblem] = []
    var item: PlanProblem?
    var flags = Set<String>()
    func finish() throws {
      guard let item else { return }
      guard flags == ["AC", "收藏"] else { throw PocketError.invalid("\(group) 组的 \(item.title) 缺少 AC 或收藏复选框，未导入不完整题单。") }
      entries.append(item)
    }
    for block in Document(parsing: markdown).children {
      if let heading = block as? Heading {
        try finish()
        guard heading.level == 3, heading.childCount == 1, let link = heading.child(at: 0) as? Link,
          let destination = link.destination, let url = URL(string: destination)
        else { throw PocketError.invalid("\(group) 组题目标题无法识别。请使用三级标题中的官方 CF 链接。") }
        item = PlanProblem(problem: try ProblemID(url: url), title: link.plainText); flags = []
      } else if let list = block as? UnorderedList {
        guard item != nil else { throw PocketError.invalid("\(group) 组有未关联题目的勾选项。") }
        for child in list.children {
          guard let row = child as? ListItem, let checkbox = row.checkbox,
            row.childCount == 1, let paragraph = row.child(at: 0) as? Paragraph
          else { throw PocketError.invalid("\(group) 组复选框格式未识别。") }
          let name = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
          guard ["AC", "收藏"].contains(name), flags.insert(name).inserted else { throw PocketError.invalid("\(group) 组有重复或未知的进度字段。") }
          if name == "AC" { item?.accepted = checkbox == .checked } else { item?.favorite = checkbox == .checked }
        }
      } else { throw PocketError.invalid("\(group) 组包含无法识别的内容，未跳过或丢弃题目。") }
    }
    try finish(); return PlanGroup(id: group, problems: entries)
  }
}
