import SwiftUI
import PocketCore

@MainActor @Observable final class TrainingPlanStore {
  let storage: PocketStorage
  var plan: TrainingPlan?
  var busy = false
  var error: String?
  var notice: String?
  private var epoch = 0
  private var loaded = false
  init(storage: PocketStorage) { self.storage = storage }
  func load() async {
    guard !loaded else { return }; loaded = true; busy = true; defer { busy = false }
    epoch = await storage.currentEpoch()
    do {
      plan = try await storage.loadTrainingPlan()
      let pending = URL.documentsDirectory.appendingPathComponent("训练题单导入.json")
      if FileManager.default.fileExists(atPath: pending.path) {
        let incoming = try TrainingPlan.decode(Data(contentsOf: pending))
        let merged = try plan?.mergingRoster(incoming) ?? incoming
        try await storage.saveTrainingPlan(merged, expectedEpoch: epoch); plan = merged
        // Retain the supplied file for recovery; never silently reapply its old checkboxes.
        try FileManager.default.moveItem(at: pending, to: URL.documentsDirectory.appendingPathComponent("题单导入备份-\(UUID().uuidString).json"))
      }
    } catch { self.error = "题单读取未完成：" + error.localizedDescription }
    busy = false
    // A slow file-provider download must not delay loading the problem library or drafts.
    if plan?.connection != nil { Task { await synchronizeIfNeeded() } }
  }
  func change(_ edit: (inout TrainingPlan) -> Void) {
    guard !busy, var next = plan else { return }
    let previous = next
    edit(&next); next.recordEdits(comparedTo: previous); next.updatedAt = Date(); busy = true; error = nil
    let expected = epoch
    Task {
      defer { busy = false }
      do {
        try await storage.saveTrainingPlan(next, expectedEpoch: expected)
        guard epoch == expected else { return }; plan = next
        busy = false
        if next.connection != nil { await synchronize() }
      }
      catch { self.error = "进度未保存：" + error.localizedDescription }
    }
  }
  func toggle(_ id: String, favorite: Bool) {
    change { next in
      for g in next.groups.indices {
        if let p = next.groups[g].problems.firstIndex(where: { $0.id == id }) {
          if favorite { next.groups[g].problems[p].favorite.toggle() } else { next.groups[g].problems[p].accepted.toggle() }
          return
        }
      }
    }
  }
  func importFile(_ url: URL) async {
    guard !busy else { return }; busy = true; error = nil; defer { busy = false }
    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      guard plan?.connection == nil else { throw PocketError.invalid("请先取消文件夹关联，再导入另一份进度备份。当前关联和进度均保留。") }
      let incoming = try await Task.detached(priority: .userInitiated) { try Self.readImport(url) }.value
      let next = try plan?.mergingRoster(incoming) ?? incoming
      try await storage.saveTrainingPlan(next, expectedEpoch: epoch); plan = next
      notice = "已导入 \(next.total) 道题。同题的本机 AC 与收藏优先保留；Obsidian 原文件未改动。"
    } catch { self.error = "导入未完成，原进度仍保留：" + error.localizedDescription }
  }
  func connectFolder(_ url: URL) async {
    guard !busy else { return }; busy = true; error = nil; notice = nil; defer { busy = false }
    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let expected = epoch
    do {
      let remote = try await Task.detached(priority: .userInitiated) { try Self.readImport(url) }.value
      var connected = plan ?? remote
      connected.connection = PlanFolderConnection(bookmark: try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), folderName: url.lastPathComponent)
      try await storage.saveTrainingPlan(connected, expectedEpoch: expected)
      guard epoch == expected else { return }; plan = connected
      busy = false; await synchronize()
    } catch { self.error = "文件夹关联未完成：" + error.localizedDescription }
  }
  func synchronizeIfNeeded() async {
    guard let connection = plan?.connection, !busy else { return }
    if plan?.hasUnsyncedChanges == true || Date().timeIntervalSince(connection.synchronizedAt ?? .distantPast) > 30 { await synchronize() }
  }
  func synchronize() async {
    guard !busy, var current = plan, let connection = current.connection else { return }
    busy = true; error = nil; notice = nil; defer { busy = false }
    let expected = epoch
    do {
      var stale = false
      let url = try URL(resolvingBookmarkData: connection.bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
      let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      if stale { current.connection?.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
      let storageRoot = await storage.root
      let backups = storageRoot.appendingPathComponent("plans/source-backups", isDirectory: true)
      let merged = try await ObsidianPlanFolder.synchronize(root: url, local: current, backupDirectory: backups)
      try await storage.saveTrainingPlan(merged, expectedEpoch: expected)
      guard epoch == expected else { return }; plan = merged
    } catch { self.error = "同步未完成，手机进度仍保留：" + error.localizedDescription + " 若文件夹已移动或权限失效，请重新关联。" }
  }
  nonisolated private static func readImport(_ selected: URL) throws -> TrainingPlan {
    // Coordinate provider reads so an iCloud placeholder is never treated as an empty file.
    func read(_ url: URL) throws -> Data {
      var result: Result<Data, Error>?
      var coordinationError: NSError?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { located in
        result = Result {
          let values = try located.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
          guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 2_000_001) <= 2_000_000 else { throw PocketError.invalid("文件不可读或超过 2 MB。") }
          return try Data(contentsOf: located)
        }
      }
      if let coordinationError { throw coordinationError }
      guard let result else { throw PocketError.unavailable("iCloud 文件尚未准备好，请在“文件”中下载后重试。") }
      return try result.get()
    }
    if selected.pathExtension.lowercased() == "json" { return try TrainingPlan.decode(read(selected)) }
    guard try selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw PocketError.invalid("请选择“ICPC区域赛训练”整个文件夹，或已导出的题单 JSON。总览文件本身不包含题目。") }
    let overviewData = try read(selected.appendingPathComponent("训练总览.md"))
    guard let overview = String(data: overviewData, encoding: .utf8) else { throw PocketError.invalid("总览不是 UTF-8 文本。") }
    var files: [String: String] = [:]
    for value in 65...90 {
      let group = String(UnicodeScalar(value)!)
      guard let text = String(data: try read(selected.appendingPathComponent("cf/\(group).md")), encoding: .utf8) else { throw PocketError.invalid("\(group) 组不是 UTF-8 文本。") }
      files[group] = text
    }
    return try ObsidianPlanParser.parse(title: selected.lastPathComponent, overview: overview, files: files)
  }
  func didClearPrivate() async { epoch = await storage.currentEpoch(); plan = nil; error = nil; notice = nil }
}
