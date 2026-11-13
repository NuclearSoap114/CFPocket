import SwiftUI
import TrainingCore

struct PlatformsPage: View {
  @Environment(TrainingStore.self) private var store
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ProgressBanner()
        Text("换一个视角，查看同一平台上每个人的训练。").font(.subheadline).foregroundStyle(Theme.secondaryText)
        ForEach(OJ.allCases) { oj in
          let accounts = store.accounts.filter { $0.oj == oj }
          let ids = Set(accounts.map(\.id))
          let summary = store.summary(accountIDs: ids)
          let rows = summary.rows
          let people = store.people.filter { $0.accounts.contains { $0.oj == oj } }
          NavigationLink {
            PlatformTrainingPage(oj: oj)
          } label: {
            HStack(alignment: .top, spacing: 14) {
              Text(oj == .codeforces ? "CF" : String(oj.name.prefix(2))).font(
                .headline.weight(.black)
              ).foregroundStyle(Theme.color(oj)).frame(width: 48, height: 48).background(
                Theme.color(oj).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
              VStack(alignment: .leading, spacing: 8) {
                Text(oj.name).font(.headline)
                Text("\(people.count) 人 · \(accounts.count) 个账号").font(.caption).foregroundStyle(Theme.secondaryText)
                MiniHeatmap(days: summary.days)
              }
              Spacer(minLength: 0)
              VStack(alignment: .trailing, spacing: 8) {
                Text(rows.count, format: .number).font(.title3.bold()).monospacedDigit()
                Text("已收集提交").font(.caption2).foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
              }
            }.trainingCard()
          }.buttonStyle(.plain)
        }
      }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
    }.background(Theme.canvas).refreshable { store.refresh() }
  }
}
struct PlatformTrainingPage: View {
  @Environment(TrainingStore.self) private var store
  let oj: OJ
  @State private var personID: UUID?
  @State private var year = TrainingDates.calendar.component(.year, from: Date())
  @State private var date: Date?
  @State private var metric = HeatMetric.submissions
  @State private var favoriteFirst = true
  @State private var query = ""
  private var people: [Person] { store.people.filter { $0.accounts.contains { $0.oj == oj } } }
  private var accounts: [OJAccount] {
    people.filter { personID == nil || $0.id == personID }.flatMap(\.accounts).filter {
      $0.oj == oj
    }
  }
  private var summary: TrainingSummary { store.summary(accountIDs: Set(accounts.map(\.id))) }
  private var all: [Submission] { summary.rows }
  private var rows: [Submission] {
    let filtered = all.filter {
      (date == nil || TrainingDates.day($0.timestamp) == date!)
        && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
          || $0.problemID.localizedCaseInsensitiveContains(query)
          || (store.owner($0.accountID)?.displayName.localizedCaseInsensitiveContains(query)
            ?? false))
    }
    if !favoriteFirst { return filtered }
    let pinned = Set(store.people.filter(\.favorite).flatMap(\.accounts).map(\.id))
    return filtered.filter { pinned.contains($0.accountID) }
      + filtered.filter { !pinned.contains($0.accountID) }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ProgressBanner()
        if accounts.isEmpty, people.isEmpty {
          EmptyTraining(title: "尚未绑定\(oj.name)账号", detail: "在人物资料中添加此 OJ 的用户 ID，即可按平台查看训练。")
        } else {
          Text("\(people.count) 位人物 · \(oj.name)训练档案").font(.subheadline).foregroundStyle(Theme.secondaryText)
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              personChip(nil, "全部人物")
              ForEach(people) { p in personChip(p.id, (p.favorite ? "★ " : "") + p.displayName) }
            }
          }.scrollIndicators(.hidden)
          MetricRow(stats: summary.stats)
          if oj == .codeforces {
            CFPlatformContent(accounts: accounts, personID: personID, query: query)
          } else {
            TrainingAnalysisLink(personID: personID, oj: oj)
            HStack {
              YearMenu(years: summary.years, year: $year)
              Spacer()
              Picker("统计口径", selection: $metric) {
                ForEach(HeatMetric.allCases) { Text($0.rawValue).tag($0) }
              }.pickerStyle(.menu)
            }
            TrainingHeatmap(
              days: summary.days.filter {
                TrainingDates.calendar.component(.year, from: $0.date) == year
              }, year: year, metric: metric, selected: $date)
            DateSelectionRow(selected: $date)
            DisclosureGroup("来源与账号状态") {
              VStack(alignment: .leading, spacing: 12) {
                ForEach(accounts) { a in
                  Text(store.owner(a.id)?.displayName ?? "").font(.caption.weight(.semibold))
                  AccountStatus(account: a)
                  Divider()
                }
              }.padding(.top, 12)
            }.trainingCard()
            HStack {
              Text(date.map { TrainingDates.text($0, format: "M月d日") + "的提交" } ?? "训练记录").font(
                .headline)
              Spacer()
              Toggle("收藏优先", isOn: $favoriteFirst).font(.caption).fixedSize()
            }
            if rows.isEmpty {
              EmptyTraining(title: "暂无已采集记录", detail: "可查看上方各账号的同步状态。来源未连接不等于没有训练。")
            } else {
              VStack(spacing: 0) {
                ForEach(Array(rows.prefix(100))) { r in
                  SubmissionRow(row: r, showPerson: true)
                  Divider()
                }
              }.trainingCard()
              if rows.count > 100 {
                NavigationLink("查看全部 \(rows.count) 条记录") {
                  AllSubmissionsPage(accountIDs: Set(accounts.map(\.id)), showPerson: true, day: date)
                }
              }
            }
          }
        }
      }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
    }.background(Theme.canvas).navigationTitle(oj.name).navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "题目、题号或人物")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { SyncButton(ids: Set(accounts.map(\.id))) }
      }.refreshable { store.refresh(accountIDs: Set(accounts.map(\.id))) }
      .onChange(of: year) { _, _ in date = nil }
  }
  private func personChip(_ id: UUID?, _ title: String) -> some View {
    Button {
      personID = id
    } label: {
      Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 40)
        .background(
          personID == id ? Theme.accent : Color(uiColor: .secondarySystemGroupedBackground),
          in: Capsule()
        ).foregroundStyle(personID == id ? Theme.onAccent : Color.primary)
    }.buttonStyle(.plain)
  }
}
struct AllSubmissionsPage: View {
  @Environment(TrainingStore.self) private var store
  let accountIDs: Set<UUID>
  let showPerson: Bool
  var day: Date? = nil
  var problemID: String? = nil
  @State private var search = ""
  @State private var onlyAC = false
  @State private var results: [Submission] = []
  @State private var searching = false
  private var queryID: String {
    "\(store.queryGeneration)|\(search)|\(onlyAC)|\(day?.timeIntervalSince1970 ?? 0)|\(problemID ?? "")"
  }
  var body: some View {
    List {
      Section {
        Toggle("只看通过", isOn: $onlyAC)
        if let problemID { Text("题号 · " + problemID).font(.caption.monospaced()).foregroundStyle(Theme.accent) }
        if let day {
          Text(TrainingDates.text(day, format: "yyyy年M月d日")).font(.caption).foregroundStyle(
            Theme.secondaryText)
        }
        HStack {
          Text("\(results.count) 条匹配记录").font(.caption).foregroundStyle(Theme.secondaryText)
          Spacer()
          if searching { ProgressView().controlSize(.small) }
        }
      }
      ForEach(results) { row in SubmissionRow(row: row, showPerson: showPerson) }
      if !searching, results.isEmpty {
        EmptyTraining(title: "没有匹配的记录", detail: "可以按真名、平台 ID、题名或题号搜索，或调整通过状态筛选。")
      }
    }.navigationTitle("全部提交").navigationBarTitleDisplayMode(.inline).searchable(
      text: $search, prompt: "真名、平台 ID、题目或题号"
    )
    .task(id: queryID) {
      searching = true
      do {
        if !search.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
        let source = store.rows(accountIDs: accountIDs).filter { problemID == nil || $0.problemID == problemID }
        let query = search
        let accepted = onlyAC
        let date = day
        let aliases = Dictionary(
          uniqueKeysWithValues: accountIDs.map { id in
            (
              id,
              [
                store.owner(id)?.displayName, store.owner(id)?.name, store.account(id)?.handle,
                store.account(id)?.platformName,
              ].compactMap { $0 }.joined(separator: " ")
            )
          })
        let worker = Task.detached(priority: .userInitiated) {
          try TrainingSearch.filter(
            source, query: query, onlyAccepted: accepted, day: date, accountAliases: aliases)
        }
        let filtered = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        try Task.checkCancellation()
        results = filtered
        searching = false
      } catch { if !Task.isCancelled { searching = false } }
    }
  }
}
