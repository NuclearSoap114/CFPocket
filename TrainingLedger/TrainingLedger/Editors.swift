import SwiftUI
import TrainingCore
import UniformTypeIdentifiers

struct PersonEditor: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var person: Person
  init(person: Person) { _person = State(initialValue: person) }
  @State private var error: String?
  @State private var saving = false
  @State private var confirmDelete = false
  private var existing: Bool { store.person(person.id) != nil }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("真名（可选）", text: $person.realName)
          TextField("训练昵称（可选）", text: $person.name)
          Toggle("收藏并置顶", isOn: $person.favorite)
        } header: {
          Text("人物资料")
        } footer: {
          Text("优先显示真名；未填写时显示训练昵称。平台 ID 单独保存，不会从用户名猜真名。")
        }
        Section {
          ForEach($person.accounts) { $a in
            VStack(alignment: .leading, spacing: 10) {
              Picker("OJ", selection: $a.oj) { ForEach(OJ.allCases) { Text($0.name).tag($0) } }
              TextField(a.oj.hint, text: $a.handle).textInputAutocapitalization(.never)
                .autocorrectionDisabled().keyboardType(
                  a.oj == .luogu || a.oj == .nowcoder ? .numberPad : .asciiCapable)
              TextField("平台昵称（可选，便于辨认）", text: $a.platformName)
                .autocorrectionDisabled()
              if a.oj == .hydro {
                TextField("站点，例如 https://hydro.ac", text: $a.site).textInputAutocapitalization(
                  .never
                ).autocorrectionDisabled().keyboardType(.URL)
                Text("可填写学校的 Hydro 地址和 /d/域名前缀；留空使用 hydro.ac。").font(.caption).foregroundStyle(Theme.secondaryText)
              }
              Button("移除此账号", role: .destructive) {
                let id = a.id
                person.accounts.removeAll { $0.id == id }
              }
              .font(.caption)
            }.padding(.vertical, 5)
          }
          Button {
            person.accounts.append(
              OJAccount(
                oj: OJ.allCases.first(where: { oj in !person.accounts.contains { $0.oj == oj } })
                  ?? .codeforces, handle: ""))
          } label: {
            Label("添加 OJ 账号", systemImage: "plus.circle")
          }
        } header: {
          Text("OJ 账号")
        } footer: {
          Text("保存用户 ID，不需要密码。同一人物可以绑定不同 OJ，也可以绑定同一 OJ 的多个账号。修改或移除账号会清除该绑定的旧记录，其他账号不受影响。")
        }
        if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline) } }
        if existing {
          Section { Button("删除人物及其本地记录", role: .destructive) { confirmDelete = true } }
        }
      }.navigationTitle(existing ? "编辑人物" : "添加人物").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(saving ? "保存中…" : "保存") { save() }.disabled(saving)
          }
        }
        .confirmationDialog(
          "删除此人物及其本地训练记录？", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
          Button("删除人物", role: .destructive) {
            Task {
              do {
                try await store.removePerson(person.id)
                dismiss()
              } catch { self.error = error.localizedDescription }
            }
          }
          Button("取消", role: .cancel) {}
        } message: {
          Text("如需保留，请先在设置中导出备份。平台上的账号和提交不会被修改。")
        }
    }
  }
  private func save() {
    saving = true
    error = nil
    Task {
      do {
        person.name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        person.realName = person.realName.trimmingCharacters(in: .whitespacesAndNewlines)
        try await store.savePerson(person)
        dismiss()
      } catch { self.error = error.localizedDescription }
      saving = false
    }
  }
}
struct ArchiveDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
struct DataSettingsPage: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var exporting = false
  @State private var importing = false
  @State private var document = ArchiveDocument(data: Data())
  @State private var message: String?
  @State private var processing = false
  @AppStorage("autoRefresh") private var autoRefresh = true
  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("已保存人物", value: String(store.people.count))
          LabeledContent("已保存提交", value: String(store.archive.submissions.count))
          Button(processing ? "正在准备备份…" : "导出完整 JSON 备份") {
            processing = true
            Task {
              do {
                document = ArchiveDocument(data: try await store.exportData())
                exporting = true
              } catch { message = error.localizedDescription }
              processing = false
            }
          }.disabled(processing)
          Button("导入 JSON（校验并合并）") { importing = true }.disabled(processing)
          LabeledContent("数据格式", value: "v\(store.archive.version).\(store.archive.schemaMinor)")
          LabeledContent("本地修订", value: String(store.archive.revision))
        } header: {Text("本地数据")} footer: {
          Text("导出包含已填写的真名和平台ID，请自行保管。支持旧版数据迁移；导入不会用旧备份覆盖本机较新的提交状态。")
        }
        Section("管理") {
          NavigationLink("人物与账号映射") { MappingPage() }
          NavigationLink("来源状态与连接") { SourcesPage() }
        }

        Section("统计口径") {
          Text(
            "热力图按北京时间的自然日统计。提交次数包含未通过提交；通过题数是在当前筛选内按 OJ＋站点＋题号去重后的当天通过题目数，多个账号重复通过同一题也不重复计题。不同 OJ 的同名题目保持各自来源，不擅自合并。"
          )
          Text("人物收藏后置顶；OJ 页面可开启收藏优先。历史只来自实际采集或用户导入，登录校验失败不会清空已保存的记录。")
          Text(
            "AtCoder 来自 AtCoder Problems 的第三方收录，难度为其模型估计原值；各 OJ 难度体系独立，不作等值换算。Hydro 默认收集指定域中当前可见的非比赛记录，权限内不可见的记录无法推断。"
          )
          Text("题目难度缺失时明确标注。部分站点需要在本手机网页连接中完成登录或安全校验。")
        }.font(.footnote)
        Section("刷新") {
          Toggle("启动时自动同步", isOn: $autoRefresh)
          Text("打开 App 后同步；可手动刷新或下拉刷新。同步按平台限速，支持停止并保留已采集页面。App 退到后台时 iOS 可能暂停任务，不保证锁屏定时运行。").font(
            .footnote)
        }
        Section("题迹 1.2 · 本地开发版") {
          Text("SwiftUI 原生界面 · iOS 27 SDK\n无服务器、广告或分析追踪。数据保存在这台设备上。").font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        }
      }.navigationTitle("设置与数据").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
      }
    }
    .fileExporter(
      isPresented: $exporting, document: document, contentType: .json,
      defaultFilename: "题迹备份-" + TrainingDates.text(Date(), format: "yyyy-MM-dd")
    ) { result in if case .failure(let error) = result { message = error.localizedDescription } }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      Task {
        do {
          let url = try result.get()
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }
            .value
          try await store.importData(data)
          message = "导入完成，重复提交已按原始记录ID合并。"
        } catch { message = "导入失败，原数据保留：" + error.localizedDescription }
      }
    }.alert(
      "数据管理", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    ) {
      Button("知道了") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

}
