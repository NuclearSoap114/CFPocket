import Foundation
import Testing
@testable import TrainingCore

private func attempt(_ account: OJAccount, _ id: String, _ problem: String,
  _ time: String, ac: Bool = true, rating: Int? = nil) -> Submission {
  Submission(accountID: account.id, recordID: id, timestamp: TrainingDates.parse(time)!,
    problemID: problem, title: "测试题 " + problem, problemURL: "https://\(account.oj.host)/problem/\(problem)",
    verdict: ac ? "OK" : "WRONG_ANSWER", accepted: ac,
    difficulty: rating.map { Difficulty(value: $0, label: String($0), source: "测试rating") })
}
@Test func insightWindowUsesShanghaiAndDistinctProblems() {
  let a = OJAccount(oj: .codeforces, handle: "test")
  let b = OJAccount(oj: .codeforces, handle: "test2")
  let rows = [
    attempt(a,"1","A","2026-10-01T00:00:00Z"),
    attempt(a,"2","A","2026-10-26T15:59:59Z"),
    attempt(b,"3","A","2026-10-26T16:00:00Z"),
    attempt(a,"4","B","2026-10-27T01:00:00Z",ac:false),
    attempt(a,"5","B","2026-10-27T02:00:00Z")]
  let report = TrainingInsights(rows: rows, accounts:[a,b], period:.week,
    now:TrainingDates.parse("2026-10-27 20:00:00")!)
  #expect(report.submissions == 4)
  #expect(report.accepted == 3)
  #expect(report.solved == 2)
  #expect(report.newlySolved == 1)
  #expect(report.activeDays == 2)
  #expect(report.points.last?.submissions == 3)
  #expect(report.points.last?.cumulativeSolved == 2)
  #expect(report.points.first?.cumulativeSolved == 1)
  #expect(report.weekdays[1].submissions == 3) // Tuesday
  #expect(report.acFraction == 0.75)
}
@Test func insightPlatformCountsDoNotMixOJNamespaces() {
  let cf = OJAccount(oj:.codeforces,handle:"a"), at = OJAccount(oj:.atcoder,handle:"b")
  let rows = [attempt(cf,"1","A","2026-10-20 12:00:00"),attempt(at,"2","A","2026-10-20 12:00:00")]
  let r = TrainingInsights(rows:rows,accounts:[cf,at],period:.all,now:TrainingDates.parse("2026-10-20 13:00:00")!)
  #expect(r.solved == 2)
  #expect(r.platforms.count == 2)
  #expect(r.points.count == 1)
  #expect(r.points[0].cumulativeSolved == 2)
}
@Test func emptyAndOutOfWindowInsightsRemainHonest() {
  let a = OJAccount(oj:.codeforces,handle:"a"), now = TrainingDates.parse("2026-10-27 12:00:00")!
  let empty = TrainingInsights(rows:[],accounts:[a],period:.month,now:now)
  #expect(empty.acFraction == nil)
  #expect(empty.platforms.isEmpty)
  #expect(empty.points.count == 1)
  let r = TrainingInsights(rows:[attempt(a,"1","A","2026-01-01 12:00:00")],accounts:[a],period:.week,now:now)
  #expect(r.submissions == 0)
  #expect(r.points.count == 7)
  #expect(r.points.allSatisfy { $0.cumulativeSolved == 1 })
  #expect(r.weekdays.allSatisfy { $0.submissions == 0 })
}
@Test func longHistoryUsesBoundedAggregationAndPreservesTotals() {
  let a = OJAccount(oj:.codeforces,handle:"a")
  let rows = [attempt(a,"1","A","2020-01-01 10:00:00"),attempt(a,"2","B","2026-10-27 10:00:00")]
  let r = TrainingInsights(rows:rows,accounts:[a],period:.all,now:TrainingDates.parse("2026-10-27 12:00:00")!)
  #expect(r.bucketLabel == "每月汇总")
  #expect(r.points.count < 100)
  #expect(r.points.reduce(0) { $0 + $1.submissions } == 2)
  #expect(r.points.last?.cumulativeSolved == 2)
  #expect(r.points.last!.end == r.end)
}
@Test func cfProblemsDeduplicateAttemptsAndKeepLatestKnownRating() {
  let a = OJAccount(oj:.codeforces,handle:"a"), b = OJAccount(oj:.codeforces,handle:"b")
  let at = OJAccount(oj:.atcoder,handle:"a")
  let rows = [attempt(a,"1","A","2026-10-20 12:00:00",ac:false,rating:1900),
    attempt(b,"2","A","2026-10-21 12:00:00",rating:1800),
    attempt(a,"3","A","2026-10-22 12:00:00"),
    attempt(at,"4","A","2026-10-22 12:00:00",rating:900)]
  let result = CFPractice.problems(rows:rows,accounts:[a,b,at])
  #expect(result.count == 1)
  #expect(result[0].rows.count == 3)
  #expect(result[0].accepted)
  #expect(result[0].rating == 1800) // latest nonmissing value, not maximum value
  #expect(result[0].rows[0].recordID == "3")
}
@Test func cfSortingFilteringAndUnratedAreIndependent() {
  let a = OJAccount(oj:.codeforces,handle:"a")
  let p = CFPractice.problems(rows:[attempt(a,"1","A","2026-10-20 12:00:00",rating:800),
    attempt(a,"2","B","2026-10-21 12:00:00",ac:false,rating:2400),
    attempt(a,"3","C","2026-10-22 12:00:00")],accounts:[a])
  #expect(CFPractice.filter(p).map(\.problemID) == ["A","B","C"])
  #expect(CFPractice.filter(p,order:.descending).map(\.problemID) == ["B","A","C"])
  #expect(CFPractice.filter(p,order:.latest).map(\.problemID) == ["C","B","A"])
  #expect(CFPractice.filter(p,band:.unrated).map(\.problemID) == ["C"])
  #expect(CFPractice.filter(p,status:.attempted).map(\.problemID) == ["B"])
  let d = CFPractice.distribution(p)
  #expect(d.reduce(0) { $0 + $1.total } == 3)
  #expect(d.first { $0.band == .unrated }?.accepted == 1)
  #expect(d.first { $0.band == .expert }?.attempted == 1)
}
@Test func cfBandBoundariesDoNotImplyOfficialUserRanks() {
  #expect(CFRatingBand.band(nil) == .unrated)
  #expect(CFRatingBand.band(0) == .unrated)
  #expect(CFRatingBand.band(1100) == .foundation)
  #expect(CFRatingBand.band(1200) == .developing)
  #expect(CFRatingBand.band(1600) == .advanced)
  #expect(CFRatingBand.band(2000) == .challenging)
  #expect(CFRatingBand.band(2400) == .expert)
}
@Test func difficultyHeatmapUsesHighestAcceptedRatingNotFailedAttempt() {
  let a = OJAccount(oj:.codeforces,handle:"a")
  let rows = [attempt(a,"1","A","2026-10-20 12:00:00",rating:800),
    attempt(a,"2","B","2026-10-20 13:00:00",rating:1900),
    attempt(a,"3","B","2026-10-20 14:00:00",rating:1900),
    attempt(a,"4","C","2026-10-20 15:00:00",ac:false,rating:3500),
    attempt(a,"5","D","2026-10-21 12:00:00",ac:false,rating:2400),
    attempt(a,"6","E","2026-10-22 12:00:00")]
  let days = TrainingAnalysis.days(rows,accounts:[a])
  #expect(days[0].submissions == 4)
  #expect(days[0].solved == 2)
  #expect(days[0].hardest?.value == 1900)
  #expect(days[1].hardest == nil)
  #expect(days[2].hardest == nil)
}
@Test func monthlyInsightsAlignToCalendarBoundaries() {
  let a = OJAccount(oj:.codeforces,handle:"a")
  let rows = [attempt(a,"1","A","2020-01-31 10:00:00"),
    attempt(a,"2","B","2020-02-01 00:00:00"),
    attempt(a,"3","C","2026-10-28 12:00:00")]
  let r = TrainingInsights(rows:rows,accounts:[a],period:.all,now:TrainingDates.parse("2026-10-28 13:00:00")!)
  #expect(r.points[0].submissions == 1)
  #expect(r.points[0].end == TrainingDates.parse("2020-02-01 00:00:00"))
  #expect(r.points[1].submissions == 1)
  #expect(r.points.reduce(0) { $0 + $1.submissions } == 3)
  #expect(r.points.last?.cumulativeSolved == 3)
}
