import Foundation
import TrainingCore

@main struct TrainingBench {
    private static func makeIndex(_ archive: TrainingArchive) -> (TrainingIndex, Bool) {
        (TrainingIndex(archive), !Thread.isMainThread)
    }
    static func main()async throws {
        let count=Int(CommandLine.arguments.dropFirst().first ?? "50000") ?? 50000
        var people:[Person]=[],accounts:[OJAccount]=[]
        for p in 0..<10 {let bindings=OJ.allCases.map{OJAccount(oj:$0,handle:$0 == .luogu || $0 == .nowcoder ? String(10000+p):"benchmark-\(p)")};accounts+=bindings;people.append(Person(name:"仅用于基准\(p)",accounts:bindings))}
        let now=Date(),base=now.addingTimeInterval(-Double(count)*60)
        let records=(0..<count).map{i in let a=accounts[i%accounts.count];return Submission(accountID:a.id,recordID:"BENCH-\(i)",timestamp:base.addingTimeInterval(Double(i)*60),problemID:"P\(i%1000)",title:"仅用于本地性能基准题目\(i)",problemURL:"https://\(a.oj.host)/",verdict:i%3==0 ? "WA":"AC",accepted:i%3 != 0)}
        let archive=TrainingArchive(people:people,submissions:records),ids=Set(people[0].accounts.map(\.id)),clock=ContinuousClock()
        var oldCount=0,newCount=0
        let before=clock.now
        for _ in 0..<20 {let rows=TrainingAnalysis.rows(records,accounts:ids);let stats=TrainingAnalysis.stats(rows,accounts:people[0].accounts);oldCount+=stats.submissions}
        let oldTime=before.duration(to:clock.now)
        let indexStart=clock.now
        let (index,offMain)=await Task.detached{makeIndex(archive)}.value
        let indexTime=indexStart.duration(to:clock.now)
        let summaryStart=clock.now,summary=TrainingSummary(rows:index.rows(for:ids),accounts:people[0].accounts)
        let summaryTime=summaryStart.duration(to:clock.now)
        let cache=["selection":summary],cachedStart=clock.now
        for _ in 0..<20 {newCount+=cache["selection"]!.stats.submissions}
        let cachedTime=cachedStart.duration(to:clock.now)
        let searchStart=clock.now
        let searched=try await Task.detached{try TrainingSearch.filter(index.rows(for:ids),query:"题目123")}.value
        let searchTime=searchStart.duration(to:clock.now)
        let selectedAccounts=people[0].accounts,selectedRows=summary.rows
        let insightStart=clock.now
        let insights=await Task.detached{TrainingInsights(rows:selectedRows,accounts:selectedAccounts,period:.all,now:now)}.value
        let insightTime=insightStart.duration(to:clock.now)
        let difficultyStart=clock.now
        let problems=await Task.detached{CFPractice.problems(rows:selectedRows,accounts:selectedAccounts)}.value
        let difficultyTime=difficultyStart.duration(to:clock.now)
        print("BENCHMARK_SYNTHETIC_NOT_APP_HISTORY")
        print("records=\(count),people=\(people.count),accounts=\(accounts.count),selectedRecords=\(summary.rows.count)")
        print("baseline20RepeatedSortAndStats=\(oldTime)")
        print("buildIndex=\(indexTime),indexOffMain=\(offMain)")
        print("firstSummary=\(summaryTime),cached20Queries=\(cachedTime)")
        print("backgroundSearch=\(searchTime),matches=\(searched.count)")
        print("insightAggregation=\(insightTime),buckets=\(insights.points.count)")
        print("cfDifficultyAggregation=\(difficultyTime),problems=\(problems.count)")
        print("checksum=\(oldCount)==\(newCount)")
        guard oldCount==newCount,offMain else{throw TrainingError.invalid("基准结果不一致")}
        guard insights.submissions==summary.stats.submissions,
              insights.points.last?.cumulativeSolved==summary.stats.uniqueSolved else{throw TrainingError.invalid("图表统计与原有口径不一致")}
    }
}
