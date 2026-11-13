import SwiftUI
import Charts
import PocketCore
import TrainingCore

struct TrainingHome: View {
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  let showProfile: () -> Void
  @Environment(TrainingStore.self) private var ledger
  @AppStorage("CFPocket.primaryPerson") private var personKey = ""
  private var person: Person? { ledger.people.first { $0.id.uuidString == personKey } }
  private var latest: Workspace? { model.workspaces.max { $0.updatedAt < $1.updatedAt } }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        TrainingGreeting(name: person?.displayName)
        TrainingPlanEntry(model: model, engine: engine)
        if model.plans.plan == nil {
          ContinueTrainingCard(workspace: latest, model: model, engine: engine)
        } else if let latest {
          let problem = model.problems.first { $0.key == latest.problem } ?? PocketProblem(key: latest.problem, name: latest.problem.id)
          NavigationLink { WorkspaceScreen(model: WorkspaceModel(app: model, problem: problem), engine: engine) } label: {
            PocketDestinationLabel(title: "接着上次的草稿", detail: "CF \(problem.id) · \(problem.name)", symbol: "pencil.and.outline").pocketSurface()
          }.buttonStyle(.plain)
        }
        if let error = model.plans.error { StatusNotice(title: "题单读取未完成", message: error, symbol: "exclamationmark.circle") }
        if let person {
          WeeklyTrainingCard(summary: ledger.summary(accountIDs: Set(person.accounts.map(\.id))))
        } else {
          Button(action: showProfile) {
            PocketDestinationLabel(title: "选择我的档案", detail: "查看自己的平台记录与训练节奏", symbol: "person.crop.circle")
          }.buttonStyle(.plain).pocketSurface()
        }
        HStack(spacing: 12) {
          NavigationLink { LibraryScreen(model: model, engine: engine) } label: { PracticeEntryTile(title: "探索题库", detail: "\(model.problems.count.formatted()) 道 CF 题目", symbol: "square.grid.2x2", color: PocketStyle.accent) }.buttonStyle(.plain)
          NavigationLink { PracticeScreen(model: model, engine: engine) } label: { PracticeEntryTile(title: "我的练习", detail: "\(model.workspaces.count) 份本机记录", symbol: "bookmark", color: PocketStyle.amber) }.buttonStyle(.plain)
        }
        if let error = model.libraryError {
          StatusNotice(title: "正在使用已保存题库", message: error, symbol: "wifi.exclamationmark")
        }
        if !model.problems.isEmpty {
          PocketSectionTitle(title: "挑一道题，开始思考")
          TrainingDiscovery(model: model, engine: engine)
        }
      }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
        .frame(maxWidth: 700).frame(maxWidth: .infinity)
    }.background(PocketStyle.canvas).navigationTitle("训练")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { LibraryScreen(model: model, engine: engine) } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索题目") } }
      .refreshable { await model.refresh() }
  }
}
struct TrainingGreeting: View {
  let name: String?
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(Date(), format: .dateTime.month(.wide).day().weekday(.wide)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
      Spacer()
      if let name { Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(PocketStyle.accent).lineLimit(1) }
    }
  }
}
struct ContinueTrainingCard: View {
  let workspace: Workspace?
  let model: PocketModel
  let engine: RuntimeEngine
  var problem: PocketProblem? {
    workspace.map { value in model.problems.first { $0.key == value.problem } ?? PocketProblem(key: value.problem, name: value.problem.id) }
  }
  var body: some View {
    if let problem, let workspace {
      NavigationLink { WorkspaceScreen(model: WorkspaceModel(app: model, problem: problem), engine: engine) } label: {
        ContinueTrainingFace(title: problem.name, eyebrow: "继续上次的思考", detail: "CF \(problem.id) · \(workspace.language.rawValue)", subtitle: workspace.updatedAt.formatted(date: .abbreviated, time: .shortened), active: true)
      }.buttonStyle(.plain)
    } else {
      NavigationLink { LibraryScreen(model: model, engine: engine) } label: {
        ContinueTrainingFace(title: "下一道题，\n从一个想法开始。", eyebrow: "专注这一题", detail: "读题、写思路，再亲手验证", subtitle: "打开 Codeforces 题库", active: false)
      }.buttonStyle(.plain)
    }
  }
}
struct ContinueTrainingFace: View {
  let title: String; let eyebrow: String; let detail: String; let subtitle: String; let active: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Label(eyebrow, systemImage: active ? "pencil.and.outline" : "sparkle").font(.caption.weight(.semibold))
          .padding(.horizontal, 11).padding(.vertical, 7).background(.white.opacity(0.08), in: Capsule())
        Spacer()
        Image(systemName: "arrow.up.right").font(.headline).frame(width: 40, height: 40).background(.white.opacity(0.08), in: Circle())
      }.foregroundStyle(PocketStyle.heroAccent)
      Text(title).font(.system(.title, weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 9) {
        Text(detail).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.9))
        HStack { Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.67)); Spacer(); Image(systemName: "curlybraces").font(.title2.weight(.light)).foregroundStyle(.white.opacity(0.35)).accessibilityHidden(true) }
      }
    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      .background {
        ZStack(alignment: .trailing) {
          PocketStyle.hero
          ForEach(0..<3) { index in RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.045), lineWidth: 1).frame(width: 180, height: 180).rotationEffect(.degrees(Double(index * 19 + 22))).offset(x: 90, y: 15) }
        }.clipShape(RoundedRectangle(cornerRadius: 26))
      }.accessibilityElement(children: .combine)
  }
}

struct WeeklyTrainingCard: View {
  let summary: TrainingSummary
  private var days: [Date] { let c = TrainingDates.calendar; return (-6...0).map { c.date(byAdding: .day, value: $0, to: TrainingDates.day(Date()))! } }
  var body: some View {
    let counts = Dictionary(uniqueKeysWithValues: summary.days.map { ($0.date, $0.submissions) })
    let total = days.reduce(0) { $0 + (counts[$1] ?? 0) }
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline) {
        Text("近 7 天").font(.headline)
        Spacer()
        Text("\(total) 次提交").font(.subheadline.weight(.semibold)).foregroundStyle(PocketStyle.accent)
      }
      HStack(alignment: .bottom, spacing: 8) {
        ForEach(days, id: \.self) { date in
          let value = counts[date] ?? 0
          VStack(spacing: 8) {
            Text(value.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(value == 0 ? .secondary : .primary)
            Capsule().fill(value == 0 ? Color(uiColor: .quaternarySystemFill) : PocketStyle.accent.opacity(TrainingDates.day(Date()) == date ? 1 : 0.45))
              .frame(height: value == 0 ? 5 : 12 + 42 * CGFloat(value) / CGFloat(max(1, days.map { counts[$0] ?? 0 }.max() ?? 1)))
              .frame(height: 54, alignment: .bottom)
            Text(date, format: .dateTime.weekday(.narrow)).font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TrainingDates.text(date, format: "M月d日"))，已采集 \(value) 次提交")
        }
      }
      Text("最近 7 天 · 仅计算所选人物已采集的 OJ 提交").font(.caption).foregroundStyle(.secondary)
    }.pocketSurface()
  }
}
struct TrainingDiscovery: View {
  let model: PocketModel
  let engine: RuntimeEngine
  @AppStorage("CFPocket.discoveryRating") private var rating = 1200
  @State private var showsDifficulty = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(showsDifficulty ? "隐藏难度" : "显示难度") { showsDifficulty.toggle() }.font(.subheadline).frame(minHeight: 44)
      if showsDifficulty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach([800, 1000, 1200, 1400, 1600, 1800, 2000, 2400], id: \.self) { value in
              Button { rating = value } label: {
                HStack(spacing: 3) {
                  if rating == value { Image(systemName: "checkmark").font(.caption).accessibilityHidden(true) }
                  DifficultyBadge(title: String(value), rgb: DifficultyPalette.codeforces(value))
                }.frame(minHeight: 44)
              }.buttonStyle(.plain).accessibilityAddTraits(rating == value ? .isSelected : [])
            }
          }
        }.scrollIndicators(.hidden)
      }
      VStack(spacing: 0) {
        ForEach(Array(model.problems.lazy.filter { $0.rating == rating }.prefix(3))) { problem in
          NavigationLink { WorkspaceScreen(model: WorkspaceModel(app: model, problem: problem), engine: engine) } label: { ProblemRow(problem: problem, showsDifficulty: showsDifficulty) }.buttonStyle(.plain)
          Divider()
        }
      }.pocketSurface()
    }
  }
}
