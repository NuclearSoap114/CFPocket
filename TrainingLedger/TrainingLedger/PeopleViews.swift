import SwiftUI
import TrainingCore

enum PeopleFilter: String, CaseIterable, Identifiable {
  case all = "全部"
  case favorites = "已收藏"
  case attention = "需处理"
  var id: String { rawValue }
}
struct PeoplePage: View {
  @Environment(TrainingStore.self) private var store
  @State private var query = ""
  @State private var filter = PeopleFilter.all
  private var matching: [Person] {
    store.people.filter { p in
      p.matches(query)
        && (filter == .all || (filter == .favorites && p.favorite)
          || (filter == .attention && p.accounts.contains { store.info($0.id).error != nil }))
    }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ProgressBanner()
        OverviewHeader()
        if store.loaded, !store.archive.submissions.isEmpty {
          TrainingPulseCard(accountIDs: Set(store.accounts.map(\.id)))
        }
        Picker("人物筛选", selection: $filter) {
          ForEach(PeopleFilter.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
        if !store.loaded {
          ProgressView("正在读取本地记录…").frame(maxWidth: .infinity)
        } else if store.people.isEmpty {
          EmptyTraining(title: "建立训练档案", detail: "点右上角 + 添加人物，填写真名或昵称，再绑定各平台 ID。")
        } else if matching.isEmpty {
          EmptyTraining(title: "没有符合条件的人物", detail: "试试真名、昵称或平台 ID，也可以切换上方筛选。")
        } else {
          ForEach([true, false], id: \.self) { favorite in
            let people = matching.filter { $0.favorite == favorite }
            if !people.isEmpty {
              HStack {
                Label(favorite ? "置顶关注" : "训练档案", systemImage: favorite ? "star.fill" : "person.2")
                  .font(.headline)
                Spacer()
                Text("\(people.count)人").font(.caption).foregroundStyle(Theme.secondaryText)
              }.padding(.top, 6)
              ForEach(people) { p in
                NavigationLink {
                  PersonTrainingPage(personID: p.id)
                } label: {
                  PersonCard(person: p)
                }.buttonStyle(.plain)
              }
            }
          }
        }
        Text("仅统计已采集的公开记录。来源未连接或数据未公开，不代表没有训练。").font(.caption).foregroundStyle(Theme.secondaryText)
          .padding(.top, 6)
      }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
    }.background(Theme.canvas).searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "真名、昵称或任意平台 ID").refreshable {
      store.refresh()
    }
  }
}
struct OverviewHeader: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    let sources = Set(store.accounts.map(\.oj)).count
    Group {
      if typeSize.isAccessibilitySize {
        VStack(spacing: 12) {
          LabeledContent("人物", value: store.people.count.formatted())
          LabeledContent("OJ 平台", value: sources.formatted())
          LabeledContent("已收集提交", value: store.archive.submissions.count.formatted())
        }.font(.subheadline).monospacedDigit()
      } else {
        HStack(spacing: 0) {
          metric("人物", store.people.count)
          Divider().frame(height: 28)
          metric("OJ 平台", sources)
          Divider().frame(height: 28)
          metric("已收集提交", store.archive.submissions.count)
        }
      }
    }.padding(.vertical, 5)
  }
  private func metric(_ title: String, _ count: Int) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(count, format: .number).font(.title2.weight(.bold)).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct PersonCard: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  let person: Person
  var body: some View {
    let current = store.person(person.id) ?? person
    let summary = store.summary(accountIDs: Set(current.accounts.map(\.id)))
    let week = TrainingDates.calendar.date(
      byAdding: .day, value: -6, to: TrainingDates.day(Date()))!
    let recent = summary.days.filter { $0.date >= week }.reduce(0) { $0 + $1.submissions }
    let errors = current.accounts.filter { store.info($0.id).error != nil }.count
    let tint = Theme.avatar(current.id)
    VStack(alignment: .leading, spacing: 14) {
      let headerLayout = typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        : AnyLayout(HStackLayout(spacing: 12))
      headerLayout {
        Text(String(current.displayName.prefix(1)).uppercased()).font(.title3.bold())
          .foregroundStyle(tint).frame(width: 45, height: 45).background(
            tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(current.displayName).font(.headline)
            if current.favorite {
              Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.favorite)
            }
          }
          Text(
            current.alias.map { "\($0) · \(current.accounts.count) 个账号" }
              ?? "\(current.accounts.count) 个 OJ 账号"
          ).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        if !typeSize.isAccessibilitySize {
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(
            Theme.secondaryText)
        }
      }
      MiniHeatmap(days: summary.days)
      let countLayout = typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        : AnyLayout(HStackLayout())
      countLayout {
        Text("近7天 \(recent) 次提交").font(.subheadline.weight(.semibold))
        if !typeSize.isAccessibilitySize { Spacer() }
        Text("共 \(summary.stats.submissions) 次").font(.caption).foregroundStyle(Theme.secondaryText)
      }
      ScrollView(.horizontal) {
        HStack(spacing: 7) {
          ForEach(current.accounts) { a in
            HStack(spacing: 5) {
              OJBadge(oj: a.oj)
              Text(a.handle).font(.caption2.monospaced()).foregroundStyle(Theme.secondaryText)
            }.padding(.trailing, 5)
          }
        }
      }.scrollIndicators(.hidden)
      if errors > 0 {
        Label("\(errors) 个来源需处理 · 可在详情中连接或重试", systemImage: "exclamationmark.circle").font(.caption)
          .foregroundStyle(Theme.warning)
      }
    }.trainingCard()
  }
}
struct PersonTrainingPage: View {
  @Environment(TrainingStore.self) private var store
  let personID: UUID
  @State private var oj: OJ?
  @State private var year = TrainingDates.calendar.component(.year, from: Date())
  @State private var selectedDate: Date?
  @State private var metric = HeatMetric.submissions
  @State private var query = ""
  @State private var editing: Person?
  @State private var showAccounts = false
  private var person: Person? { store.person(personID) }
  private var accounts: [OJAccount] { person?.accounts.filter { oj == nil || $0.oj == oj } ?? [] }
  private var summary: TrainingSummary { store.summary(accountIDs: Set(accounts.map(\.id))) }
  private var allRows: [Submission] { summary.rows }
  private var rows: [Submission] {
    let source =
      selectedDate.flatMap { summary.rowsByDay[$0] } ?? (selectedDate == nil ? allRows : [])
    return source.filter {
      (selectedDate == nil || TrainingDates.day($0.timestamp) == selectedDate!)
        && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
          || $0.problemID.localizedCaseInsensitiveContains(query))
    }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ProgressBanner()
        if let person {
          ProfileHeader(person: person)
          OJFilter(
            choices: Array(Set(person.accounts.map(\.oj))).sorted { $0.rawValue < $1.rawValue },
            selection: $oj)
          MetricRow(stats: summary.stats)
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
            }, year: year, metric: metric, selected: $selectedDate)
          DateSelectionRow(selected: $selectedDate)
          DisclosureGroup("来源状态与网页连接", isExpanded: $showAccounts) {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(accounts) { a in
                AccountStatus(account: a)
                if a.id != accounts.last?.id { Divider() }
              }
            }.padding(.top, 12)
          }.font(.subheadline.weight(.medium)).trainingCard()
          HStack {
            Text(selectedDate.map { TrainingDates.text($0, format: "M月d日") + "的提交" } ?? "最近提交")
              .font(.headline)
            Spacer()
            Text("\(rows.count) 条").font(.caption).foregroundStyle(Theme.secondaryText)
          }
          if rows.isEmpty {
            EmptyTraining(
              title: selectedDate == nil ? "还没有采集到记录" : "这一天暂无已采集记录",
              detail: "检查上方来源状态；采集失败或数据未公开时，不代表没有训练。")
          } else {
            VStack(spacing: 0) {
              ForEach(Array(rows.prefix(100))) { row in
                SubmissionRow(row: row)
                if row.id != rows.prefix(100).last?.id { Divider() }
              }
            }.trainingCard()
            if rows.count > 100 {
              NavigationLink("搜索和查看全部 \(rows.count) 条记录") {
                AllSubmissionsPage(
                  accountIDs: Set(accounts.map(\.id)), showPerson: false, day: selectedDate)
              }
            }
          }
        }
      }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
    }.background(Theme.canvas)
      .navigationTitle(person?.displayName ?? "人物").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            Task { await store.toggleFavorite(personID) }
          } label: {
            Image(systemName: person?.favorite == true ? "star.fill" : "star")
          }.accessibilityLabel(person?.favorite == true ? "取消收藏" : "收藏置顶")
          SyncButton(ids: Set(person?.accounts.map(\.id) ?? []))
          Button {
            editing = person
          } label: {
            Image(systemName: "ellipsis")
          }.accessibilityLabel("编辑人物")
        }
      }
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "题目名称或题号").refreshable {
        store.refresh(accountIDs: Set(person?.accounts.map(\.id) ?? []))
      }
      .sheet(item: $editing) { p in PersonEditor(person: p) }
      .onChange(of: year) { _, _ in selectedDate = nil }
  }
}
struct ProfileHeader: View {
  let person: Person
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
    layout {
      Text(String(person.displayName.prefix(1)).uppercased()).font(.title.weight(.bold))
        .foregroundStyle(
          Theme.accent
        ).frame(width: 60, height: 60).background(
          Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
      VStack(alignment: .leading, spacing: 7) {
        Text(person.displayName).font(.title2.bold())
        if let alias = person.alias {
          Text(alias).font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
        Text("\(person.accounts.count) 个账号 · 跨 OJ 训练档案").font(.subheadline).foregroundStyle(Theme.secondaryText)
      }
    }.padding(.vertical, 8)
  }
}
struct OJFilter: View {
  let choices: [OJ]
  @Binding var selection: OJ?
  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        chip("全部", oj: nil)
        ForEach(choices) { oj in chip(oj.shortName, oj: oj) }
      }
    }.scrollIndicators(.hidden)
  }
  private func chip(_ title: String, oj: OJ?) -> some View {
    Button {
      selection = oj
    } label: {
      Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 40)
        .background(
          selection == oj ? Theme.accent : Color(uiColor: .secondarySystemGroupedBackground),
          in: Capsule()
        ).foregroundStyle(selection == oj ? Theme.onAccent : Color.primary)
    }.buttonStyle(.plain).accessibilityAddTraits(selection == oj ? .isSelected : [])
  }
}
struct YearMenu: View {
  let years: [Int]
  @Binding var year: Int
  var body: some View {
    Menu {
      ForEach(years, id: \.self) { value in Button(String(value)) { year = value } }
    } label: {
      HStack {
        Text(String(year))
        Image(systemName: "chevron.down").font(.caption)
      }
    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
  }
}
struct DateSelectionRow: View {
  @Binding var selected: Date?
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(spacing: 10))
    layout {
      Text("查看某一天").font(.subheadline)
      if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
      HStack(spacing: 12) {
        DatePicker("查看某一天", selection: Binding(get: { selected ?? Date() }, set: { selected = TrainingDates.day($0) }),
          in: ...Date(), displayedComponents: .date).labelsHidden().font(.subheadline)
          .accessibilityLabel("查看某一天")
        if selected != nil { Button("全部") { selected = nil }.font(.subheadline).frame(minHeight: 44) }
      }
    }.frame(minHeight: 44)
  }
}
