import SwiftUI
import Charts
import TrainingCore

struct TrainingPulseCard: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  let accountIDs: Set<UUID>
  var body: some View {
    let summary = store.summary(accountIDs: accountIDs)
    let c = TrainingDates.calendar, today = TrainingDates.day(Date())
    let days = (-6...0).map { c.date(byAdding: .day, value: $0, to: today)! }
    let counts = Dictionary(uniqueKeysWithValues: summary.days.map { ($0.date, $0.submissions) })
    let count = days.reduce(0) { $0 + (counts[$1] ?? 0) }
    NavigationLink { TrainingInsightsPage(period: .week) } label: {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Label("最近的训练节奏", systemImage: "waveform.path").font(.headline)
          Spacer()
          Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
        }
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
          : AnyLayout(HStackLayout(alignment: .bottom, spacing: 20))
        layout {
          VStack(alignment: .leading, spacing: 5) {
            Text(count, format: .number).font(.system(.largeTitle, design: .rounded, weight: .bold))
              .monospacedDigit()
            Text("近7天已采集提交 · 查看统计").font(.caption).foregroundStyle(Theme.secondaryText)
          }
          if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
          Chart(days, id: \.self) { day in
            BarMark(x: .value("日期", day, unit: .day), y: .value("提交", counts[day] ?? 0), width: .ratio(0.55))
              .foregroundStyle(Theme.accent.gradient).cornerRadius(3)
          }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 96, height: 58)
            .accessibilityHidden(true)
        }
      }.foregroundStyle(.primary).trainingCard()
        .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.accent.opacity(0.12)) }
    }.buttonStyle(.plain).accessibilityHint("打开训练趋势与平台统计")
  }
}

struct TrainingInsightsPage: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var personID: UUID?
  @State private var oj: OJ?
  @State private var period: InsightPeriod
  @State private var report: TrainingInsights?
  @State private var calculating = false
  init(personID: UUID? = nil, oj: OJ? = nil, period: InsightPeriod = .month) {
    _personID = State(initialValue: personID); _oj = State(initialValue: oj); _period = State(initialValue: period)
  }
  private var accounts: [OJAccount] {
    let resolvedID = personID.flatMap { store.person($0)?.id }
    return store.people.filter { resolvedID == nil || $0.id == resolvedID }.flatMap(\.accounts).filter { oj == nil || $0.oj == oj }
  }
  private var key: String {
    store.queryGeneration + accounts.map { $0.id.uuidString }.sorted().joined()
      + period.rawValue + TrainingDates.text(Date(), format: "yyyyMMdd")
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text("训练概览").font(.title2.bold())
          Text("按人物、平台与时间，回看已采集的解题记录。").font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        filters
        if calculating { ProgressView("正在汇总已采集记录…").font(.caption) }
        if let r = report {
          Text(TrainingDates.text(r.start, format: "yyyy/M/d") + " — " + TrainingDates.text(r.end.addingTimeInterval(-1), format: "yyyy/M/d"))
            .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
          InsightMetricGrid(report: r)
          if r.submissions == 0 {
            EmptyTraining(title: "这段时间暂无已采集记录", detail: "试试更长时间或其他人物、平台。采集不完整时，零条记录不代表没有训练。")
          } else {
            SubmissionTrendCard(report: r)
            CumulativeSolvedCard(report: r)
            SubmissionOutcomeCard(total: r.submissions, accepted: r.accepted)
            PlatformContributionCard(contributions: r.platforms)
            WeekdayActivityCard(days: r.weekdays)
          }
          VStack(alignment: .leading, spacing: 7) {
            Label("统计口径", systemImage: "info.circle").font(.caption.weight(.semibold))
            Text("只使用已采集记录，按北京时间统计。通过题数按 OJ＋站点＋题号去重；新通过指在当前筛选的已采集历史中首次出现 AC。不同平台的难度不混合比较。")
              .font(.caption).foregroundStyle(Theme.secondaryText)
          }.trainingCard()
        } else if !calculating {
          EmptyTraining(title: "准备训练统计", detail: "先添加人物和平台账号，再同步训练记录。")
        }
      }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
    }.background(Theme.canvas).navigationTitle("训练统计").navigationBarTitleDisplayMode(.inline)
      .task(id: key) { await calculate() }
  }
  private var filters: some View {
    VStack(spacing: 14) {
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
      layout {
        Menu {
          Button("全部人物") { personID = nil }
          ForEach(store.people) { p in Button(p.displayName) { personID = p.id } }
        } label: { FilterMenuLabel(title: personID.flatMap { store.person($0)?.displayName } ?? "全部人物", icon: "person") }
        Menu {
          Button("全部平台") { oj = nil }
          ForEach(OJ.allCases) { source in Button(source.name) { oj = source } }
        } label: { FilterMenuLabel(title: oj?.shortName ?? "全部平台", icon: "square.grid.2x2") }
      }
      Picker("统计时间范围", selection: $period) {
        ForEach(InsightPeriod.allCases) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented)
    }
  }
  private func calculate() async {
    calculating = true
    let selected = accounts, rows = store.rows(accountIDs: Set(selected.map(\.id))), window = period
    let worker = Task.detached(priority: .userInitiated) { TrainingInsights(rows: rows, accounts: selected, period: window) }
    let value = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    guard !Task.isCancelled else { return }
    report = value; calculating = false
  }
}
struct FilterMenuLabel: View {
  let title: String
  let icon: String
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: icon).font(.caption)
      Text(title).font(.subheadline.weight(.medium)).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
      Spacer(minLength: 0)
      Image(systemName: "chevron.down").font(.caption2.weight(.bold))
    }.padding(.horizontal, 13).frame(minHeight: 44)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
  }
}
private struct InsightMetricGrid: View {
  let report: TrainingInsights
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
      metric("已采集提交", report.submissions, "次提交", "paperplane", Theme.accent)
      metric("通过题目", report.solved, "筛选内去重", "checkmark.seal", Theme.success)
      metric("新通过题目", report.newlySolved, "已采集历史首次AC", "sparkle", Theme.color(.atcoder))
      metric("活跃日期", report.activeDays, "有已采集提交", "calendar", Theme.color(.hydro))
    }
  }
  private func metric(_ title: String, _ count: Int, _ detail: String, _ icon: String, _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(tint)
      Text(count, format: .number).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
      Text(detail).font(.caption2).foregroundStyle(Theme.secondaryText)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
  }
}
struct SubmissionTrendCard: View {
  let report: TrainingInsights
  @State private var selected: Date?
  private var point: InsightPoint? { selected.flatMap { date in report.points.first { date >= $0.date && date < $0.end } } }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ChartTitle("提交节奏", subtitle: report.bucketLabel + " · AC 与其他判定")
      if let p = point {
        Text("\(insightRangeLabel(p)) · \(p.submissions) 次提交 / \(p.accepted) 次 AC")
          .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.accent)
      }
      Chart {
        ForEach(report.points) { p in
          let inset = p.end.timeIntervalSince(p.date) * 0.12
          if p.accepted > 0 {
            RectangleMark(xStart: .value("区间开始", p.date.addingTimeInterval(inset)),
              xEnd: .value("区间结束", p.end.addingTimeInterval(-inset)),
              yStart: .value("提交起点", 0), yEnd: .value("提交终点", p.accepted))
              .foregroundStyle(by: .value("判定", "AC"))
          }
          if p.submissions > p.accepted {
            RectangleMark(xStart: .value("区间开始", p.date.addingTimeInterval(inset)),
              xEnd: .value("区间结束", p.end.addingTimeInterval(-inset)),
              yStart: .value("提交起点", p.accepted), yEnd: .value("提交终点", p.submissions))
              .foregroundStyle(by: .value("判定", "其他"))
          }
        }
        if let p = point { RuleMark(x: .value("选中日期", p.date)).foregroundStyle(Theme.secondaryText.opacity(0.5)) }
      }.chartForegroundStyleScale(["AC": Theme.success, "其他": Theme.accent.opacity(0.45)])
        .chartXScale(domain: report.start...report.end)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: insightAxisFormat(report)) } }
        .chartYScale(domain: 0...max(1, report.points.map(\.submissions).max() ?? 1))
        .chartXSelection(value: $selected)
        .chartGesture { proxy in DragGesture(minimumDistance: 0).onChanged { proxy.selectXValue(at: $0.location.x) } }
        .frame(height: 200)
      ChartFootnote("轻点图表查看区间数值；没有柱子的日期表示没有已采集提交。")
    }.trainingCard().onChange(of: report.start) { _, _ in selected = nil }
  }
}
struct CumulativeSolvedCard: View {
  let report: TrainingInsights
  @State private var selected: Date?
  private var point: InsightPoint? { selected.flatMap { date in report.points.min { abs($0.end.timeIntervalSince(date)) < abs($1.end.timeIntervalSince(date)) } } }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ChartTitle("累计通过轨迹", subtitle: "按已采集的首次 AC 去重")
      if let p = point {
        Text("截至 \(TrainingDates.text(p.end.addingTimeInterval(-1),format:"yyyy/M/d")) · 累计 \(p.cumulativeSolved) 题")
          .font(.caption.weight(.semibold)).foregroundStyle(Theme.color(.atcoder))
      }
      Chart {
        ForEach(report.points) { p in
          if report.points.count > 1 {
            LineMark(x: .value("日期", p.end.addingTimeInterval(-1)), y: .value("累计通过题数", p.cumulativeSolved))
              .foregroundStyle(Theme.color(.atcoder)).interpolationMethod(.stepEnd).lineStyle(StrokeStyle(lineWidth: 2.5))
          }
          if report.points.count == 1 || p.id == point?.id || p.id == report.points.last?.id {
            PointMark(x: .value("日期", p.end.addingTimeInterval(-1)), y: .value("累计通过题数", p.cumulativeSolved))
              .foregroundStyle(Theme.color(.atcoder)).symbolSize(35)
          }
        }
      }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: insightAxisFormat(report)) } }
        .chartYScale(domain: 0...max(1, report.points.last?.cumulativeSolved ?? 1))
        .chartXSelection(value: $selected)
        .chartGesture { proxy in DragGesture(minimumDistance: 0).onChanged { proxy.selectXValue(at: $0.location.x) } }
        .frame(height: 180)
      ChartFootnote(report.points.count == 1 ? "当前只有一个时间点，不显示虚构的趋势线。" : "按各汇总区间结束时计算；包含所选时间范围之前已采集的通过题目。")
    }.trainingCard().onChange(of: report.start) { _, _ in selected = nil }
  }
}
private struct SubmissionOutcomeCard: View {
  let total: Int
  let accepted: Int
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ChartTitle("AC 提交占比", subtitle: "按提交次数计算，不等同于题目通过率")
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 24))
      layout {
        Chart {
          SectorMark(angle: .value("次数", accepted), innerRadius: .ratio(0.76), angularInset: 2).foregroundStyle(Theme.success)
          SectorMark(angle: .value("次数", total - accepted), innerRadius: .ratio(0.76), angularInset: 2).foregroundStyle(Theme.secondaryText.opacity(0.22))
        }.frame(width: 126, height: 126).chartBackground { _ in
          Text(total > 0 ? Double(accepted) / Double(total) : 0, format: .percent.precision(.fractionLength(0)))
            .font(.title3.bold()).monospacedDigit()
        }.accessibilityLabel("AC提交\(accepted)次，总提交\(total)次")
        VStack(alignment: .leading, spacing: 16) {
          Label("AC · \(accepted) 次", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
          Label("其他 · \(total - accepted) 次", systemImage: "circle.dashed").foregroundStyle(Theme.secondaryText)
        }.font(.subheadline.weight(.medium))
      }
      ChartFootnote("其他包含未通过、评测中及来源返回的其他判定。")
    }.trainingCard()
  }
}
private struct PlatformContributionCard: View {
  let contributions: [PlatformContribution]
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ChartTitle("平台分布", subtitle: "当前时间范围内的已采集提交")
      Chart(contributions) { p in
        BarMark(x: .value("提交次数", p.submissions), y: .value("平台", p.oj.shortName))
          .foregroundStyle(Theme.color(p.oj)).cornerRadius(4)
          .annotation(position: .trailing) { Text(p.submissions, format: .number).font(.caption.monospacedDigit()) }
      }.chartXScale(domain: 0...max(1, Int(Double(contributions.map(\.submissions).max() ?? 1) * 1.25)))
        .frame(height: CGFloat(max(1, contributions.count)) * 38 + 24)
    }.trainingCard()
  }
}
private struct WeekdayActivityCard: View {
  let days: [WeekdayActivity]
  @State private var selected: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ChartTitle("一周中的训练", subtitle: "按北京时间的星期累计提交次数")
      if let day = days.first(where: { $0.label == selected }) { Text("星期\(day.label) · \(day.submissions) 次").font(.caption.weight(.semibold)) }
      Chart(days) { day in
        BarMark(x: .value("星期", day.label), y: .value("提交次数", day.submissions), width: .ratio(0.5))
          .foregroundStyle(day.label == selected ? Theme.color(.hydro) : Theme.accent.opacity(0.65)).cornerRadius(4)
      }.chartXSelection(value: $selected)
        .chartGesture { proxy in DragGesture(minimumDistance: 0).onChanged { proxy.selectXValue(at: $0.location.x) } }
        .frame(height: 160)
      ChartFootnote("这是当前范围的提交总量分布；未按各星期出现的天数做平均。")
    }.trainingCard()
  }
}
struct ChartTitle: View {
  let title: String
  let subtitle: String
  init(_ title: String, subtitle: String) { self.title = title; self.subtitle = subtitle }
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.headline)
      Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
    }
  }
}
struct ChartFootnote: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View { Text(text).font(.caption2).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
}
private func insightAxisFormat(_ report: TrainingInsights) -> Date.FormatStyle {
  report.end.timeIntervalSince(report.start) > 366 * 86400 ? .dateTime.year().month() : .dateTime.month().day()
}
private func insightRangeLabel(_ point: InsightPoint) -> String {
  let first = TrainingDates.text(point.date, format: "yyyy/M/d")
  return point.end.timeIntervalSince(point.date) > 86400
    ? first + "–" + TrainingDates.text(point.end.addingTimeInterval(-1), format: "M/d") : first
}
struct TrainingAnalysisLink: View {
  var personID: UUID? = nil
  var oj: OJ? = nil
  var body: some View {
    NavigationLink { TrainingInsightsPage(personID: personID, oj: oj) } label: {
      HStack(spacing: 12) {
        Image(systemName: "chart.xyaxis.line").font(.title2).foregroundStyle(Theme.accent)
        VStack(alignment: .leading, spacing: 4) {
          Text("训练分析").font(.headline).foregroundStyle(.primary)
          Text("趋势、AC占比与训练分布").font(.caption).foregroundStyle(Theme.secondaryText)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
      }.trainingCard()
    }.buttonStyle(.plain)
  }
}
#if DEBUG
/// Reuses the production renderer with real local records, without navigation-tool dependencies.
struct SubmissionChartReview: View {
  @Environment(TrainingStore.self) private var store
  @State private var report: TrainingInsights?
  var body: some View {
    ScrollView {
      if let report {
        VStack(alignment: .leading, spacing: 18) {
          Text("全部已采集历史 · \(report.submissions) 次提交").font(.headline)
          Text(TrainingDates.text(report.start, format: "yyyy/M/d") + " — " + TrainingDates.text(report.end.addingTimeInterval(-1), format: "yyyy/M/d"))
            .font(.caption).foregroundStyle(Theme.secondaryText)
          SubmissionTrendCard(report: report)
        }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
      } else { ProgressView("正在读取本地记录") }
    }.background(Theme.canvas).navigationTitle("图表本地复核").navigationBarTitleDisplayMode(.inline)
      .task(id: store.queryGeneration) {
        let accounts = store.accounts, rows = store.rows(accountIDs: Set(store.accounts.map(\.id)))
        let value = await Task.detached { TrainingInsights(rows: rows, accounts: accounts, period: .all) }.value
        if !Task.isCancelled { report = value }
      }
  }
}
#endif
