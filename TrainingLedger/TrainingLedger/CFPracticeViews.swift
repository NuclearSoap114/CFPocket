import SwiftUI
import Charts
import TrainingCore
#if CFPOCKET
import PocketCore
#endif

extension Theme {
  static func rating(_ band: CFRatingBand) -> Color {
    switch band {
    case .foundation, .unrated: secondaryText
    case .developing: color(.hydro)
    case .advanced: accent
    case .challenging: color(.atcoder)
    case .expert: color(.vjudge)
    }
  }
}
struct CFPlatformContent: View {
  @Environment(TrainingStore.self) private var store
  let accounts: [OJAccount]
  var personID: UUID?
  var query: String
  @State private var section = 0
  @State private var day: Date?
  @State private var year = TrainingDates.calendar.component(.year, from: Date())
  @State private var metric = HeatMetric.submissions
  @AppStorage("cfHeatmapDifficulty") private var ratingColors = true
  private var ids: Set<UUID> { Set(accounts.map(\.id)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Picker("CF展示内容", selection: $section) {
        Text("难度题目").tag(0)
        Text("训练节奏").tag(1)
      }.pickerStyle(.segmented)
      if section == 0 {
        DateSelectionRow(selected: $day)
        CFPracticePanel(accountIDs: ids, day: day, query: query)
      } else {
        let summary = store.summary(accountIDs: ids)
        TrainingAnalysisLink(personID: personID, oj: .codeforces)
        HStack {
          YearMenu(years: summary.years, year: $year)
          Spacer()
          Picker("热力图统计口径", selection: $metric) {
            ForEach(HeatMetric.allCases) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.menu)
        }
        Picker("热力图配色", selection: $ratingColors) {
          Text("难度＋数量").tag(true)
          Text("仅数量").tag(false)
        }.pickerStyle(.segmented)
        TrainingHeatmap(days: summary.days.filter { TrainingDates.calendar.component(.year, from: $0.date) == year },
          year: year, metric: metric, selected: $day, ratingColors: ratingColors)
        DateSelectionRow(selected: $day)
        if day != nil {
          Button("按难度查看这一天的题目") { section = 0 }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
        NavigationLink("查看CF原始提交") { AllSubmissionsPage(accountIDs: ids, showPerson: true, day: day) }
          .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
      }
      DisclosureGroup("来源与账号状态") {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(accounts) { account in AccountStatus(account: account); Divider() }
        }.padding(.top, 10)
      }.trainingCard()
    }.onChange(of: year) { _, _ in day = nil }
  }
}
struct CFRatingBadge: View {
  let rating: Int?
  var body: some View {
    Text(rating.map(String.init) ?? "暂无rating")
      .font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.rating(.band(rating)))
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(Theme.rating(.band(rating)).opacity(0.09), in: Capsule())
      .accessibilityLabel(rating.map { "题目难度rating \($0)" } ?? "没有公开题目rating")
  }
}
struct CFRatingDistributionCard: View {
  let counts: [CFRatingCount]
  @Binding var selected: CFRatingBand?
  @Environment(\.dynamicTypeSize) private var typeSize
  private var selection: Binding<String?> {
    Binding(get: { selected?.label }, set: { value in selected = CFRatingBand.allCases.first { $0.label == value } })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout(alignment: .top))
      layout {
        ChartTitle("题目难度分布", subtitle: "按题目去重 · 点击一栏筛选")
        if !typeSize.isAccessibilitySize { Spacer() }
        Menu {
          Button("全部难度") { selected = nil }
          ForEach(CFRatingBand.allCases) { band in Button(band.label) { selected = band } }
        } label: {
          Label(selected?.label ?? "全部难度", systemImage: "line.3.horizontal.decrease")
            .font(.caption.weight(.medium)).frame(minHeight: 44)
        }.accessibilityLabel("选择CF题目难度范围")
      }
      Text("已采集AC \(counts.reduce(0) { $0 + $1.accepted }) 题 · 暂无AC \(counts.reduce(0) { $0 + $1.attempted }) 题")
        .font(.caption).foregroundStyle(Theme.secondaryText)
      Chart(counts) { count in
        BarMark(x: .value("题目数", count.total), y: .value("题目rating", count.band.label))
          .foregroundStyle(Theme.rating(count.band).opacity(selected == nil || selected == count.band ? 0.9 : 0.3))
          .cornerRadius(4)
          .annotation(position: .trailing) { Text(count.total, format: .number).font(.caption.monospacedDigit()) }
      }.chartXScale(domain: 0...max(1, Int(Double(counts.map(\.total).max() ?? 0) * 1.2) + 1))
        .chartYSelection(value: selection)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectYValue(at: $0.location.y) } }
        .frame(height: 210)
      ChartFootnote("rating来自CF题目字段；分段只用于浏览，不是用户段位。未知难度单列，不计作0。")
    }.trainingCard()
  }
}

struct CFPracticePanel: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  let accountIDs: Set<UUID>
  var day: Date?
  var query: String
  @State private var problems: [CFPracticeProblem] = []
  @State private var band: CFRatingBand?
  @State private var status: CFProblemStatus = .all
  @State private var order: CFProblemOrder = .ascending
  @State private var visibleCount = 60
  @State private var calculating = false
  private var queryKey: String {
    store.queryGeneration + accountIDs.map(\.uuidString).sorted().joined() + query + String(day?.timeIntervalSince1970 ?? 0)
  }
  private var filtered: [CFPracticeProblem] { CFPractice.filter(problems, band: band, status: status, order: order) }
  private func groups(_ filtered: [CFPracticeProblem]) -> [(Int, [CFPracticeProblem])] {
    let shown = Array(filtered.prefix(visibleCount))
    if order == .latest { return [(0, shown)] }
    let groups = Dictionary(grouping: shown) { $0.rating ?? -1 }
    return groups.keys.sorted { a, b in
      if a == -1 { return false }; if b == -1 { return true }
      return order == .ascending ? a < b : a > b
    }.map { ($0, groups[$0]!) }
  }
  var body: some View {
    let ordered = filtered
    VStack(alignment: .leading, spacing: 18) {
      if calculating { ProgressView("正在按难度整理题目…").font(.caption) }
      if !problems.isEmpty {
        CFRatingDistributionCard(counts: CFPractice.distribution(problems), selected: $band)
      }
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(day.map { TrainingDates.text($0, format: "M月d日") + "的题目" } ?? "按难度看题").font(.title3.bold())
          Spacer()
          Text("\(ordered.count) 题").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
        }
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
          Menu {
            ForEach(CFProblemStatus.allCases) { s in Button(s.rawValue) { status = s } }
          } label: { FilterMenuLabel(title: status.rawValue, icon: "checkmark.circle") }
          Menu {
            ForEach(CFProblemOrder.allCases) { s in Button(s.rawValue) { order = s } }
          } label: { FilterMenuLabel(title: order == .ascending ? "难度低到高" : order == .descending ? "难度高到低" : "最近提交", icon: "arrow.up.arrow.down") }
        }
        if let band {
          HStack {
            Label("rating · " + band.label, systemImage: "line.3.horizontal.decrease").font(.caption).foregroundStyle(Theme.rating(band))
            Spacer()
            Button("清除难度筛选") { self.band = nil }.font(.caption).frame(minHeight: 44)
          }
        }
      }
      if !calculating, ordered.isEmpty {
        EmptyTraining(title: problems.isEmpty ? "暂无已采集的CF题目" : "这个范围暂无匹配题目",
          detail: "可以切换日期、状态或难度；来源没有返回记录时，不推断为没有训练。")
      }
      LazyVStack(alignment: .leading, spacing: 18) {
        ForEach(groups(ordered), id: \.0) { group in
          VStack(alignment: .leading, spacing: 10) {
            Text(order == .latest ? "最近提交的题目" : group.0 == -1 ? "暂无公开rating" : "Rating \(group.0)")
              .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.rating(.band(group.0)))
            VStack(spacing: 0) {
              ForEach(group.1) { problem in
                NavigationLink { CFProblemDetailPage(problem: problem, day: day) } label: { CFProblemRow(problem: problem) }
                  .buttonStyle(.plain)
                if problem.id != group.1.last?.id { Divider() }
              }
            }.trainingCard()
          }
        }
      }.opacity(calculating ? 0.6 : 1)
      if ordered.count > visibleCount {
        Button("继续显示 \(min(60, ordered.count - visibleCount)) 题（共\(ordered.count)题）") { visibleCount += 60 }
          .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
          .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
      }
      ChartFootnote("每题汇总当前筛选内的重复提交；任一所选账号有AC即显示已采集AC。打开题目可核对各账号的原始提交。")
    }.task(id: queryKey) { await prepare() }
      .onChange(of: band) { _, _ in visibleCount = 60 }
      .onChange(of: status) { _, _ in visibleCount = 60 }
      .onChange(of: order) { _, _ in visibleCount = 60 }
  }
  private func prepare() async {
    calculating = true
    do {
      if !query.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
      let rows = store.rows(accountIDs: accountIDs), accounts = accountIDs.compactMap { store.account($0) }
      let date = day, text = query
      let aliases = Dictionary(uniqueKeysWithValues: accounts.map { account in
        (account.id, [store.owner(account.id)?.displayName ?? "", account.handle, account.platformName].joined(separator: " "))
      })
      let worker = Task.detached(priority: .userInitiated) {
        let matching = try TrainingSearch.filter(rows, query: text, day: date, accountAliases: aliases)
        return CFPractice.problems(rows: matching, accounts: accounts)
      }
      let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      problems = result; calculating = false; visibleCount = 60
    } catch { if !Task.isCancelled { calculating = false } }
  }
}
private struct CFProblemRow: View {
  let problem: CFPracticeProblem
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(problem.problemID).font(.caption.monospaced()).foregroundStyle(Theme.secondaryText)
        Spacer()
        CFRatingBadge(rating: problem.rating)
      }
      Text(problem.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        Label(problem.accepted ? "已采集AC" : "暂无AC", systemImage: problem.accepted ? "checkmark.circle.fill" : "circle.dashed")
          .foregroundStyle(problem.accepted ? Theme.success : Theme.secondaryText)
        Text("· \(problem.rows.count) 次提交").foregroundStyle(Theme.secondaryText)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
      }.font(.caption)
    }.padding(.vertical, 10).contentShape(Rectangle())
  }
}
private struct CFProblemDetailPage: View {
  #if CFPOCKET
  @Environment(PocketModel.self) private var pocket
  @Environment(RuntimeEngine.self) private var engine
  #endif
  let problem: CFPracticeProblem
  var day: Date?
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 12) {
          HStack { OJBadge(oj: .codeforces); Spacer(); CFRatingBadge(rating: problem.rating) }
          Text(problem.title).font(.title2.bold())
          Text(problem.problemID).font(.subheadline.monospaced()).foregroundStyle(Theme.secondaryText)
          Label(problem.accepted ? "当前筛选内已采集到AC" : "当前筛选内尚未采集到AC", systemImage: problem.accepted ? "checkmark.circle" : "circle.dashed")
            .font(.subheadline).foregroundStyle(problem.accepted ? Theme.success : Theme.secondaryText)
          #if CFPOCKET
          if let url = URL(string: problem.url), let key = try? ProblemID(url: url) {
            NavigationLink {
              WorkspaceScreen(model: WorkspaceModel(app: pocket, problem: pocket.problems.first { $0.key == key } ?? PocketProblem(key: key, name: problem.title, rating: problem.rating)), engine: engine)
            } label: { Label("在这里练习与复盘", systemImage: "pencil.and.outline") }.buttonStyle(.borderedProminent)
          }
          #endif
          if let url = URL(string: problem.url) { Link("打开CF原题", destination: url).font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
        }.trainingCard()
        HStack { Text("原始提交").font(.headline); Spacer(); Text("\(problem.rows.count) 次").font(.caption).foregroundStyle(Theme.secondaryText) }
        VStack(spacing: 0) {
          ForEach(Array(problem.rows.prefix(12))) { row in SubmissionRow(row: row, showPerson: true); Divider() }
        }.trainingCard()
        NavigationLink("查看这题的全部提交") {
          AllSubmissionsPage(accountIDs: Set(problem.rows.map(\.accountID)), showPerson: true, day: day, problemID: problem.problemID)
        }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
      }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
    }.background(Theme.canvas).navigationTitle(problem.problemID).navigationBarTitleDisplayMode(.inline)
  }
}
