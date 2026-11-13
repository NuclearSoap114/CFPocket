import SwiftUI
import PocketCore
import TrainingCore

struct ProfileHome: View {
  @Bindable var model: PocketModel
  let engine: RuntimeEngine
  @Environment(TrainingStore.self) private var store
  @AppStorage("CFPocket.primaryPerson") private var personKey = ""
  @State private var editing: Person?
  @State private var dataSettings = false
  @State private var showCFLogin = false
  private var person: Person? { store.people.first { $0.id.uuidString == personKey } }
  var body: some View {
    List {
      Section {
        ProfileIdentity(person: person, count: person?.accounts.count ?? 0)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)).listRowBackground(Color.clear)
      }
      Section("训练档案") {
        if !store.people.isEmpty {
          Picker("我的档案", selection: $personKey) {
            Text("请选择本人").tag("")
            ForEach(store.people) { Text($0.displayName).tag($0.id.uuidString) }
          }
        }
        NavigationLink { PeopleManagementPage() } label: { Label("人物与关注", systemImage: "person.2") }
        if let person { Button { editing = person } label: { Label("编辑我的平台账号", systemImage: "person.crop.circle.badge.checkmark") } }
        else { Button { editing = Person(name: "") } label: { Label("建立我的档案", systemImage: "person.badge.plus") } }
        NavigationLink { SourcesPage() } label: { Label("同步与来源状态", systemImage: "arrow.triangle.2.circlepath") }
      }
      Section("Codeforces") {
        Button { showCFLogin = true } label: { Label("登录与管理 CF 账号", systemImage: "person.crop.circle.badge.checkmark") }
        Text("登录后可从做题的代码区直接提交。账号状态以官网为准。").font(.caption).foregroundStyle(.secondary)
      }
      Section("阅读与练习") {
        NavigationLink { PracticeScreen(model: model, engine: engine) } label: { Label("收藏、草稿与复盘", systemImage: "bookmark") }
        NavigationLink { SettingsScreen(model: model, engine: engine) } label: { Label("AI 与运行设置", systemImage: "slider.horizontal.3") }
      }
      Section {
        Button { dataSettings = true } label: { Label("训练数据导入与备份", systemImage: "externaldrive") }
        Text("CF Pocket · 让每一次思考留下记录")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }.navigationTitle("我的").listStyle(.insetGrouped).scrollContentBackground(.hidden).background(PocketStyle.canvas)
      .sheet(item: $editing) { PersonEditor(person: $0) }
      .sheet(isPresented: $showCFLogin) { CFLoginScreen(app: model) }
      .sheet(isPresented: $dataSettings) { DataSettingsPage() }
      .onChange(of: personKey) { _, _ in
        if let handle = person?.accounts.first(where: { $0.oj == .codeforces })?.handle { model.handle = handle; model.saveSettings() }
      }
  }
}
struct ProfileIdentity: View {
  let person: Person?
  let count: Int
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 16) {
        Text(person.map { String($0.displayName.prefix(1)) } ?? "我").font(.title2.weight(.semibold)).foregroundStyle(PocketStyle.accent)
          .frame(width: 62, height: 62).background(PocketStyle.wash, in: RoundedRectangle(cornerRadius: 20))
        VStack(alignment: .leading, spacing: 6) {
          Text(person?.displayName ?? "我的训练空间").font(.title2.bold()).foregroundStyle(PocketStyle.ink)
          Text(count == 0 ? "建立档案，连接你的训练记录" : "\(count) 个平台账号").font(.subheadline).foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 6) { Image(systemName: "externaldrive").foregroundStyle(PocketStyle.amber); Text("草稿与练习保存在这台 iPhone").foregroundStyle(.secondary) }.font(.caption)
    }.frame(maxWidth: .infinity, alignment: .leading).pocketSurface().accessibilityElement(children: .combine)
  }
}

struct PeopleManagementPage: View {
  @State private var editing: Person?
  var body: some View {
    PeoplePage().navigationTitle("人物与关注").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("添加人物", systemImage: "plus") { editing = Person(name: "") } } }
      .sheet(item: $editing) { PersonEditor(person: $0) }
  }
}
