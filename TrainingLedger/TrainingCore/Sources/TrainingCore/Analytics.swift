import Foundation

public enum HeatMetric: String, CaseIterable, Identifiable, Sendable {
  case submissions = "提交次数"
  case solved = "通过题数"
  public var id: String { rawValue }
}
public struct TrainingDay: Identifiable, Equatable, Sendable {
  public var date: Date
  public var submissions: Int
  public var acceptedSubmissions: Int
  public var solved: Int
  public var hardest: Difficulty?
  public var id: Date { date }
  public func count(_ metric: HeatMetric) -> Int { metric == .submissions ? submissions : solved }
}
public struct TrainingStats: Equatable, Sendable {
  public var submissions: Int
  public var accepted: Int
  public var uniqueSolved: Int
  public var activeDays: Int
  public var currentStreak: Int
  public var longestStreak: Int
  public var lastSubmission: Date?
}
public enum TrainingAnalysis {
  public static func sortedPeople(_ people: [Person]) -> [Person] {
    people.sorted {
      if $0.favorite != $1.favorite { return $0.favorite }
      return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }
  public static func rows(
    _ all: [Submission], accounts: Set<UUID>, from: Date? = nil, to: Date? = nil
  ) -> [Submission] {
    all.filter {
      accounts.contains($0.accountID) && (from == nil || $0.timestamp >= from!)
        && (to == nil || $0.timestamp < to!)
    }.sorted {
      if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
      return $0.id > $1.id
    }
  }
  public static func days(_ rows: [Submission], accounts: [OJAccount]) -> [TrainingDay] {
    let identities = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.problemNamespace) })
    return Dictionary(grouping: rows, by: { TrainingDates.day($0.timestamp) }).map { date, rs in
      let passed = rs.filter(\.accepted)
      // A problem is unique within its OJ/site, even across multiple handles of one person.
      let solved = Set(
        passed.map { "\(identities[$0.accountID] ?? $0.accountID.uuidString)|\($0.problemID)" }
      ).count
      let hardest = passed.compactMap(\.difficulty).max { ($0.value ?? -1) < ($1.value ?? -1) }
      return TrainingDay(
        date: date, submissions: rs.count, acceptedSubmissions: passed.count, solved: solved,
        hardest: hardest)
    }.sorted { $0.date < $1.date }
  }
  public static func stats(
    _ rows: [Submission], accounts: [OJAccount], now: Date = Date(),
    precomputedDays: [TrainingDay]? = nil
  )
    -> TrainingStats
  {
    let days = precomputedDays ?? days(rows, accounts: accounts)
    let dates = Set(days.map(\.date))
    let c = TrainingDates.calendar
    let today = TrainingDates.day(now)
    var current = 0
    var cursor = dates.contains(today) ? today : c.date(byAdding: .day, value: -1, to: today)!
    while dates.contains(cursor) {
      current += 1
      cursor = c.date(byAdding: .day, value: -1, to: cursor)!
    }
    var longest = 0
    var streak = 0
    var previous: Date?
    for d in days {
      streak =
        previous.flatMap { c.dateComponents([.day], from: $0, to: d.date).day } == 1
        ? streak + 1 : 1
      longest = max(longest, streak)
      previous = d.date
    }
    let identities = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.problemNamespace) })
    return TrainingStats(
      submissions: rows.count, accepted: rows.filter(\.accepted).count,
      uniqueSolved: Set(
        rows.filter(\.accepted).map {
          "\(identities[$0.accountID] ?? $0.accountID.uuidString)|\($0.problemID)"
        }
      ).count, activeDays: days.count, currentStreak: current, longestStreak: longest,
      lastSubmission: rows.map(\.timestamp).max())
  }
  public static func yearDates(_ year: Int) -> [Date] {
    let c = TrainingDates.calendar
    let start = c.date(from: DateComponents(year: year, month: 1, day: 1))!
    let end = c.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
    var result: [Date] = []
    var d = start
    while d < end {
      result.append(d)
      d = c.date(byAdding: .day, value: 1, to: d)!
    }
    return result
  }
  public static func merge(
    _ old: [Submission], _ incoming: [Submission], preferIncoming: Bool = true
  ) throws -> [Submission] {
    var result = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
    for var r in incoming {
      try r.validate()
      if let previous = result[r.id] {
        guard previous.problemID == r.problemID,
          abs(previous.timestamp.timeIntervalSince(r.timestamp)) < 1
        else { throw TrainingError.invalid("提交ID冲突，题号或提交时间不同：\(r.recordID)") }
        if !preferIncoming {
          var kept = previous
          if kept.difficulty == nil { kept.difficulty = r.difficulty }
          if kept.title == kept.problemID && r.title != r.problemID { kept.title = r.title }
          kept.extraFields = r.extraFields.merging(kept.extraFields) { _, local in local }
          result[r.id] = kept
          continue
        }
        if r.difficulty == nil { r.difficulty = previous.difficulty }
        r.extraFields = previous.extraFields.merging(r.extraFields) { _, fresh in fresh }
      }
      result[r.id] = r
    }
    return result.values.sorted {
      if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
      return $0.id > $1.id
    }
  }
}
