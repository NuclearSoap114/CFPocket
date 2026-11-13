import Foundation

public struct TrainingIndex: Sendable {
  public let people: [Person]
  public let accounts: [OJAccount]
  public let peopleByID: [UUID: Person]
  public let accountsByID: [UUID: OJAccount]
  public let ownersByAccount: [UUID: Person]
  public let rowsByAccount: [UUID: [Submission]]
  public let syncByAccount: [UUID: SyncInfo]
  public init(_ archive: TrainingArchive, retainingRows: [UUID: [Submission]]? = nil) {
    people = TrainingAnalysis.sortedPeople(archive.people)
    accounts = people.flatMap(\.accounts)
    peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
    accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    ownersByAccount = Dictionary(
      uniqueKeysWithValues: people.flatMap { p in p.accounts.map { ($0.id, p) } })
    syncByAccount = Dictionary(uniqueKeysWithValues: archive.sync.map { ($0.accountID, $0) })
    if let retainingRows {
      rowsByAccount = retainingRows
      return
    }
    let sorted = archive.submissions.sorted {
      if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
      return $0.id > $1.id
    }
    rowsByAccount = Dictionary(grouping: sorted, by: \.accountID)
  }
  public func rows(for ids: Set<UUID>) -> [Submission] {
    if ids.count == 1, let id = ids.first { return rowsByAccount[id] ?? [] }
    return ids.flatMap { rowsByAccount[$0] ?? [] }.sorted {
      if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
      return $0.id > $1.id
    }
  }
}
public struct TrainingSummary: Sendable {
  public let rows: [Submission]
  public let days: [TrainingDay]
  public let stats: TrainingStats
  public let years: [Int]
  public let rowsByDay: [Date: [Submission]]
  public init(rows: [Submission], accounts: [OJAccount], now: Date = Date()) {
    self.rows = rows
    days = TrainingAnalysis.days(rows, accounts: accounts)
    stats = TrainingAnalysis.stats(rows, accounts: accounts, now: now, precomputedDays: days)
    years = Array(
      Set(
        days.map { TrainingDates.calendar.component(.year, from: $0.date) } + [
          TrainingDates.calendar.component(.year, from: now)
        ])
    ).sorted(by: >)
    rowsByDay = Dictionary(grouping: rows, by: { TrainingDates.day($0.timestamp) })
  }
}
