import Foundation

/// A versioned envelope, written atomically. Public caches and private workspaces never share files.
public actor PocketStorage {
  public let root: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var epoch = 0
  public func currentEpoch() -> Int { epoch }
  public init(root: URL) throws {
    self.root = root; encoder = JSONEncoder(); decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    for directory in ["public", "private", "ai-cache", "plans"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true) }
  }
  private struct Envelope<T: Codable>: Codable { let version: Int; let payload: T }
  private func read<T: Codable>(_ type: T.Type, _ name: String) throws -> T? {
    let url = root.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    guard data.count < 40_000_000 else { throw PocketError.invalid("本地文件过大，未加载。") }
    let envelope = try decoder.decode(Envelope<T>.self, from: data)
    guard envelope.version == 1 else { throw PocketError.invalid("本地数据版本暂不支持；原文件已保留。") }; return envelope.payload
  }
  private func write<T: Codable>(_ payload: T, _ name: String) throws {
    let url = root.appendingPathComponent(name)
    let bytes = try encoder.encode(Envelope(version: 1, payload: payload))
    guard bytes.count < 40_000_000 else { throw PocketError.invalid("记录达到本地容量上限，未覆盖已保存数据。请先导出并整理历史。") }
    _ = try decoder.decode(Envelope<T>.self, from: bytes)
    if FileManager.default.fileExists(atPath: url.path) {
      let old = try Data(contentsOf: url)
      // Preserve last valid version only; a corrupt current file must not overwrite recovery copy.
      if (try? decoder.decode(Envelope<T>.self, from: old)) != nil { try old.write(to: url.appendingPathExtension("previous"), options: .atomic) }
    }
    try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
  }
  public func loadLuoguProblem(_ id: ProblemID) throws -> LuoguProblem? { try read(LuoguProblem.self, "public/luogu-\(id.id).json") }
  public func saveLuoguProblem(_ value: LuoguProblem, id: ProblemID) throws { guard value.pid == (try LuoguParser.pid(id)) else { throw PocketError.invalid("洛谷缓存题号不一致。") }; try write(value, "public/luogu-\(id.id).json") }
  public func loadLuoguPages(_ id: ProblemID) throws -> [LuoguPage] {
    if let pages = try read([LuoguPage].self, "public/luogu-\(id.id)-solutions.json") { return pages }
    return try loadLuoguPage(id, page: 1).map { [$0] } ?? []
  }
  public func saveLuoguPages(_ pages: [LuoguPage], id: ProblemID) throws {
    let pid = try LuoguParser.pid(id)
    guard pages.enumerated().allSatisfy({ $0.element.pid == pid && $0.element.page == $0.offset + 1 }), try encoder.encode(pages).count <= 8_000_000 else { throw PocketError.invalid("本题离线题解超过 8 MB，原缓存保留。") }
    try write(pages, "public/luogu-\(id.id)-solutions.json")
  }
  public func loadLuoguPage(_ id: ProblemID, page: Int) throws -> LuoguPage? { try read(LuoguPage.self, "public/luogu-\(id.id)-page-\(page).json") }
  public func saveLuoguPage(_ value: LuoguPage, id: ProblemID) throws { guard value.pid == (try LuoguParser.pid(id)), value.page > 0 else { throw PocketError.invalid("洛谷题解缓存题号不一致。") }; try write(value, "public/luogu-\(id.id)-page-\(value.page).json") }
  public func loadSafety(_ id: ProblemID) throws -> ContestSafety? { try read(ContestSafety.self, "public/safety-\(id.contest).json") }
  public func saveSafety(_ value: ContestSafety, id: ProblemID) throws { try write(value, "public/safety-\(id.contest).json") }
  public func loadProblems() throws -> ProblemListCache? { try read(ProblemListCache.self, "public/problems.json") }
  public func saveProblems(_ value: ProblemListCache) throws {
    guard !value.problems.isEmpty, Set(value.problems.map(\.id)).count == value.problems.count else { throw PocketError.invalid("题库缓存为空或有重复项。") }
    try write(value, "public/problems.json")
  }
  public func loadStatement(_ id: ProblemID) throws -> Statement? { try read(Statement.self, "public/statement-\(id.id).json") }
  public func saveStatement(_ value: Statement) throws { guard fingerprint(value.html) == value.hash else { throw PocketError.invalid("题面指纹不一致。") }; try write(value, "public/statement-\(value.problem.id).json") }
  public func loadEditorial(_ id: ProblemID) throws -> EditorialEvidence? { try read(EditorialEvidence.self, "public/editorial-\(id.id).json") }
  public func saveEditorial(_ value: EditorialEvidence) throws { guard fingerprint(value.content) == value.hash else { throw PocketError.invalid("题解指纹不一致。") }; try write(value, "public/editorial-\(value.problem.id).json") }
  public func loadWorkspace(_ id: ProblemID) throws -> Workspace { try read(Workspace.self, "private/\(id.id).json") ?? Workspace(problem: id) }
  public func saveWorkspace(_ workspace: Workspace, expectedEpoch: Int? = nil) throws {
    if let expectedEpoch, expectedEpoch != epoch { throw PocketError.invalid("私人记录已删除，这份旧页面不会重新写回。") }
    guard (workspace.chatDraft ?? "").utf8.count <= 262_144, (workspace.pendingChatQuestion ?? "").utf8.count <= 262_144 else { throw PocketError.invalid("提问超过 256 KB，请缩短后重试。") }
    guard workspace.cpp.utf8.count <= 262_144, workspace.python.utf8.count <= 262_144, workspace.draft.utf8.count <= 262_144 else { throw PocketError.invalid("草稿或代码超过 256 KB；请先导出备份。") }
    guard workspace.stdin.utf8.count <= 65_536, workspace.expected.utf8.count <= 65_536, workspace.notes.utf8.count <= 262_144 else { throw PocketError.invalid("输入/期望输出上限64 KB，笔记上限256 KB；未覆盖已有记录。") }
    try write(workspace, "private/\(workspace.id).json")
  }
  public func allWorkspaces() throws -> [Workspace] {
    try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("private"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { url in
      guard let workspace = try read(Workspace.self, "private/\(url.lastPathComponent)") else { throw PocketError.invalid("草稿文件无法读取。") }; return workspace
    }.sorted { $0.updatedAt > $1.updatedAt }
  }
  public func clearPrivate() throws {
    epoch += 1
    for name in ["private", "ai-cache", "plans"] {
      let url = root.appendingPathComponent(name); try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }
  public func loadTrainingPlan() throws -> TrainingPlan? {
    var plan = try read(TrainingPlan.self, "plans/active.json"); try plan?.validate()
    if let value = plan, value.sourceBaseline == nil { plan?.sourceBaseline = PlanProgressBaseline(groups: value.groups, selectedGroup: value.selectedGroup) }
    return plan
  }
  public func saveTrainingPlan(_ plan: TrainingPlan, expectedEpoch: Int) throws {
    guard expectedEpoch == epoch else { throw PocketError.invalid("私人记录已删除，旧题单不会重新写回。") }
    try plan.validate(); try write(plan, "plans/active.json")
  }
  public func loadKnowledge(key: String) throws -> KnowledgeCard? { try read(KnowledgeCard.self, "ai-cache/\(fingerprint(key)).json") }
  public func saveKnowledge(_ card: KnowledgeCard, key: String) throws { try write(card, "ai-cache/\(fingerprint(key)).json") }
}
