import SwiftUI
import Charts
import TrainingCore

struct StatisticsHome: View {
  @Environment(TrainingStore.self) private var store
  @AppStorage("CFPocket.primaryPerson") private var primaryKey = ""
  @State private var personID: UUID?
  @State private var showEveryone = true
  @State private var period: InsightPeriod = .month
  @State private var report: TrainingInsights?
  @State private var busy = false
  @State private var heatDay: Date?
  @State private var year = TrainingDates.calendar.component(.year, from: Date())
  private var person: Person? { store.people.first { $0.id == personID } ?? store.people.first { $0.id.uuidString == primaryKey } }
  private var accounts: [OJAccount] { showEveryone ? store.accounts : person?.accounts ?? [] }
  private var ids: Set<UUID> { Set(accounts.map(\.id)) }
  private var queryKey: String { store.queryGeneration + ids.map(\.uuidString).sorted().joined() + period.rawValue }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        StatisticsScope(person: person, people: store.people, everyone: $showEveryone, selected: $personID)
        ProgressBanner()
        Picker("统计时间", selection: $period) { ForEach(InsightPeriod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
        if busy { ProgressView("正在整理记录…").font(.caption) }
        if let report {
          StatisticsHeadline(report: report)
          if report.submissions > 0 {
            SubmissionTrendCard(report: report)
            CumulativeSolvedCard(report: report)
          } else {
            ContentUnavailableView("这段时间还没有记录", systemImage: "chart.xyaxis.line", description: Text("切换时间范围，或在“我的”绑定账号并同步。未采集到记录不代表没有训练。"))
          }
        }
        let cf = accounts.filter { $0.oj == .codeforces }
        if !cf.isEmpty {
          PocketSectionTitle(title: "Codeforces 足迹", subtitle: "色相代表难度，深浅代表数量")
          CFHeatmapOverview(accounts: cf, day: $heatDay, year: $year)
        }
        PocketSectionTitle(title: "训练分析")
        VStack(spacing: 0) {
          NavigationLink { TrainingInsightsPage(personID: showEveryone ? nil : person?.id, period: period) } label: {
            PocketDestinationLabel(title: "完整统计", detail: "通过比例、平台分布与一周节奏", symbol: "chart.bar.xaxis")
          }.buttonStyle(.plain).padding(.vertical, 8)
          Divider().padding(.leading, 58)
          NavigationLink { PlatformsPage().navigationTitle("各平台训练") } label: {
            PocketDestinationLabel(title: "各平台训练", detail: "CF · AtCoder · 洛谷 · 牛客 · QOJ · Hydro · VJudge", symbol: "square.stack.3d.up.fill", color: .teal)
          }.buttonStyle(.plain).padding(.vertical, 8)
        }.pocketSurface()
        Text("统计来源为实际采集或导入的 OJ 记录。本地样例运行单独保存在练习中，不计为平台 AC。").font(.caption).foregroundStyle(.secondary)
      }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
    }.background(PocketStyle.canvas).navigationTitle("统计")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncButton(ids: ids) } }
      .refreshable { store.refresh(accountIDs: ids) }
      .task(id: queryKey) {
        busy = true
        let rows = store.rows(accountIDs: ids), selection = accounts, interval = period
        let value = await Task.detached(priority: .userInitiated) { TrainingInsights(rows: rows, accounts: selection, period: interval) }.value
        guard !Task.isCancelled else { return }; report = value; busy = false
      }
  }
}
struct StatisticsScope: View {
  let person: Person?; let people: [Person]
  @Binding var everyone: Bool
  @Binding var selected: UUID?
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
    layout {
      Menu {
        Button("全部人物") { everyone = true }
        ForEach(people) { person in Button(person.displayName) { selected = person.id; everyone = false } }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: everyone ? "person.2.fill" : "person.crop.circle.fill")
          Text(everyone ? "全部人物" : person?.displayName ?? "我的训练").fixedSize(horizontal: false, vertical: true)
          Image(systemName: "chevron.down").font(.caption2.bold())
        }.font(.headline).frame(minHeight: 44)
      }.layoutPriority(1)
      if !typeSize.isAccessibilitySize { Spacer() }
      Text("已采集记录").font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct StatisticsHeadline: View {
  let report: TrainingInsights
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text("已通过题目").font(.subheadline).foregroundStyle(.white.opacity(0.75))
          Text(report.solved.formatted()).font(.system(size: 48, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(PocketStyle.heroAccent)
        }
        Spacer()
        Image(systemName: "chart.xyaxis.line").font(.system(size: 34, weight: .light)).foregroundStyle(.white.opacity(0.4)).padding(.top, 12).accessibilityHidden(true)
      }
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
      layout {
        statistic(report.submissions, "提交次数")
        statistic(report.activeDays, "活跃天数")
        statistic(report.newlySolved, "首次通过")
      }
      Divider().overlay(.white.opacity(0.15))
      Text("\(TrainingDates.text(report.start, format: "M月d日")) — \(TrainingDates.text(report.end.addingTimeInterval(-1), format: "M月d日")) · 按平台去重")
        .font(.caption).foregroundStyle(.white.opacity(0.7))
    }.padding(24).background(PocketStyle.hero, in: RoundedRectangle(cornerRadius: 26))
  }
  func statistic(_ value: Int, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 6) { Text(value.formatted()).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.white); Text(label).font(.caption).foregroundStyle(.white.opacity(0.7)) }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
  }
}

struct CFHeatmapOverview: View {
  @Environment(TrainingStore.self) private var store
  let accounts: [OJAccount]
  @Binding var day: Date?
  @Binding var year: Int
  var body: some View {
    let summary = store.summary(accountIDs: Set(accounts.map(\.id)))
    VStack(alignment: .leading, spacing: 12) {
      YearMenu(years: summary.years, year: $year)
      TrainingHeatmap(days: summary.days.filter { TrainingDates.calendar.component(.year, from: $0.date) == year }, year: year, metric: .submissions, selected: $day, ratingColors: true, framed: false, showsHeading: false)
      if let day {
        NavigationLink { AllSubmissionsPage(accountIDs: Set(accounts.map(\.id)), showPerson: true, day: day) } label: {
          Label("\(TrainingDates.text(day, format: "M月d日")) · 查看当天提交", systemImage: "arrow.up.right")
        }.font(.subheadline).frame(minHeight: 44)
      }
      NavigationLink { PlatformTrainingPage(oj: .codeforces) } label: { Label("按难度查看 CF 题目", systemImage: "chart.bar.doc.horizontal") }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
    }.pocketSurface().onChange(of: year) { _, _ in day = nil }
  }
}
