import SwiftUI
import PocketCore
import TrainingCore

@main struct CFPocketApp: App {
  @State private var boot = PocketBootstrap()
  @State private var engine = RuntimeEngine()
  @State private var ledger = TrainingStore(seedDefaultPerson: false)
  @Environment(\.scenePhase) private var scenePhase
  var body: some Scene {
    WindowGroup {
      Group {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reading-review") { ReadingReview() }
        else if let model = boot.model { PocketRoot(model: model, engine: engine) }
        else { ContentUnavailableView("本地存储暂时不可用", systemImage: "externaldrive", description: Text(boot.error ?? "请重试")) }
        #else
        if let model = boot.model { PocketRoot(model: model, engine: engine) }
        else { ContentUnavailableView { Label("本地存储暂时不可用", systemImage: "externaldrive.badge.exclamationmark") } description: { Text(boot.error ?? "原有文件未覆盖，可释放空间后重试。") } actions: { Button("重试") { boot.retry() } } }
        #endif
      }
        .tint(PocketStyle.accent)
        .environment(ledger)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .environment(\.timeZone, TrainingDates.calendar.timeZone)
        .overlay(alignment: .bottomLeading) { RuntimeHost(engine: engine).frame(width: 1, height: 1).opacity(0.01).accessibilityHidden(true).allowsHitTesting(false) }
        .task {
          if ProcessInfo.processInfo.arguments.contains("--runtime-probe") { await RuntimeProbe.run(engine: engine) }
        }
        .onChange(of: scenePhase) { _, phase in
          engine.inForeground = phase == .active
          if phase != .active { engine.stop(reason: "切到后台，本地运行已停止；代码与思路保留。") }
          else if let model = boot.model { Task { await model.plans.synchronizeIfNeeded() } }
        }
    }
  }
}
struct PocketRoot: View {
  private enum Tab { case training, statistics, profile }
  @State private var selectedTab = Tab.training
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  @Environment(TrainingStore.self) private var ledger
  var body: some View {
    @Bindable var ledger = ledger
    TabView(selection: $selectedTab) {
      NavigationStack { TrainingHome(model: model, engine: engine, showProfile: { selectedTab = .profile }) }.tabItem { Label("训练", systemImage: "pencil.and.outline") }.tag(Tab.training)
      NavigationStack { StatisticsHome() }.tabItem { Label("统计", systemImage: "chart.xyaxis.line") }.tag(Tab.statistics)
      NavigationStack { ProfileHome(model: model, engine: engine) }.tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(Tab.profile)
    }
    .environment(model).environment(engine)
    .background {
      if ledger.connection == nil {
        WebHost(session: ledger.web, hidesWebAccessibility: true).frame(width: 390, height: 800)
          .offset(x: -1000, y: -1000).opacity(0.01).accessibilityHidden(true)
      }
    }
    .sheet(item: $ledger.connection) { WebConnectionPage(account: $0) }
    .alert("训练记录", isPresented: Binding(get: { ledger.message != nil }, set: { if !$0 { ledger.message = nil } })) {
      Button("知道了") { ledger.message = nil }
    } message: { Text(ledger.message ?? "") }
    .task {
      await model.plans.load()
      await ledger.start()
      await migratePendingLedger()
      await model.load()
    }
  }
  private func migratePendingLedger() async {
    // Only a user-provided JSON in this app's Documents is eligible. It is never bundled or fetched.
    let file = URL.documentsDirectory.appendingPathComponent("题迹导入.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return }
    do {
      let data = try Data(contentsOf: file)
      try await ledger.importData(data)
      let retained = URL.documentsDirectory.appendingPathComponent("题迹迁移备份-" + UUID().uuidString + ".json")
      try FileManager.default.moveItem(at: file, to: retained)
    } catch { ledger.message = "题迹导入未完成，两个 App 的原记录均保留：" + error.localizedDescription }
  }
}
struct LibraryScreen: View {
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  @State private var query = ""
  @State private var rating = 0
  @State private var showsDifficulty = false
  @State private var openProblem = false
  @State private var contest = ""
  @State private var index = "A"
  @State private var selected: PocketProblem?
  @State private var error: String?
  var filtered: [PocketProblem] {
    Array(model.problems.lazy.filter { (rating == 0 || $0.rating == rating) && (query.isEmpty || "\($0.id) \($0.name)".localizedCaseInsensitiveContains(query)) }.prefix(200))
  }
  var body: some View {
    List {
      Section {
        LibraryIntro(total: model.problems.count, updatedAt: model.fetchedAt)
          .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
      }
      if let message = model.libraryError { Section { StatusNotice(title: "暂未更新", message: message, symbol: "wifi.exclamationmark") } }
      Section {
        LibrarySectionHeader(rating: $rating)
        Button(showsDifficulty ? "隐藏难度" : "显示难度") { showsDifficulty.toggle() }.frame(minHeight: 44).accessibilityIdentifier("library-reveal-difficulty")
        if model.libraryBusy && model.problems.isEmpty { HStack { ProgressView(); Text("从 Codeforces 获取题库…").foregroundStyle(.secondary) } }
        if !model.libraryBusy && filtered.isEmpty { ContentUnavailableView(query.isEmpty ? "还没有题库缓存" : "没有匹配的题目", systemImage: "text.magnifyingglass", description: Text("可以刷新官方题库，或用右上角按钮直接输入题号。")) }
        ForEach(filtered) { problem in NavigationLink(value: problem) { ProblemRow(problem: problem, showsDifficulty: showsDifficulty) } }
      } footer: { if filtered.count == 200 { Text("显示前 200 条匹配项。输入题号或名称继续查找；算法标签默认隐藏，避免剧透。") } }
    }
    .listStyle(.insetGrouped).navigationTitle("题库").navigationBarTitleDisplayMode(.inline)
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "题号或题名")
    .refreshable { await model.refresh() }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { Button("输入题号", systemImage: "plus") { openProblem = true } }
      ToolbarItem(placement: .topBarTrailing) { Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.disabled(model.libraryBusy) }
    }
    .navigationDestination(for: PocketProblem.self) { WorkspaceScreen(model: WorkspaceModel(app: model, problem: $0), engine: engine) }
    .navigationDestination(item: $selected) { WorkspaceScreen(model: WorkspaceModel(app: model, problem: $0), engine: engine) }
    .sheet(isPresented: $openProblem) {
      NavigationStack {
        Form {
          Section("官方题号") { TextField("比赛 ID，例如 4", text: $contest).keyboardType(.numberPad); TextField("题目索引，例如 A、A1", text: $index).textInputAutocapitalization(.characters).autocorrectionDisabled() }
          if let error { Text(error).foregroundStyle(.red) }
          Button("打开题目") {
            do { let id = try ProblemID(contest: Int(contest) ?? 0, index: index); selected = model.problems.first(where: { $0.key == id }) ?? PocketProblem(key: id, name: id.id); openProblem = false } catch { self.error = error.localizedDescription }
          }
        }.navigationTitle("直接打开").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { openProblem = false } } }
      }.presentationDetents([.medium, .large])
    }
  }
}
struct LibraryIntro: View {
  let total: Int
  let updatedAt: Date?
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(total == 0 ? "Codeforces" : "\(total.formatted()) 道题目").font(.title2.bold())
      Spacer()
      if let updatedAt { Text(updatedAt, style: .time).font(.caption).foregroundStyle(.secondary) }
    }.padding(.vertical, 4)

  }
}
struct ProblemRow: View {
  let problem: PocketProblem
  var showsDifficulty = false
  var body: some View {
    HStack(spacing: 14) {
      Text(problem.key.index).font(.system(.title3, design: .rounded, weight: .semibold)).frame(width: 40, height: 44).foregroundStyle(PocketStyle.accent).background(PocketStyle.wash, in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 4) { Text(problem.name).font(.body.weight(.medium)).lineLimit(2); Text("CF \(problem.id)").font(.caption).foregroundStyle(.secondary) }
      Spacer(minLength: 4)
      if showsDifficulty { DifficultyBadge(title: problem.rating.map(String.init) ?? "暂无评级", rgb: DifficultyPalette.codeforces(problem.rating)) }
    }.padding(.vertical, 5).contentShape(Rectangle()).accessibilityElement(children: .combine)
  }
}
struct PracticeScreen: View {
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  @State private var favoritesOnly = false
  var body: some View {
    List {
      Section { Toggle("只看收藏", isOn: $favoritesOnly) }
      Section("保存在这台 iPhone") {
        if model.workspaces.isEmpty { ContentUnavailableView("从一道题开始", systemImage: "pencil.and.scribble", description: Text("你的代码、思路版本、运行与提交记录会在这里继续。")) }
        ForEach(model.workspaces.filter { !favoritesOnly || $0.favorite }) { workspace in
          let problem = model.problems.first(where: { $0.key == workspace.problem }) ?? PocketProblem(key: workspace.problem, name: workspace.problem.id)
          NavigationLink { WorkspaceScreen(model: WorkspaceModel(app: model, problem: problem), engine: engine) } label: {
            VStack(alignment: .leading, spacing: 6) { HStack { Text(problem.name).font(.headline); if workspace.favorite { Image(systemName: "star.fill").foregroundStyle(.orange) } }; Text("\(problem.id) · \(workspace.revisions.count) 个思路版本 · \(workspace.runs.count) 次本地运行").font(.caption).foregroundStyle(.secondary); Text(workspace.updatedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary) }
          }
        }
      }
    }.navigationTitle("继续练习")
    .safeAreaInset(edge: .bottom) { if let error = model.saveError { Text(error).font(.caption).foregroundStyle(.red).padding().background(.regularMaterial) } }
  }
}
struct StatusNotice: View {
  let title: String; let message: String; var symbol = "info.circle"
  var body: some View { VStack(alignment: .leading, spacing: 6) { Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)); Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }.padding(.vertical, 4).accessibilityElement(children: .combine) }
}

@MainActor @Observable final class PocketBootstrap {
  var model: PocketModel?
  var error: String?
  init() { retry() }
  func retry() { do { model = try PocketModel(); error = nil } catch { self.error = error.localizedDescription; model = nil } }
}

struct LibrarySectionHeader: View {
  @Binding var rating: Int
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    if typeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 12) { Text("所有题目").font(.headline); DifficultyMenu(rating: $rating) }
    } else {
      HStack { Text("所有题目").font(.headline); Spacer(); DifficultyMenu(rating: $rating) }
    }
  }
}
struct DifficultyMenu: View {
  @Binding var rating: Int
  var body: some View {
    Menu {
      Button("全部难度") { rating = 0 }
      ForEach(Array(stride(from: 800, through: 3500, by: 100)), id: \.self) { value in Button("\(value)") { rating = value } }
    } label: { Label(rating == 0 ? "难度" : String(rating), systemImage: "line.3.horizontal.decrease") }
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge).fixedSize().accessibilityLabel("筛选题目难度")
  }
}
