import Foundation

public struct PlanFlags: Codable, Equatable, Sendable {
  public var accepted: Bool
  public var favorite: Bool
  public init(_ item: PlanProblem) { accepted = item.accepted; favorite = item.favorite }
}
public struct PlanProgressBaseline: Codable, Equatable, Sendable {
  public var flags: [String: PlanFlags]
  public var selectedGroup: String?
  public init(groups: [PlanGroup], selectedGroup: String?) {
    flags = Dictionary(groups.flatMap(\.problems).map { ($0.id, PlanFlags($0)) }, uniquingKeysWith: { first, _ in first })
    self.selectedGroup = selectedGroup
  }
}
public struct PlanFolderConnection: Codable, Equatable, Sendable {
  public var bookmark: Data
  public var folderName: String
  public var synchronizedAt: Date?
  public init(bookmark: Data, folderName: String) { self.bookmark = bookmark; self.folderName = folderName }
}
public extension TrainingPlan {
  var hasUnsyncedChanges: Bool {
    editedAC?.isEmpty == false || editedFavorites?.isEmpty == false || editedGroup == true || sourceBaseline != PlanProgressBaseline(groups: groups, selectedGroup: selectedGroup)
  }
  mutating func recordEdits(comparedTo old: TrainingPlan) {
    let before = Dictionary(uniqueKeysWithValues: old.groups.flatMap(\.problems).map { ($0.id, $0) })
    for item in groups.flatMap(\.problems) {
      if let previous = before[item.id] {
        if previous.accepted != item.accepted { if editedAC == nil { editedAC = [] }; editedAC?.insert(item.id) }
        if previous.favorite != item.favorite { if editedFavorites == nil { editedFavorites = [] }; editedFavorites?.insert(item.id) }
      }
    }
    if selectedGroup != old.selectedGroup { editedGroup = true }
  }
  func mergingObsidian(_ remote: TrainingPlan) throws -> TrainingPlan {
    try validate(); try remote.validate()
    let baseline = sourceBaseline ?? PlanProgressBaseline(groups: groups, selectedGroup: selectedGroup)
    let local = Dictionary(uniqueKeysWithValues: groups.flatMap(\.problems).map { ($0.id, $0) })
    let remoteIDs = Set(remote.groups.flatMap(\.problems).map(\.id))
    for (id, item) in local where !remoteIDs.contains(id) {
      if (baseline.flags[id].map { $0 != PlanFlags(item) } ?? false) || editedAC?.contains(id) == true || editedFavorites?.contains(id) == true {
        throw PocketError.invalid("Obsidian 已移除 \(id)，但手机仍有未同步的勾选。请先导出进度并核对题单，未覆盖任一端。")
      }
    }
    var merged = remote
    merged.connection = connection
    for g in merged.groups.indices {
      for p in merged.groups[g].problems.indices {
        let id = merged.groups[g].problems[p].id
        if let item = local[id], let base = baseline.flags[id] {
          // Each boolean is merged independently. Two changes away from the same
          // boolean baseline necessarily agree; an unchanged local field pulls remote.
          if item.accepted != base.accepted || editedAC?.contains(id) == true { merged.groups[g].problems[p].accepted = item.accepted }
          if item.favorite != base.favorite || editedFavorites?.contains(id) == true { merged.groups[g].problems[p].favorite = item.favorite }
        }
      }
    }
    if selectedGroup != baseline.selectedGroup || editedGroup == true {
      if remote.selectedGroup != baseline.selectedGroup && remote.selectedGroup != selectedGroup {
        throw PocketError.invalid("训练组在手机与 Obsidian 两边被改成不同值。Obsidian 当前是 \(remote.selectedGroup ?? "自动")；请先统一训练组后重试，勾选仍保留。")
      }
      merged.selectedGroup = selectedGroup
    }
    try merged.validate()
    merged.sourceBaseline = PlanProgressBaseline(groups: merged.groups, selectedGroup: merged.selectedGroup)
    merged.editedAC = nil; merged.editedFavorites = nil; merged.editedGroup = nil
    merged.updatedAt = Date()
    return merged
  }
}

public enum ObsidianPlanPatcher {
  /// Changes checkbox characters only; headings, task queries, spacing and links survive byte for byte.
  public static func patchGroup(_ markdown: String, target: PlanGroup) throws -> String {
    let expression = try NSRegularExpression(pattern: #"(?m)^[ \t]*[-+*][ \t]+\[([ xX])\][ \t]+(AC|收藏)[ \t]*\r?$"#)
    let ns = markdown as NSString
    let matches = expression.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
    guard matches.count == target.problems.count * 2 else { throw PocketError.invalid("\(target.id) 组复选框位置不完整，未写回。") }
    var result = markdown
    for (i, match) in matches.enumerated().reversed() {
      let entry = target.problems[i / 2]
      let checked = ns.substring(with: match.range(at: 2)) == "AC" ? entry.accepted : entry.favorite
      let current = ns.substring(with: match.range(at: 1)).lowercased() == "x"
      if checked != current, let range = Range(match.range(at: 1), in: result) { result.replaceSubrange(range, with: checked ? "x" : " ") }
    }
    return result
  }
  public static func patchOverview(_ markdown: String, selected: String?, previous: String?) throws -> String {
    guard selected != previous else { return markdown }
    let newline = markdown.contains("\r\n") ? "\r\n" : "\n"
    var lines = markdown.components(separatedBy: newline)
    let value = selected ?? "自动"
    if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
       let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
      for i in 1..<close {
        let pieces = lines[i].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if pieces.count == 2, pieces[0].trimmingCharacters(in: .whitespaces) == "训练组" {
          let old = String(pieces[1]); let comment = old.range(of: " #").map { String(old[$0.lowerBound...]) } ?? ""
          lines[i] = String(pieces[0]) + ": " + value + comment
          return lines.joined(separator: newline)
        }
      }
      lines.insert("训练组: " + value, at: close); return lines.joined(separator: newline)
    }
    return "---" + newline + "训练组: " + value + newline + "---" + newline + markdown
  }
}

/// Uses coordinated access to the complete source, then validates every patch before any write.
/// Callers hold the security-scoped folder grant for the lifetime of this asynchronous operation.
public enum ObsidianPlanFolder {
  public static func synchronize(root: URL, local: TrainingPlan, backupDirectory: URL) async throws -> TrainingPlan {
    let letters = (65...90).map { String(UnicodeScalar($0)!) }
    let names = ["训练总览.md"] + letters.map { "cf/\($0).md" }
    let intents = names.map { NSFileAccessIntent.writingIntent(with: root.appendingPathComponent($0), options: []) }
    let coordinator = NSFileCoordinator()
    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
    return try await withCheckedThrowingContinuation { continuation in
      coordinator.coordinate(with: intents, queue: queue) { error in
        _ = coordinator
        if let error { continuation.resume(throwing: error); return }
        do {
          for folder in [root, root.appendingPathComponent("cf")] {
            let value = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard value.isDirectory == true, value.isSymbolicLink != true else { throw PocketError.invalid("请选择真实题单文件夹，不能使用替身或链接目录。") }
          }
          var original: [String: Data] = [:]
          for (i, intent) in intents.enumerated() {
            guard NSFileVersion.unresolvedConflictVersionsOfItem(at: intent.url)?.isEmpty != false else { throw PocketError.unavailable("\(names[i]) 有尚未解决的 iCloud 文件冲突，请先在笔记中处理后重试。") }
            let value = try intent.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard value.isRegularFile == true, value.isSymbolicLink != true, (value.fileSize ?? 262_145) <= 262_144 else { throw PocketError.invalid("\(names[i]) 尚未下载、过大或不是普通文件。") }
            original[names[i]] = try Data(contentsOf: intent.url)
          }
          func text(_ name: String, in bytes: [String: Data]) throws -> String {
            guard let data = bytes[name], let value = String(data: data, encoding: .utf8) else { throw PocketError.invalid("\(name) 不是完整 UTF-8 文本。") }; return value
          }
          func parse(_ bytes: [String: Data]) throws -> TrainingPlan {
            let files = try Dictionary(uniqueKeysWithValues: letters.map { ($0, try text("cf/\($0).md", in: bytes)) })
            return try ObsidianPlanParser.parse(title: local.title, overview: text("训练总览.md", in: bytes), files: files)
          }
          let remote = try parse(original)
          var merged = try local.mergingObsidian(remote)
          var patched = original
          for group in merged.groups { patched["cf/\(group.id).md"] = Data(try ObsidianPlanPatcher.patchGroup(text("cf/\(group.id).md", in: original), target: group).utf8) }
          patched["训练总览.md"] = Data(try ObsidianPlanPatcher.patchOverview(text("训练总览.md", in: original), selected: merged.selectedGroup, previous: remote.selectedGroup).utf8)
          let checked = try parse(patched)
          guard checked.groups == merged.groups, checked.selectedGroup == merged.selectedGroup else { throw PocketError.invalid("写回预检不一致，文件未改动。") }
          let changed = names.filter { original[$0] != patched[$0] }
          if !changed.isEmpty {
            let backup = backupDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: backup.appendingPathComponent("cf"), withIntermediateDirectories: true)
            for name in names { try original[name]!.write(to: backup.appendingPathComponent(name), options: .atomic) }
            // Also detect writers that do not participate in NSFileCoordinator.
            for (i, intent) in intents.enumerated() {
              guard try Data(contentsOf: intent.url) == original[names[i]] else { throw PocketError.unavailable("题单在同步期间又被修改，请重试；未用旧内容覆盖。") }
            }
            for (i, intent) in intents.enumerated() where changed.contains(names[i]) {
              guard try Data(contentsOf: intent.url) == original[names[i]] else { throw PocketError.unavailable("题单在写回时改变，部分勾选可能已写入。手机进度仍保留，请再次同步。") }
              try patched[names[i]]!.write(to: intent.url, options: .atomic)
            }
            for (i, intent) in intents.enumerated() {
              guard try Data(contentsOf: intent.url) == patched[names[i]] else { throw PocketError.unavailable("文件写回后未核对一致，手机进度仍保留，请重试。") }
            }
            let backups = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
              .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
              .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            for old in backups.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
          }
          merged.connection?.synchronizedAt = Date()
          continuation.resume(returning: merged)
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
