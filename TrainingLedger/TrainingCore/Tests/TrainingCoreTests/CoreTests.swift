import Foundation
import Testing

@testable import TrainingCore

private func capturedFixtureAvailable(_ name: String) -> Bool {
  Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") != nil
}

private func fixture(_ name: String) throws -> Data {
  try Data(
    contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!)
}
private func html(_ name: String) throws -> String {
  String(data: try fixture(name), encoding: .utf8)!
}
private func record(
  account: UUID, id: String = "1", time: String = "2026-10-20 12:00:00", pid: String = "A",
  accepted: Bool = true
) -> Submission {
  Submission(
    accountID: account, recordID: id, timestamp: TrainingDates.parse(time)!, problemID: pid,
    title: "Problem " + pid, problemURL: "https://codeforces.com/problemset",
    verdict: accepted ? "OK" : "WA", accepted: accepted)
}

@Test(.enabled(if: capturedFixtureAvailable("cf-own.json"))) func realCFMapping() throws {
  let a = OJAccount(oj: .codeforces, handle: "fixture_user")
  let p = try APIParser.codeforces(fixture("cf-own.json"), account: a, from: 1, count: 1000)
  #expect(p.rows.count == 868)
  #expect(p.finished)
  #expect(p.rows.first?.title == "Gargari and Permutations")
  #expect(p.rows.first?.difficulty?.value == 1900)
  #expect(p.rows.first?.accepted == false)
  #expect(p.rows.first?.recordID == "396246848")
}
@Test(.enabled(if: capturedFixtureAvailable("cf-own.json"))) func cfWrongAccountAndFailureRejected() throws {
  let a = OJAccount(oj: .codeforces, handle: "another")
  #expect(throws: TrainingError.self) {
    try APIParser.codeforces(fixture("cf-own.json"), account: a, from: 1, count: 1000)
  }
  #expect(throws: TrainingError.self) {
    try APIParser.codeforces(
      Data("{\"status\":\"FAILED\",\"comment\":\"invalid handle\"}".utf8), account: a, from: 1,
      count: 1000)
  }
}
@Test(.enabled(if: capturedFixtureAvailable("at-own.json"))) func atcoderRealRecords() throws {
  let a = OJAccount(oj: .atcoder, handle: "fixture_user")
  let p = try APIParser.atcoder(fixture("at-own.json"), account: a, cursor: 0)
  #expect(p.rows.count == 249)
  #expect(p.finished)
  #expect(p.rows.first?.problemID == "abc355_a")
  #expect(p.rows.first?.timestamp == Date(timeIntervalSince1970: 1_732_273_834))
  #expect(p.rows.first?.difficulty == nil)
}
@Test func atcoderPageBoundaryIsOverlapped() throws {
  let a = OJAccount(oj: .atcoder, handle: "u")
  let raw = (0..<500).map { i in
    [
      "id": i + 1, "epoch_second": 1_000_000_000 + i / 2, "problem_id": "a_\(i)", "contest_id": "a",
      "user_id": "u", "result": "AC",
    ] as [String: Any]
  }
  let p = try APIParser.atcoder(JSONSerialization.data(withJSONObject: raw), account: a, cursor: 0)
  #expect(!p.finished)
  #expect(p.nextCursor == 1_000_000_249)
  let saturated = raw.map { x in
    var x = x
    x["epoch_second"] = 1_000_000_000
    return x
  }
  #expect(throws: TrainingError.self) {
    try APIParser.atcoder(
      JSONSerialization.data(withJSONObject: saturated), account: a, cursor: 1_000_000_000)
  }
}
@Test func luoguOfficialDifficultyAndTime() throws {
  let a = OJAccount(oj: .luogu, handle: "10001")
  let p = try APIParser.luogu(fixture("luogu.json"), account: a, page: 1)
  #expect(p.rows.count == 2)
  #expect(!p.finished)
  #expect(p.rows.first?.difficulty?.label == "提高+/省选−")
  #expect(p.rows.first?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
  let allAC = p.rows.allSatisfy { $0.accepted }
  #expect(allAC)
  #expect(p.nextURL?.query?.contains("page=2") == true)
}
@Test func luoguJSONInHTML() throws {
  let a = OJAccount(oj: .luogu, handle: "10001")
  let s =
    "<html><script type=\"application/json\" id=\"lentille-context\">\(String(data:try fixture("luogu.json"),encoding:.utf8)!)</script></html>"
  let p = try TrainingHTML.parse(s, account: a, url: a.recordsURL)
  #expect(p.rows.count == 2)
  #expect(throws: TrainingError.self) {
    try APIParser.luogu(fixture("luogu.json"), account: OJAccount(oj: .luogu, handle: "1"), page: 1)
  }
}
@Test(.enabled(if: capturedFixtureAvailable("nowcoder.html"))) func nowcoderActualHTML() throws {
  let a = OJAccount(oj: .nowcoder, handle: "10002")
  let p = try TrainingHTML.parse(html("nowcoder.html"), account: a, url: a.recordsURL)
  #expect(p.rows.count == 100)
  #expect(p.rows.first?.title == "小月的数组")
  #expect(p.rows.first?.recordID == "84615034")
  #expect(p.rows.first?.timestamp == TrainingDates.parse("2026-08-28 22:51:03"))
  #expect(p.rows.contains { !$0.accepted })
  #expect(p.nextURL != nil)
}
@Test(.enabled(if: capturedFixtureAvailable("qoj.html"))) func qojRealRowAndTimezone() throws {
  let a = OJAccount(oj: .qoj, handle: "fixture_user")
  let p = try TrainingHTML.parse(html("qoj.html"), account: a, url: a.recordsURL)
  #expect(p.rows.count == 1)
  #expect(p.rows[0].accepted)
  #expect(p.rows[0].title.contains("Cyclic Shift"))
  #expect(TrainingDates.text(p.rows[0].timestamp) == "2026-10-20 16:24")
  #expect(p.nextURL?.query?.contains("page=2") == true)
  #expect(throws: TrainingError.self) {
    try TrainingHTML.parse(
      html("qoj.html"), account: OJAccount(oj: .qoj, handle: "other"), url: a.recordsURL)
  }
}
@Test(.enabled(if: capturedFixtureAvailable("hydro.html"))) func hydroRealTimestampAndIsolation() throws {
  let a = OJAccount(oj: .hydro, handle: "0")
  let p = try TrainingHTML.parse(html("hydro.html"), account: a, url: a.recordsURL)
  #expect(p.rows[0].timestamp == Date(timeIntervalSince1970: 1_793_083_653))
  #expect(p.rows[0].title.contains("Strings of Impurity"))
  #expect(p.nextURL?.query?.contains("page=2") == true)
  #expect(throws: TrainingError.self) {
    try TrainingHTML.parse(
      html("hydro.html"), account: OJAccount(oj: .hydro, handle: "10003"), url: a.recordsURL)
  }
}
@Test func hydroExplicitEmptyAndChallenges() throws {
  let a = OJAccount(oj: .hydro, handle: "10003")
  let p = try TrainingHTML.parse("<body>喔，目前没有符合过滤条件的任务。</body>", account: a, url: a.recordsURL)
  #expect(p.rows.isEmpty && p.finished)
  for s in [
    "<html>Cerberus Challenge</html>", "<html>Just a moment...</html>", "<html>login</html>",
    "<html></html>",
  ] {
    #expect(throws: TrainingError.self) { try TrainingHTML.parse(s, account: a, url: a.recordsURL) }
  }
}
@Test func vjudgeSentinelAndMillisecondTime() throws {
  let a = OJAccount(oj: .vjudge, handle: "fixture_user")
  let p = try APIParser.vjudge(
    fixture("vjudge.json"), account: a, url: SubmissionCollector.startURL(a))
  #expect(p.finished)
  #expect(p.rows.count == 2)
  #expect(p.rows[0].timestamp == Date(timeIntervalSince1970: 1_700_000_000))
  #expect(p.rows[0].problemID == "QOJ-9769")
  #expect(throws: TrainingError.self) {
    try APIParser.vjudge(
      fixture("vjudge.json"), account: OJAccount(oj: .vjudge, handle: "other"),
      url: SubmissionCollector.startURL(a))
  }
}
@Test func metadataParser() throws {
  let v = try TrainingHTML.problemMetadata("<html><h2>Rolling Stones</h2></html>", oj: .vjudge)
  #expect(v.0 == "Rolling Stones")
  let n = try TrainingHTML.problemMetadata("<html><body>难度：3</body></html>", oj: .nowcoder)
  #expect(n.1?.value == 3)
}
@Test func accountValidationAndHydroDomains() throws {
  for h in ["", "u?x=1", "u&a=b", "https://foo", "u\n"] {
    let a = OJAccount(oj: .codeforces, handle: h)
    if h != "u\n" { #expect(throws: TrainingError.self) { try a.validate() } }
  }
  #expect(throws: TrainingError.self) { try OJAccount(oj: .luogu, handle: "name").validate() }
  #expect(throws: TrainingError.self) {
    try OJAccount(oj: .hydro, handle: "u", site: "bad url").validate()
  }
  #expect(throws: TrainingError.self) {
    try OJAccount(oj: .hydro, handle: "u", site: "https://user:pass@example.com").validate()
  }
  let a = OJAccount(oj: .hydro, handle: "5", site: "https://example.com/d/class")
  try a.validate()
  #expect(a.recordsURL.path == "/d/class/record")
}
@Test func favoritesAndMultiplePeople() {
  let p1 = Person(name: "Z", favorite: true)
  let p2 = Person(name: "A")
  let p3 = Person(name: "B", favorite: true)
  #expect(TrainingAnalysis.sortedPeople([p2, p1, p3]).map(\.name) == ["B", "Z", "A"])
}
@Test func metricSeparatesAttemptsFromSolved() {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let b = OJAccount(oj: .atcoder, handle: "u")
  let rows = [
    record(account: a.id, id: "1", accepted: false), record(account: a.id, id: "2"),
    record(account: a.id, id: "3"), record(account: b.id, id: "1"),
  ]
  let d = TrainingAnalysis.days(rows, accounts: [a, b])[0]
  #expect(d.submissions == 4)
  #expect(d.acceptedSubmissions == 3)
  #expect(d.solved == 2)
  let s = TrainingAnalysis.stats(
    rows, accounts: [a, b], now: TrainingDates.parse("2026-10-20 18:00:00")!)
  #expect(s.submissions == 4)
  #expect(s.uniqueSolved == 2)
  #expect(s.currentStreak == 1)
}
@Test func timeBoundaryAndLeapYear() {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let r1 = record(account: a.id, id: "1", time: "2026-10-20T15:59:59Z")
  let r2 = record(account: a.id, id: "2", time: "2026-10-20T16:00:00Z")
  #expect(TrainingAnalysis.days([r1, r2], accounts: [a]).count == 2)
  #expect(TrainingAnalysis.yearDates(2024).count == 366)
  #expect(TrainingAnalysis.yearDates(2026).count == 365)
}
@Test func streakDoesNotBridgeMissingDays() {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let rows = [
    record(account: a.id, id: "1", time: "2026-10-18 12:00:00"),
    record(account: a.id, id: "2", time: "2026-10-19 12:00:00"),
    record(account: a.id, id: "3", time: "2026-10-21 12:00:00"),
  ]
  let s = TrainingAnalysis.stats(
    rows, accounts: [a], now: TrainingDates.parse("2026-10-23 12:00:00")!)
  #expect(s.currentStreak == 0)
  #expect(s.longestStreak == 2)
  #expect(s.activeDays == 3)
}
@Test func mergeRejudgingAndDifficulty() throws {
  let a = OJAccount(oj: .codeforces, handle: "u")
  var r = record(account: a.id, accepted: false)
  r.difficulty = Difficulty(value: 1200, label: "1200", source: "CF")
  let incoming = record(account: a.id)
  let m = try TrainingAnalysis.merge([r], [incoming])
  #expect(m.count == 1)
  #expect(m[0].accepted)
  #expect(m[0].difficulty?.value == 1200)
}
@Test func archiveIntegrity() throws {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let p = Person(name: "A", accounts: [a])
  let r = record(account: a.id)
  let ok = TrainingArchive(people: [p], submissions: [r])
  try ok.validate()
  #expect(throws: TrainingError.self) {
    try TrainingArchive(people: [p], submissions: [r, r]).validate()
  }
  #expect(throws: TrainingError.self) { try TrainingArchive(submissions: [r]).validate() }
  var bad = ok
  bad.version = 9
  #expect(throws: TrainingError.self) { try bad.validate() }
  var unsafe = r
  unsafe.problemURL = "javascript:alert(1)"
  #expect(throws: TrainingError.self) { try unsafe.validate() }
}
@Test func atomicPersistenceRestartAndImport() async throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let url = dir.appendingPathComponent("history.json")
  let a = OJAccount(oj: .codeforces, handle: "u")
  let p = Person(name: "A", favorite: true, accounts: [a])
  let archive = TrainingArchive(people: [p], submissions: [record(account: a.id)])
  let repo = TrainingRepository(url: url)
  #expect(try await repo.load().people.isEmpty)
  try await repo.save(archive)
  let reload = try await TrainingRepository(url: url).load()
  #expect(reload == archive)
  let data = try TrainingRepository.encoder.encode(archive)
  let merged = try TrainingRepository.importArchive(data, into: reload)
  #expect(merged.submissions.count == 1)
  try await repo.save(merged)
  #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("backup").path))
  let original = try Data(contentsOf: url)
  var bad = archive
  bad.version = 9
  #expect(throws: TrainingError.self) {
    try TrainingRepository.importArchive(TrainingRepository.encoder.encode(bad), into: reload)
  }
  #expect(try Data(contentsOf: url) == original)
  try Data("invalid".utf8).write(to: url)
  await #expect(throws: (any Error).self) { try await repo.load() }
  try FileManager.default.removeItem(at: dir)
}

@Test func sameOJProblemAcrossTwoHandlesCountsOnce() {
  let a = OJAccount(oj: .codeforces, handle: "one")
  let b = OJAccount(oj: .codeforces, handle: "two")
  let rows = [record(account: a.id), record(account: b.id)]
  let stats = TrainingAnalysis.stats(rows, accounts: [a, b])
  #expect(stats.submissions == 2)
  #expect(stats.uniqueSolved == 1)
  #expect(TrainingAnalysis.days(rows, accounts: [a, b])[0].solved == 1)
}
@Test func importedLinksMustMatchOJ() throws {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let p = Person(name: "A", accounts: [a])
  var row = record(account: a.id)
  row.problemURL = "https://example.com/wrong-source"
  #expect(throws: TrainingError.self) {
    try TrainingArchive(people: [p], submissions: [row]).validate()
  }
}
private actor MetadataHTTPStub: HTTPGetting {
  private var calls: [String] = []
  func get(_ url: URL) async throws -> Data {
    calls.append(url.path)
    if url.path == "/api/problemset.problems" {
      return Data(
        "{\"status\":\"OK\",\"result\":{\"problems\":[{\"contestId\":743,\"index\":\"C\",\"name\":\"Test problem metadata\",\"rating\":1200}]}}"
          .utf8)
    }
    throw TrainingError.network("Test network failure")
  }
  func count() -> Int { calls.count }
}
@Test func vjudgeOriginalCFDifficultyUsesPublicMetadataAndCache() async throws {
  let http = MetadataHTTPStub()
  let collector = SubmissionCollector(http: http)
  let a = OJAccount(oj: .vjudge, handle: "u")
  var row = record(account: a.id, pid: "CodeForces-743C")
  row.problemURL = "https://vjudge.net/problem/CodeForces-743C"
  let first = try await collector.metadata(for: row, oj: .vjudge)
  let second = try await collector.metadata(for: row, oj: .vjudge)
  #expect(first.0 == "Test problem metadata")
  #expect(first.1?.value == 1200)
  #expect(second.1 == first.1)
  let count = await http.count()
  #expect(count == 1)
}
@Test func challengePageNeverBecomesProblemName() throws {
  #expect(throws: TrainingError.self) {
    try TrainingHTML.problemMetadata(
      "<html><title>Just a moment...</title><h2>Checking your browser</h2></html>", oj: .vjudge)
  }
}

@Test func realNamesAndPlatformIDMappings() throws {
  let account = OJAccount(oj: .nowcoder, handle: "123456", platformName: "算法昵称")
  let person = Person(name: "训练昵称", accounts: [account], realName: "测试姓名")
  #expect(person.displayName == "测试姓名")
  #expect(person.alias == "训练昵称")
  #expect(person.matches("测试姓名"))
  #expect(person.matches("123456"))
  #expect(person.matches("算法昵称"))
  let onlyRealName = Person(name: "", realName: "测试姓名")
  try onlyRealName.validate()
  let oldIdentity = account.identity
  var renamed = account
  renamed.platformName = "新平台昵称"
  #expect(renamed.identity == oldIdentity)
}
@Test func legacyV1MigratesAndIDsRemainStable() throws {
  let source = try fixture("archive-v1.json")
  let old = try JSONSerialization.jsonObject(with: source) as! [String: Any]
  let archive = try TrainingRepository.decoder.decode(TrainingArchive.self, from: source)
  try archive.validate()
  let json = try TrainingRepository.encoder.encode(archive)
  let root = try JSONSerialization.jsonObject(with: json) as! [String: Any]
  #expect(archive.version == 2)
  #expect(root["format"] as? String == TrainingArchive.formatIdentifier)
  #expect(root["schemaVersion"] as? Int == 2)
  let people = root["people"] as! [[String: Any]]
  let oldPeople = old["people"] as! [[String: Any]]
  #expect(people[0]["id"] as? String == oldPeople[0]["id"] as? String)
  #expect(people[0]["nickname"] as? String == oldPeople[0]["name"] as? String)
  #expect(archive.people[0].realName.isEmpty)
  let accounts = people[0]["accounts"] as! [[String: Any]]
  #expect(accounts[0]["platformID"] as? String == "fixture_user")
  let reread = try TrainingRepository.decoder.decode(TrainingArchive.self, from: json)
  #expect(reread == archive)
}
@Test func repositoryMigratesLegacyFileWithoutModifyingSource() async throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let original = try fixture("archive-v1.json")
  let oldURL = dir.appendingPathComponent("training-v1.json")
  let newURL = dir.appendingPathComponent("training.json")
  try original.write(to: oldURL)
  let repo = TrainingRepository(url: newURL, legacyURL: oldURL)
  let first = try await repo.load()
  let second = try await repo.load()
  #expect(first == second)
  #expect(first.version == 2)
  #expect(try Data(contentsOf: oldURL) == original)
  #expect(FileManager.default.fileExists(atPath: newURL.path))
  try FileManager.default.removeItem(at: dir)
}
@Test func futureMinorAndUnknownFieldsRoundTrip() throws {
  var a = try TrainingRepository.decoder.decode(
    TrainingArchive.self, from: fixture("archive-v1.json"))
  a.schemaMinor = 4
  a.extraFields["futureCheckpoint"] = .object([
    "lastID": .string("99999999999999999999"), "integer": .integer(Int64.max),
    "decimal": .number(Decimal(string: "12345678901234567890.123")!),
  ])
  a.people[0].extraFields["futureProfile"] = .string("保留")
  a.people[0].accounts[0].extraFields["futureBinding"] = .bool(true)
  a.submissions[0].extraFields["trainingNote"] = .string("本地备注")
  if a.submissions[0].difficulty != nil {
    a.submissions[0].difficulty!.extraFields["scaleVersion"] = .integer(5)
  }
  let encoded = try TrainingRepository.encoder.encode(a)
  let reread = try TrainingRepository.decoder.decode(TrainingArchive.self, from: encoded)
  #expect(reread == a)
  #expect(String(data: encoded, encoding: .utf8)!.contains("9223372036854775807"))
}
@Test func unknownMajorRejectedBeforeAnyWrite() async throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let url = dir.appendingPathComponent("training.json")
  let bytes = Data("{\"format\":\"com.codex.training-ledger\",\"schemaVersion\":99}".utf8)
  try bytes.write(to: url)
  let repo = TrainingRepository(url: url)
  await #expect(throws: TrainingError.self) { try await repo.load() }
  #expect(try Data(contentsOf: url) == bytes)
  try FileManager.default.removeItem(at: dir)
}
@Test func importPreservesLocalRealNameFavoriteAndNewerVerdict() throws {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let p = Person(name: "昵称", favorite: true, accounts: [a], realName: "本机测试姓名")
  let r = record(account: a.id)
  let local = TrainingArchive(people: [p], submissions: [r])
  var incoming = local
  incoming.people[0].realName = "旧备份姓名"
  incoming.people[0].favorite = false
  incoming.submissions[0].accepted = false
  incoming.submissions[0].verdict = "WA"
  incoming.submissions[0].difficulty = Difficulty(value: 1500, label: "1500", source: "CF")
  let merged = try TrainingRepository.importArchive(
    TrainingRepository.encoder.encode(incoming), into: local)
  #expect(merged.people[0].realName == "本机测试姓名")
  #expect(merged.people[0].favorite)
  #expect(merged.submissions[0].accepted)
  #expect(merged.submissions[0].difficulty?.value == 1500)
  incoming.people[0].accounts[0].handle = "other"
  #expect(throws: TrainingError.self) {
    try TrainingRepository.importArchive(TrainingRepository.encoder.encode(incoming), into: local)
  }
}
@Test func indexedAndCachedSummaryMatchesUnindexedResults() throws {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let b = OJAccount(oj: .atcoder, handle: "v")
  let p = Person(name: "A", accounts: [a, b])
  var rb = record(account: b.id, id: "2", time: "2026-10-21 12:00:00")
  rb.problemURL = "https://atcoder.jp/contests"
  let records = [record(account: a.id, id: "1"), rb]
  let archive = TrainingArchive(people: [p], submissions: records)
  let index = TrainingIndex(archive)
  let ids = Set([a.id, b.id])
  #expect(index.rows(for: ids) == TrainingAnalysis.rows(records, accounts: ids))
  let summary = TrainingSummary(rows: index.rows(for: ids), accounts: [a, b])
  #expect(summary.stats == TrainingAnalysis.stats(records, accounts: [a, b]))
  #expect(summary.rowsByDay.count == 2)
  #expect(index.ownersByAccount[b.id]?.id == p.id)
}
@Test func recordSearchSupportsIdentityAliasesDatesAndAccepted() throws {
  let a = OJAccount(oj: .codeforces, handle: "u")
  let good = record(account: a.id, id: "1")
  let bad = record(account: a.id, id: "2", time: "2026-10-21 12:00:00", accepted: false)
  let aliases = [a.id: "测试真名 某平台ID 某昵称"]
  #expect(
    try TrainingSearch.filter([good, bad], query: "测试真名", accountAliases: aliases).count == 2)
  #expect(
    try TrainingSearch.filter(
      [good, bad], query: "某平台id", onlyAccepted: true, accountAliases: aliases
    ).map(\.id) == [good.id])
  #expect(
    try TrainingSearch.filter([good, bad], query: "", day: TrainingDates.day(good.timestamp)).map(
      \.id) == [good.id])
  #expect(try TrainingSearch.filter([good, bad], query: "不存在").isEmpty)
}
@Test func paletteTextContrastInBothAppearances() {
  for oj in OJ.allCases {
    let t = TrainingPalette.source(oj)
    let lightBackground = TrainingPalette.blend(t.light, onto: 0xFFFFFF, opacity: 0.09)
    let darkBackground = TrainingPalette.blend(t.dark, onto: 0x1C1C1E, opacity: 0.09)
    #expect(TrainingPalette.contrast(t.light, lightBackground) >= 4.5, "\(oj.name)浅色标签")
    #expect(TrainingPalette.contrast(t.dark, darkBackground) >= 4.5, "\(oj.name)深色标签")
  }
  for t in [
    TrainingPalette.secondary, TrainingPalette.success, TrainingPalette.warning,
    TrainingPalette.favorite,
  ] {
    #expect(TrainingPalette.contrast(t.light, 0xFFFFFF) >= 4.5)
    #expect(TrainingPalette.contrast(t.dark, 0x1C1C1E) >= 4.5)
  }
  #expect(TrainingPalette.contrast(TrainingPalette.accent.light, 0xFFFFFF) >= 4.5)
  #expect(TrainingPalette.contrast(TrainingPalette.accent.dark, 0x14224D) >= 4.5)
}
