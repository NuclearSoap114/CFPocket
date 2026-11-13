import SwiftUI
import PocketCore
import UniformTypeIdentifiers

struct SettingsScreen: View {
  @Bindable var model: PocketModel
  @Bindable var engine: RuntimeEngine
  @State private var key = ""
  @State private var hasKey = KeychainKey.exists
  @State private var status: String?
  @State private var clearData = false
  @State private var probing = false
  @State private var export = false
  @State private var document = PocketJSONDocument(data:Data())
  var body: some View {
    Form {
      Section {
        HStack(spacing:14) { Image(systemName:"curlybraces.square.fill").font(.largeTitle).foregroundStyle(Color.accentColor);VStack(alignment:.leading,spacing:5){Text("CF Pocket").font(.title2.bold());Text("阅读、思考与练习 · 0.6").font(.caption).foregroundStyle(.secondary)} }
      }
      Section("公开 CF 数据") { TextField("你的 handle（不是登录）",text:$model.handle).autocorrectionDisabled().textInputAutocapitalization(.never);Text("公开 handle 用于查询记录；登录账号在“我的 → CF 账号”管理。").font(.caption).foregroundStyle(.secondary) }
      Section("DeepSeek · 你自己的 Key") {
        Label(hasKey ? "已安全存入 Keychain" : "尚未配置，AI 不会发送请求",systemImage:hasKey ? "key.fill" : "key")
        SecureField("输入新 API Key",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled()
        Button("保存 Key") { do{try KeychainKey.save(key.trimmingCharacters(in:.whitespacesAndNewlines));key="";hasKey=KeychainKey.exists;status="已安全保存。"}catch{status=error.localizedDescription} }.disabled(key.isEmpty)
        if hasKey { Button("删除本机 Key",role:.destructive){try? KeychainKey.save("");hasKey=false} }
        Text("中文题面会自动翻译；提问与题解按你的操作生成，使用这个 Key 的额度。Key 只保存在本机。").font(.caption).foregroundStyle(.secondary)
      }
      Section("模型与预算") {
        TextField("常规模型",text:$model.configuration.fast).textInputAutocapitalization(.never).autocorrectionDisabled()
        TextField("深度模型",text:$model.configuration.reasoning).textInputAutocapitalization(.never).autocorrectionDisabled()
        Toggle("使用深度模型",isOn:$model.configuration.useReasoningModel)
        HStack{Text("每日预算（美元）");TextField("0.50",value:$model.configuration.dailyBudgetUSD,format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)}
        Stepper("单次输出上限 \(model.configuration.maxOutputTokens) tokens",value:$model.configuration.maxOutputTokens,in:500...8000,step:500)
        Text("按高峰、非缓存价格保守预留预算；中断或失败的请求不自动退款，也不自动重试。价格核验于 2026-11-12，公开发行前仍需复核。模型名称集中配置。").font(.caption).foregroundStyle(.secondary)
        DisclosureGroup("当前预算估算费率 / 百万 tokens") { Text("Flash 输入 $0.30 / 输出 $1.20；Pro 输入 $1.32 / 输出 $3.96。不以低谷或缓存折扣保证成本。").font(.caption) }
      }
      Section("运行与诊断") {
        DisclosureGroup("本地运行环境") {
        Text("C++20 / C++17：Clang 与 LLD 22.1.8 在 WASM 内运行；WASI libc++。bits/stdc++.h 是 App 的兼容聚合头，GNU PBDS、线程与异常不兼容。").font(.footnote)
        Text("Python：Pyodide 314.0.7，实际解释器版本见自检。标准库随包安装；不联网安装包。每次运行新 Worker，文件与全局变量不跨任务保存。").font(.footnote)
        Text("C++ 用户程序内存上限 256 MiB、栈 1 MiB。工具链和 Python/WebKit 总体内存没有宣称同等硬限制；进程被系统终止时显示资源错误。每次执行 2 秒、输出 64 KB；进入后台停止。").font(.caption).foregroundStyle(.secondary)
        Button(probing ? "自检正在真实运行…" : "运行本地环境自检") { probing=true;Task{await RuntimeProbe.run(engine:engine);probing=false;status="自检结束，结果保存在 App 的 Documents/runtime-probe.json。"} }.disabled(probing || engine.running || !engine.ready)
      }
        }
      Section("数据与隐私") {
        Toggle("保存后续 AI 回复到练习记录", isOn: $model.keepAIHistory)
        Text("关闭后仅在当前页面暂存后续回复；已有历史可导出后通过删除私人记录彻底清除。代码与算法草稿仍会自动保存。").font(.caption).foregroundStyle(.secondary)
        Text("公共题面缓存与个人草稿分开保存，均不自动上传。离线可读已缓存题面、编辑并本地运行。题面图片目前仍按官方地址读取，图片离线缓存尚未完成。").font(.footnote)
        Button("导出个人练习记录 JSON",systemImage:"square.and.arrow.up") { Task{do{let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; document=PocketJSONDocument(data:try encoder.encode(await model.storage.allWorkspaces()));export=true}catch{status=error.localizedDescription}} }
        Button("删除本机私人记录与 AI 缓存",role:.destructive){clearData=true}

      }
      if let status { Section{Text(status).font(.footnote)} }
    }.navigationTitle("AI 与运行设置").navigationBarTitleDisplayMode(.inline).scrollContentBackground(.hidden).background(PocketStyle.canvas)
    .onDisappear{model.saveSettings()}
    .confirmationDialog("删除题单进度、代码、草稿、笔记、运行和提交记录？建议先导出，删除不能撤销。",isPresented:$clearData,titleVisibility:.visible){Button("删除私人记录",role:.destructive){Task{do{try await model.storage.clearPrivate();model.dataGeneration = await model.storage.currentEpoch();model.workspaces=[];await model.plans.didClearPrivate();status="已删除本机私人记录与 AI 缓存。"}catch{status=error.localizedDescription}}}}
    .fileExporter(isPresented:$export,document:document,contentType:.json,defaultFilename:"CFPocket-private-records"){result in if case .failure(let error)=result{status=error.localizedDescription}}
  }
}
struct PocketJSONDocument: FileDocument {
  static var readableContentTypes:[UTType]{[.json]}
  var data:Data
  init(data:Data){self.data=data}
  init(configuration:ReadConfiguration)throws{data=configuration.file.regularFileContents ?? Data()}
  func fileWrapper(configuration:WriteConfiguration)throws->FileWrapper{FileWrapper(regularFileWithContents:data)}
}
