import Foundation

public enum InsightPeriod: String, CaseIterable, Identifiable, Sendable {
  case week = "7天", month = "30天", quarter = "90天", all = "全部"
  public var id: String { rawValue }
  public var days: Int? {
    switch self { case .week: 7; case .month: 30; case .quarter: 90; case .all: nil }
  }
}

public struct InsightPoint: Identifiable, Sendable {
  public let date: Date
  public let end: Date
  public let submissions: Int
  public let accepted: Int
  public let firstSolved: Int
  public let cumulativeSolved: Int
  public var id: Date { date }
}
public struct PlatformContribution: Identifiable, Sendable {
  public let oj: OJ
  public let submissions: Int
  public let solved: Int
  public var id: OJ { oj }
}
public struct WeekdayActivity: Identifiable, Sendable {
  public let day: Int // Monday = 0, Shanghai time
  public let submissions: Int
  public var id: Int { day }
  public var label: String { ["一", "二", "三", "四", "五", "六", "日"][day] }
}

/// Derived only from acquired submissions. No predicted history or synthetic user data.
public struct TrainingInsights: Sendable {
  public let period: InsightPeriod
  public let start: Date
  public let end: Date
  public let points: [InsightPoint]
  public let bucketLabel: String
  public let submissions: Int
  public let accepted: Int
  public let solved: Int
  public let newlySolved: Int
  public let activeDays: Int
  public let platforms: [PlatformContribution]
  public let weekdays: [WeekdayActivity]
  public var acFraction: Double? { submissions == 0 ? nil : Double(accepted) / Double(submissions) }

  public init(rows: [Submission], accounts: [OJAccount], period: InsightPeriod, now: Date = Date()) {
    self.period = period
    let c = TrainingDates.calendar, today = TrainingDates.day(now)
    let endDate = c.date(byAdding: .day, value: 1, to: today)!
    end = endDate
    let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    let source = rows.filter { accountMap[$0.accountID] != nil && $0.timestamp < endDate }
    let earliest = source.map(\.timestamp).min().map(TrainingDates.day) ?? today
    let requested = period.days.map { c.date(byAdding: .day, value: 1 - $0, to: today)! } ?? earliest
    let startDate = max(requested, earliest)
    start = startDate
    let selected = source.filter { $0.timestamp >= startDate }
    submissions = selected.count
    accepted = selected.filter(\.accepted).count
    activeDays = Set(selected.map { TrainingDates.day($0.timestamp) }).count
    func key(_ r: Submission) -> String { "\(accountMap[r.accountID]!.problemNamespace)|\(r.problemID)" }
    solved = Set(selected.filter(\.accepted).map(key)).count
    var firstAC: [String: Date] = [:]
    for r in source where r.accepted {
      let id = key(r)
      firstAC[id] = min(firstAC[id] ?? r.timestamp, r.timestamp)
    }
    newlySolved = firstAC.values.filter { $0 >= startDate }.count
    let span = c.dateComponents([.day], from: startDate, to: endDate).day ?? 1
    let step = span <= 90 ? 1 : span <= 730 ? 7 : 0
    bucketLabel = step == 1 ? "每日" : step == 7 ? "每7日汇总" : "每月汇总"
    var ranges: [(Date, Date)] = [], cursor = startDate
    while cursor < endDate {
      let next = min(endDate, step > 0 ? c.date(byAdding: .day, value: step, to: cursor)!
        : c.dateInterval(of: .month, for: cursor)!.end)
      ranges.append((cursor, next)); cursor = next
    }
    // Binary search keeps long histories O(records log buckets), without per-day full scans.
    func bucket(_ date: Date) -> Int {
      var lo = 0, hi = ranges.count
      while lo < hi { let mid = (lo + hi) / 2; if ranges[mid].0 <= date { lo = mid + 1 } else { hi = mid } }
      return max(0, lo - 1)
    }
    var totals = Array(repeating: 0, count: ranges.count), passed = totals, firsts = totals
    for r in selected { let i = bucket(r.timestamp); totals[i] += 1; if r.accepted { passed[i] += 1 } }
    var accumulated = firstAC.values.filter { $0 < startDate }.count
    for date in firstAC.values where date >= startDate { firsts[bucket(date)] += 1 }
    points = ranges.enumerated().map { i, range in
      accumulated += firsts[i]
      return InsightPoint(date: range.0, end: range.1, submissions: totals[i], accepted: passed[i],
        firstSolved: firsts[i], cumulativeSolved: accumulated)
    }
    platforms = OJ.allCases.compactMap { oj in
      let subset = selected.filter { accountMap[$0.accountID]?.oj == oj }
      guard !subset.isEmpty else { return nil }
      return PlatformContribution(oj: oj, submissions: subset.count,
        solved: Set(subset.filter(\.accepted).map(key)).count)
    }.sorted { $0.submissions == $1.submissions ? $0.oj.rawValue < $1.oj.rawValue : $0.submissions > $1.submissions }
    var week = Array(repeating: 0, count: 7)
    for r in selected { week[(c.component(.weekday, from: r.timestamp) + 5) % 7] += 1 }
    weekdays = (0..<7).map { WeekdayActivity(day: $0, submissions: week[$0]) }
  }
}

public enum CFRatingBand: Int, CaseIterable, Identifiable, Sendable {
  case foundation, developing, advanced, challenging, expert, unrated
  public var id: Int { rawValue }
  public var label: String {
    switch self {
    case .foundation: "<1200"; case .developing: "1200–1599"; case .advanced: "1600–1999"
    case .challenging: "2000–2399"; case .expert: "≥2400"; case .unrated: "暂无rating"
    }
  }
  public static func band(_ rating: Int?) -> Self {
    guard let rating, rating > 0 else { return .unrated }
    switch rating { case ..<1200: return .foundation; case ..<1600: return .developing
    case ..<2000: return .advanced; case ..<2400: return .challenging; default: return .expert }
  }
}
public enum CFProblemStatus: String, CaseIterable, Identifiable, Sendable {
  case all = "全部状态", accepted = "已采集AC", attempted = "暂无AC"
  public var id: String { rawValue }
}
public enum CFProblemOrder: String, CaseIterable, Identifiable, Sendable {
  case ascending = "难度低到高", descending = "难度高到低", latest = "最近提交"
  public var id: String { rawValue }
}
public struct CFPracticeProblem: Identifiable, Sendable {
  public let id: String
  public let problemID: String
  public let title: String
  public let url: String
  public let rating: Int?
  public let rows: [Submission]
  public let accepted: Bool
  public var band: CFRatingBand { .band(rating) }
  public var lastAttempt: Date { rows[0].timestamp }
}
public struct CFRatingCount: Identifiable, Sendable {
  public let band: CFRatingBand
  public let accepted: Int
  public let attempted: Int
  public var total: Int { accepted + attempted }
  public var id: Int { band.id }
}
public enum CFPractice {
  public static func problems(rows: [Submission], accounts: [OJAccount]) -> [CFPracticeProblem] {
    let map = Dictionary(uniqueKeysWithValues: accounts.filter { $0.oj == .codeforces }.map { ($0.id, $0) })
    let filtered = rows.filter { map[$0.accountID] != nil }
    let grouped = Dictionary(grouping: filtered) { "\(map[$0.accountID]!.problemNamespace)|\($0.problemID)" }
    return grouped.map { key, records in
      let sorted = records.sorted { $0.timestamp == $1.timestamp ? $0.id > $1.id : $0.timestamp > $1.timestamp }
      let latest = sorted[0]
      let rating = sorted.compactMap { $0.difficulty?.value }.first(where: { $0 > 0 })
      return CFPracticeProblem(id: key, problemID: latest.problemID, title: latest.title,
        url: latest.problemURL, rating: rating, rows: sorted, accepted: sorted.contains(where: \.accepted))
    }.sorted { $0.problemID.localizedStandardCompare($1.problemID) == .orderedAscending }
  }
  public static func distribution(_ problems: [CFPracticeProblem]) -> [CFRatingCount] {
    CFRatingBand.allCases.map { band in
      let subset = problems.filter { $0.band == band }
      return CFRatingCount(band: band, accepted: subset.filter(\.accepted).count,
        attempted: subset.filter { !$0.accepted }.count)
    }
  }
  public static func filter(_ problems: [CFPracticeProblem], band: CFRatingBand? = nil,
    status: CFProblemStatus = .all, order: CFProblemOrder = .ascending) -> [CFPracticeProblem] {
    problems.filter { p in (band == nil || p.band == band)
      && (status == .all || (status == .accepted && p.accepted) || (status == .attempted && !p.accepted))
    }.sorted { a, b in
      // Missing rating always stays separate at the end, even for descending sorting.
      if order != .latest {
        if (a.rating == nil) != (b.rating == nil) { return a.rating != nil }
        if let x = a.rating, let y = b.rating, x != y { return order == .ascending ? x < y : x > y }
      }
      if a.lastAttempt != b.lastAttempt { return a.lastAttempt > b.lastAttempt }
      return a.id < b.id
    }
  }
}
