import SwiftUI
import TrainingCore

@main struct TrainingLedgerApp: App {
  @State private var store = TrainingStore()
  var body: some Scene {
    WindowGroup {
      root.tint(Theme.accent).environment(store)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .environment(\.timeZone, TrainingDates.calendar.timeZone).task { await store.start() }
    }
  }
  @ViewBuilder private var root: some View {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--mapping-review") {
        NavigationStack { MappingPage() }
      } else if ProcessInfo.processInfo.arguments.contains("--insights-review") {
        NavigationStack { TrainingInsightsPage() }
      } else if ProcessInfo.processInfo.arguments.contains("--submission-review") {
        NavigationStack { SubmissionChartReview() }
      } else if ProcessInfo.processInfo.arguments.contains("--cf-review") {
        NavigationStack { PlatformTrainingPage(oj: .codeforces) }
      } else {
        TrainingRoot()
      }
    #else
      TrainingRoot()
    #endif
  }
}
struct TrainingRoot: View {
  @Environment(TrainingStore.self) private var store
  @State private var showSettings = false
  @State private var editing: Person?
  var body: some View {
    @Bindable var store = store
    TabView {
      NavigationStack {
        PeoplePage().navigationTitle("题迹").toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              showSettings = true
            } label: {
              Image(systemName: "slider.horizontal.3")
            }.accessibilityLabel("设置与数据")
          }
          ToolbarItemGroup(placement: .topBarTrailing) {
            SyncButton()
            Button {
              editing = Person(name: "")
            } label: {
              Image(systemName: "plus")
            }.accessibilityLabel("添加人物")
          }
        }
      }.tabItem { Label("人物", systemImage: "person.2.fill") }
      NavigationStack {
        PlatformsPage().navigationTitle("OJ 训练").toolbar {
          ToolbarItem(placement: .topBarTrailing) { SyncButton() }
        }
      }.tabItem { Label("OJ", systemImage: "square.grid.2x2.fill") }
      NavigationStack {
        TrainingInsightsPage().toolbar {
          ToolbarItem(placement: .topBarTrailing) { SyncButton() }
        }
      }.tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
    }.tint(Theme.accent)
      .background {
        if store.connection == nil {
          WebHost(session: store.web, hidesWebAccessibility: true).frame(width: 390, height: 800)
            .offset(x: -1000, y: -1000).opacity(0.01).accessibilityHidden(
              true)
        }
      }
      .sheet(isPresented: $showSettings) { DataSettingsPage() }
      .sheet(item: $editing) { p in PersonEditor(person: p) }
      .sheet(item: $store.connection) { a in WebConnectionPage(account: a) }
      .alert(
        "提示",
        isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })
      ) {
        Button("知道了") { store.message = nil }
      } message: {
        Text(store.message ?? "")
      }
  }
}
