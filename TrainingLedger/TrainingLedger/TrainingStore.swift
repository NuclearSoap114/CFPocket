import Foundation
import Observation
import TrainingCore

@MainActor @Observable final class TrainingStore {
  var archive = TrainingArchive()
  var loaded = false
  var isBusy = false
  var progress = ""
  var message: String?
  var storageFailure = false
  var activeAccount: UUID?
  var connection: OJAccount?
  private var preparingConnection = false
  var web = WebSession()
  private let repo: TrainingRepository
  private let collector = SubmissionCollector()
  private var syncTask: Task<Void, Never>?
  private var didStart = false
  private var peopleRevision = 0
  private var recordsRevision = 0
  private var syncRevision = 0
  @ObservationIgnored private var dataIndex = TrainingIndex(TrainingArchive())
  @ObservationIgnored private var selectionCache: [String: TrainingSummary] = [:]
  @ObservationIgnored private var cacheOrder: [String] = []
  @ObservationIgnored private var mutationLocked = false
  @ObservationIgnored private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
  var queryGeneration: String { "\(peopleRevision):\(recordsRevision)" }
  var people: [Person] {
    _ = peopleRevision
    return dataIndex.people
  }
  var accounts: [OJAccount] {
    _ = peopleRevision
    return dataIndex.accounts
  }
  private let seedDefaultPerson: Bool
  init(url: URL? = nil, seedDefaultPerson: Bool = true) {
    self.seedDefaultPerson = seedDefaultPerson
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("TrainingLedger", isDirectory: true)
    repo = TrainingRepository(
      url: url ?? root.appendingPathComponent("training.json"),
      legacyURL: url == nil ? root.appendingPathComponent("training-v1.json") : nil)
  }
  func start() async {
    guard !didStart else { return }
    didStart = true
    do {
      let saved = try await repo.load()
      let prepared = await Task.detached(priority: .userInitiated) { TrainingIndex(saved) }.value
      archive = saved
      dataIndex = prepared
      peopleRevision += 1
      recordsRevision += 1
      syncRevision += 1
      if seedDefaultPerson, archive.people.isEmpty, !UserDefaults.standard.bool(forKey: "initialized") {
        // A new installation starts without personal accounts. Add them in the app.
        UserDefaults.standard.set(true, forKey: "initialized")
      }
      loaded = true
      if !accounts.isEmpty, !ProcessInfo.processInfo.arguments.contains("--local-review"),
        UserDefaults.standard.object(forKey: "autoRefresh") as? Bool ?? true
      {
        refresh()
      }
    } catch {
      loaded = true
      storageFailure = true
      message = "本地数据读取失败，原文件仍保留。请从有效备份恢复。\n" + error.localizedDescription
    }
  }
  func info(_ id: UUID) -> SyncInfo {
    _ = syncRevision
    return dataIndex.syncByAccount[id] ?? SyncInfo(accountID: id)
  }
  func person(_ id: UUID) -> Person? {
    _ = peopleRevision
    return dataIndex.peopleByID[id]
  }
  func account(_ id: UUID) -> OJAccount? {
    _ = peopleRevision
    return dataIndex.accountsByID[id]
  }
  func owner(_ id: UUID) -> Person? {
    _ = peopleRevision
    return dataIndex.ownersByAccount[id]
  }
  func summary(accountIDs: Set<UUID>) -> TrainingSummary {
    _ = recordsRevision
    _ = peopleRevision
    let key =
      accountIDs.map(\.uuidString).sorted().joined(separator: ",")
      + TrainingDates.text(Date(), format: "yyyyMMdd")
    if let cached = selectionCache[key] { return cached }
    let summary = TrainingSummary(
      rows: dataIndex.rows(for: accountIDs),
      accounts: accountIDs.compactMap { dataIndex.accountsByID[$0] })
    selectionCache[key] = summary
    cacheOrder.append(key)
    if cacheOrder.count > 48 { selectionCache.removeValue(forKey: cacheOrder.removeFirst()) }
    return summary
  }
  func rows(accountIDs: Set<UUID>) -> [Submission] { summary(accountIDs: accountIDs).rows }
  func savePerson(_ person: Person) async throws {
    try person.validate()
    let prior = self.person(person.id)
    let identityChanged =
      prior.map { p in Set(p.accounts.map(\.identity)) != Set(person.accounts.map(\.identity)) }
      ?? false
    if isBusy, identityChanged {
      let task = syncTask
      stop()
      await task?.value
    }
    try await mutate { next in
      if let i = next.people.firstIndex(where: { $0.id == person.id }) {
        let changed = Set(
          next.people[i].accounts.filter { o in
            !person.accounts.contains(where: { $0.id == o.id && $0.identity == o.identity })
          }.map(\.id))
        next.submissions.removeAll { changed.contains($0.accountID) }
        next.sync.removeAll { changed.contains($0.accountID) }
        next.people[i] = person
      } else {
        next.people.append(person)
      }
    }
  }
  func toggleFavorite(_ id: UUID) async {
    do {
      try await mutate { next in
        if let i = next.people.firstIndex(where: { $0.id == id }) {
          next.people[i].favorite.toggle()
        }
      }
    } catch { message = error.localizedDescription }
  }
  func removePerson(_ id: UUID) async throws {
    if isBusy {
      let task = syncTask
      stop()
      await task?.value
    }
    try await mutate { next in
      let ids = Set(next.people.first(where: { $0.id == id })?.accounts.map(\.id) ?? [])
      next.people.removeAll { $0.id == id }
      next.submissions.removeAll { ids.contains($0.accountID) }
      next.sync.removeAll { ids.contains($0.accountID) }
    }
  }
  private func acquireMutation() async {
    if !mutationLocked {
      mutationLocked = true
      return
    }
    await withCheckedContinuation { mutationWaiters.append($0) }
  }
  private func releaseMutation() {
    if mutationWaiters.isEmpty {
      mutationLocked = false
    } else {
      mutationWaiters.removeFirst().resume()
    }
  }
  private func mutate(_ mutation: @escaping @Sendable (inout TrainingArchive) throws -> Void)
    async throws
  {
    await acquireMutation()
    defer { releaseMutation() }
    let old = archive
    let next = try await Task.detached(priority: .userInitiated) {
      var value = old
      try mutation(&value)
      value.revision = old.revision + 1
      return value
    }.value
    let recordsChanged = next.submissions != old.submissions
    let peopleChanged = next.people != old.people
    let statesChanged = next.sync != old.sync
    try await repo.save(next)
    let retained = recordsChanged ? nil : dataIndex.rowsByAccount
    let prepared = await Task.detached(priority: .userInitiated) {
      TrainingIndex(next, retainingRows: retained)
    }.value
    archive = next
    dataIndex = prepared
    storageFailure = false
    if recordsChanged || peopleChanged {
      selectionCache.removeAll(keepingCapacity: true)
      cacheOrder.removeAll(keepingCapacity: true)
    }
    if peopleChanged { peopleRevision += 1 }
    if recordsChanged { recordsRevision += 1 }
    if statesChanged { syncRevision += 1 }
  }
  func refresh(accountIDs: Set<UUID>? = nil) {
    guard loaded, !isBusy, !storageFailure else { return }
    let targets = accounts.filter { accountIDs == nil || accountIDs!.contains($0.id) }
    guard !targets.isEmpty else { return }
    isBusy = true
    message = nil
    syncTask = Task { [weak self] in
      guard let self else { return }
      for a in targets {
        if Task.isCancelled { break }
        await self.syncAccount(a)
      }
      for a in targets where a.oj == .nowcoder || a.oj == .vjudge {
        if Task.isCancelled { break }
        if self.info(a.id).lastSuccess != nil { await self.enrich(a) }
      }
      self.isBusy = false
      self.activeAccount = nil
      self.progress = ""
      self.syncTask = nil
    }
  }
  func stop() {
    syncTask?.cancel()
    web.cancel()
    progress = "正在停止…"
  }
  private func syncAccount(_ a: OJAccount) async {
    activeAccount = a.id
    let previous = info(a.id)
    var state = previous
    state.lastAttempt = Date()
    state.error = nil
    var cursor =
      a.oj == .atcoder && previous.complete
      ? max(
        0,
        Int(
          archive.submissions.filter { $0.accountID == a.id }.map(\.timestamp).max()?
            .timeIntervalSince1970 ?? 0) - 1) : a.oj == .atcoder ? previous.cursor : 0
    var url = SubmissionCollector.startURL(a, cursor: cursor)
    var page = 1
    var seenPages = Set<String>()
    do {
      while true {
        try Task.checkCancellation()
        progress = "\(owner(a.id)?.displayName ?? "") · \(a.oj.name) · 第\(page)页"
        let result: SubmissionPage
        do { result = try await collector.page(account: a, url: url, cursor: cursor) } catch {
          if a.oj == .codeforces || a.oj == .atcoder { throw error }
          // The app owns this WebKit session; no Mac login cookie is read or copied.
          let html = try await web.load(url, account: a)
          result = try await collector.parse(Data(html.utf8), account: a, url: url, cursor: cursor)
        }
        let fingerprint = result.rows.map(\.recordID).sorted().joined(separator: ",")
        guard result.rows.isEmpty || seenPages.insert(fingerprint).inserted else {
          throw TrainingError.invalid("来源重复返回同一页，已停止分页并保留已采集记录。")
        }
        state.lastSuccess = Date()
        state.error = nil
        state.complete = result.finished
        state.coverage = result.finished ? "已遍历来源当前可见记录" : "历史分页尚未结束"
        if a.oj == .atcoder {
          state.coverage = result.finished ? "AtCoder Problems已收录记录 · 第三方可能延迟" : state.coverage
        }
        if a.oj == .hydro { state.coverage = "本站公开非比赛记录" + (result.finished ? " · 已遍历" : " · 分页中") }
        state.nextPage = page + 1
        state.cursor = result.nextCursor ?? cursor
        let newState = state
        try await mutate { next in
          guard
            next.people.flatMap(\.accounts).contains(where: {
              $0.id == a.id && $0.identity == a.identity
            })
          else { throw CancellationError() }
          next.submissions = try TrainingAnalysis.merge(next.submissions, result.rows)
          next.sync.removeAll { $0.accountID == a.id }
          next.sync.append(newState)
        }
        if result.finished { break }
        page += 1
        if let c = result.nextCursor {
          cursor = c
          url = SubmissionCollector.startURL(a, cursor: c)
        } else if let u = result.nextURL {
          url = u
        } else {
          throw TrainingError.invalid("来源声明还有记录但未提供可用的分页位置。")
        }
        // No silent truncation: a safety stop remains partial and can be resumed by refreshing.
        if page > 5000 { throw TrainingError.invalid("单次采集达到5000页保护上限，已保留已读取记录。") }
        try await Task.sleep(for: .seconds(a.oj == .codeforces ? 2.2 : 1.2))
      }
    } catch {
      state.error =
        error is CancellationError ? "同步已停止，原记录及本次已读取页面仍保留。" : error.localizedDescription
      state.lastAttempt = Date()
      // A failed attempt must not advance lastSuccess or imply complete coverage.
      state.lastSuccess = info(a.id).lastSuccess
      state.complete = info(a.id).complete
      let failedState = state
      guard account(a.id)?.identity == a.identity else { return }
      do {
        try await mutate { next in
          next.sync.removeAll { $0.accountID == a.id }
          next.sync.append(failedState)
        }
      } catch { message = "保存采集状态失败：" + error.localizedDescription }
    }
  }
  private func enrich(_ a: OJAccount) async {
    let candidates = Dictionary(
      grouping: archive.submissions.filter { $0.accountID == a.id }, by: \.problemID
    ).compactMap { _, rs in rs.first }.sorted { $0.timestamp > $1.timestamp }
    for (index, row) in candidates.enumerated() {
      if Task.isCancelled { return }
      if a.oj == .vjudge && row.title != row.problemID {
        let hasOriginRating =
          row.problemID.hasPrefix("CodeForces-") || row.problemID.hasPrefix("AtCoder-")
        if !hasOriginRating || row.difficulty != nil { continue }
      }
      if a.oj == .nowcoder && row.difficulty != nil { continue }
      progress = "\(a.oj.name) · 补全题目 \(index+1)/\(candidates.count)"
      do {
        var meta: (String?, Difficulty?)
        do { meta = try await collector.metadata(for: row, oj: a.oj) } catch {
          if a.oj != .vjudge { continue }
          let html = try await web.load(URL(string: row.problemURL)!, account: a, metadata: true)
          meta = try TrainingHTML.problemMetadata(html, oj: a.oj)
        }
        if meta.0 == nil && meta.1 == nil { continue }
        let title = meta.0
        let difficulty = meta.1
        try await mutate { next in
          for i in next.submissions.indices
          where next.submissions[i].accountID == a.id
            && next.submissions[i].problemID == row.problemID
          {
            if let title, !title.isEmpty { next.submissions[i].title = title }
            if let difficulty { next.submissions[i].difficulty = difficulty }
          }
        }
      } catch { /* A metadata failure does not erase valid submission records. */  }
    }
  }
  func connect(_ account: OJAccount) {
    guard !preparingConnection else { return }
    preparingConnection = true
    Task {
      if isBusy {
        let task = syncTask
        stop()
        await task?.value
      }
      web.open(account.recordsURL)
      connection = account
      preparingConnection = false
    }
  }
  func connectDone(_ account: OJAccount) {
    connection = nil
    refresh(accountIDs: [account.id])
  }
  func exportData() async throws -> Data {
    let saved = archive
    return try await Task.detached(priority: .userInitiated) {
      try TrainingRepository.encoder.encode(saved)
    }.value
  }
  func importData(_ data: Data) async throws {
    if isBusy {
      let task = syncTask
      stop()
      await task?.value
    }
    try await mutate { next in next = try TrainingRepository.importArchive(data, into: next) }
  }
}
