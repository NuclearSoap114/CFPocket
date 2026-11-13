import SwiftUI
import PocketCore

struct CodeScreen: View {
  @Bindable var model: WorkspaceModel
  let engine: RuntimeEngine
  let openTests: () -> Void
  let openSubmission: () -> Void
  @State private var editor = EditorControl()
  @State private var replaceTemplate = false
  @State private var templateSaved = false
  @State private var pendingTemplate: String?
  @State private var pendingMultiple = false
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("语言", selection: $model.workspace.language) { ForEach(CodeLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.menu).fixedSize(horizontal: true, vertical: false).frame(minWidth: 88, alignment: .leading).onChange(of: model.workspace.language) { _, _ in model.scheduleSave() }
        Spacer()
        Button("撤销", systemImage: "arrow.uturn.backward") { editor.undo() }.labelStyle(.iconOnly).font(.system(size: 18, weight: .medium)).frame(minWidth: 44, minHeight: 44)
        Button("重做", systemImage: "arrow.uturn.forward") { editor.redo() }.labelStyle(.iconOnly).font(.system(size: 18, weight: .medium)).frame(minWidth: 44, minHeight: 44)
        Button("查找替换", systemImage: "magnifyingglass") { editor.find() }.labelStyle(.iconOnly).font(.system(size: 18, weight: .medium)).frame(minWidth: 44, minHeight: 44)
        Button("模板") { requestTemplate(custom: UserDefaults.standard.string(forKey: templateKey)) }.font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44).accessibilityLabel("一键模板")
        Menu {
          Button("单组测试模板") { requestTemplate(multiple: false) }
          Button("多组测试模板") { requestTemplate(multiple: true) }
          Button("保存为我的模板") { UserDefaults.standard.set(model.source, forKey: templateKey); templateSaved = true }
          Button("使用我的模板") { requestTemplate(custom: UserDefaults.standard.string(forKey: templateKey)) }.disabled(UserDefaults.standard.string(forKey: templateKey) == nil)
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("模板选项")

      }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal).padding(.vertical, 9)
      CodeEditor(text: Binding(get: { model.source }, set: { model.source = $0 }), control: editor, python: model.workspace.language == .python)
      if let result = model.workspace.runs.last, result.status == "compile-error", let line = diagnosticLine(result.stderr) { Button("编译错误 · 跳到第 \(line) 行") { editor.jump(line: line) }.font(.caption).padding(8) }
      CodeActionBar(saveStatus: model.app.saveError == nil ? (model.savePending ? "正在保存…" : "已保存在本机") : "保存失败，请查看错误", saveFailed: model.app.saveError != nil, openTests: openTests, openSubmission: openSubmission)

    }
    .alert("用模板替换当前代码？", isPresented: $replaceTemplate) {
      Button("取消", role: .cancel) {}
      Button("替换", role: .destructive) { editor.replaceTemplate(pendingTemplate, multiple: pendingMultiple) }
    } message: { Text("原代码可以通过编辑器的撤销按钮恢复。") }
    .alert("模板已保存在本机", isPresented: $templateSaved) { Button("好", role: .cancel) {} }
  }
  private var templateKey: String { "CFPocket.template.\(model.workspace.language.rawValue)" }
  private func requestTemplate(custom: String? = nil, multiple: Bool = false) {
    pendingTemplate = custom; pendingMultiple = multiple
    let initial = Workspace(problem: model.problem.key)
    let untouched = model.source == (model.workspace.language == .python ? initial.python : initial.cpp)
    if model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || untouched { editor.replaceTemplate(custom, multiple: multiple) }
    else { replaceTemplate = true }
  }

}
func diagnosticLine(_ text: String) -> Int? {
  guard let re = try? NSRegularExpression(pattern: #"main\.cc:(\d+):\d+:"#), let m = re.firstMatch(in: text, range: NSRange(location: 0,length: (text as NSString).length)) else { return nil }; return Int((text as NSString).substring(with: m.range(at:1)))
}
struct TestScreen: View {
  @Bindable var model: WorkspaceModel
  @Bindable var engine: RuntimeEngine
  @State private var batchTask: Task<Void,Never>?
  @State private var liveBatchID: UUID?
  @State private var batchIndex = 0
  @State private var batchTotal = 0
  @State private var selectedRunID: UUID?
  @State private var showInput = false
  @FocusState private var inputFocused: Bool
  private var specialJudge: Bool { model.statement?.requiresSpecialJudge ?? true }
  private var samples: [Sample] { model.statement?.samples ?? [] }
  private var resultRuns: [LocalRun] {
    if let liveBatchID { return model.workspace.runs.filter { $0.batchID == liveBatchID } }
    guard let last = model.workspace.runs.last else { return [] }
    if let batch = last.batchID { return model.workspace.runs.filter { $0.batchID == batch } }
    return [last]
  }
  private var active: Bool { engine.running || batchTask != nil }
  var body: some View {
    ScrollViewReader { proxy in
    List {
      if active {
        Section {
          HStack(spacing: 16) {
            ProgressView().controlSize(.large)
            VStack(alignment: .leading, spacing: 6) {
              Text(batchTotal > 0 ? "样例 \(batchIndex) / \(batchTotal)" : "正在运行").font(.title3.bold())
              Text(engine.phase).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button("停止", role: .destructive) { batchTask?.cancel(); engine.stop() }.frame(minHeight: 44)
          }.padding(.vertical, 12)
        }.id("running-result")
      }
      if !resultRuns.isEmpty && (!active || liveBatchID != nil) {
        Section {
          if let first = resultRuns.first, let total = first.batchSize {
            if !active {
              let verdict = ResultVerdict.batch(resultRuns, total: total, specialJudge: specialJudge)
              VerdictCard(verdict: verdict, scope: "本地样例 · \(resultRuns.count) / \(total) 已运行",
                          detail: verdict.code == "AC" ? "全部 \(total) 个样例通过" : verdict.title)
            }
            ScrollView(.horizontal) {
              HStack(spacing: 10) {
                ForEach(resultRuns) { run in
                  let result = ResultVerdict.local(run, specialJudge: specialJudge)
                  Button {
                    selectedRunID = run.id
                  } label: {
                    VStack(spacing: 8) {
                      Text("样例 \(run.sampleNumber ?? 1)").font(.subheadline)
                      VerdictBadge(verdict: result)
                    }.padding(12).background(PocketStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                      .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selectedRun?.id == run.id ? result.color : .clear, lineWidth: 2) }
                  }.buttonStyle(.plain).accessibilityLabel("样例 \(run.sampleNumber ?? 1)，\(result.code)")
                    .accessibilityAddTraits(selectedRun?.id == run.id ? .isSelected : [])
                }
              }.padding(2)
            }.scrollIndicators(.hidden)
            if let selectedRun { RunResultView(run: selectedRun, specialJudge: specialJudge, showVerdict: false).id(selectedRun.id) }
          } else if let result = resultRuns.last {
            RunResultView(run: result, specialJudge: specialJudge).id(result.id)
          }
        }.listRowSeparator(.hidden).id("finished-result")
      }
      Section {
        if !samples.isEmpty {
          Button("运行全部样例", systemImage: "play.fill") { runBatch(samples) }
            .buttonStyle(PocketPrimaryButton()).disabled(active || !engine.ready).padding(.vertical, 4)
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                Button("样例 \(index + 1)") {
                  model.workspace.stdin = sample.input; model.workspace.expected = sample.output
                  model.scheduleSave(); run(sampleNumber: index + 1)
                }.buttonStyle(.bordered).controlSize(.large).disabled(active || !engine.ready)
              }
            }
          }.scrollIndicators(.hidden)
        }
        if !engine.ready { ProgressView("准备本地运行环境") }
        if let failure = engine.failure { Text(failure).font(.body).foregroundStyle(.red) }
      }
      Section {
        DisclosureGroup("自定义输入与期望输出", isExpanded: $showInput) {
          Text("标准输入").font(.subheadline).foregroundStyle(.secondary)
          TextEditor(text: $model.workspace.stdin).font(.system(.body, design: .monospaced)).frame(minHeight: 120)
            .focused($inputFocused)
            .accessibilityLabel("标准输入").onChange(of: model.workspace.stdin) { _, _ in model.scheduleSave() }
          Text("期望输出（可选）").font(.subheadline).foregroundStyle(.secondary)
          TextEditor(text: $model.workspace.expected).font(.system(.body, design: .monospaced)).frame(minHeight: 80)
            .focused($inputFocused)
            .accessibilityLabel("期望输出").onChange(of: model.workspace.expected) { _, _ in model.scheduleSave() }
        }
        Button("在本机运行", systemImage: "play") { run() }.disabled(active || !engine.ready).frame(minHeight: 44)
      }
      if !model.workspace.runs.isEmpty {
        Section {
          DisclosureGroup("运行历史 · \(model.workspace.runs.count) 次") {
            ForEach(model.workspace.runs.reversed().prefix(20)) { result in
              DisclosureGroup {
                RunResultView(run: result, specialJudge: specialJudge)
              } label: {
                HStack {
                  VerdictBadge(verdict: .local(result, specialJudge: specialJudge))
                  Text(result.startedAt.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
              }
            }
          }
        }
      }
      Section {
        DisclosureGroup("本地运行环境") {
          Text(model.workspace.language == .cpp ? "Clang 22 / libc++，与 CF 的 GNU 环境不同，不支持 PBDS。" : "离线 CPython / Pyodide 标准库子集，不支持原生扩展和子进程。")
          Text("执行时限 2 秒，编译时限 30 秒，输出上限 64 KB。切到后台会停止。")
        }.font(.subheadline).foregroundStyle(.secondary)
      }
    }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(PocketStyle.canvas)
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: active) { _, running in proxy.scrollTo(running ? "running-result" : "finished-result", anchor: .top) }
      .onDisappear { batchTask?.cancel(); engine.stop(reason: "已离开测试页，运行停止。") }
    }
  }
  private var selectedRun: LocalRun? {
    resultRuns.first { $0.id == selectedRunID }
      ?? resultRuns.first { ResultVerdict.local($0, specialJudge: specialJudge).tone == .failure }
      ?? resultRuns.last
  }
  func run(sampleNumber: Int? = nil) {
    inputFocused = false
    liveBatchID = nil; batchTotal = 0; selectedRunID = nil
    let revision = CodeRevision(source: model.source, language: model.workspace.language)
    engine.completion = { result in
      var run = result; run.sampleNumber = sampleNumber
      model.workspace.runs.append(run); model.scheduleSave()
    }
    engine.run(revision: revision, input: model.workspace.stdin, expected: model.workspace.expected.isEmpty && sampleNumber == nil ? nil : model.workspace.expected)
  }
  func runBatch(_ samples: [Sample]) {
    inputFocused = false
    let revision = CodeRevision(source: model.source, language: model.workspace.language)
    let id = UUID(); liveBatchID = id; batchTotal = samples.count; selectedRunID = nil
    batchTask = Task {
      defer { batchTask = nil }
      for (index, sample) in samples.enumerated() {
        guard !Task.isCancelled else { return }
        batchIndex = index + 1
        engine.completion = { result in
          var run = result; run.batchID = id; run.batchSize = samples.count; run.sampleNumber = index + 1
          model.workspace.runs.append(run); model.scheduleSave()
        }
        engine.run(revision: revision, input: sample.input, expected: sample.output)
        while engine.running {
          do { try await Task.sleep(for: .milliseconds(100)) } catch { engine.stop(); return }
        }
        guard engine.failure == nil, engine.result?.status != "stopped" else { return }
      }
    }
  }
}

struct CodeActionBar: View {
  let saveStatus: String
  let saveFailed: Bool
  let openTests: () -> Void
  let openSubmission: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(spacing: 6) {
      HStack {
        if !typeSize.isAccessibilitySize { Text(saveStatus).font(.caption).foregroundStyle(saveFailed ? Color.red : Color.secondary); Spacer() }
        Button("测试", systemImage: "play.fill", action: openTests).buttonStyle(PocketPrimaryButton())
        Button("提交", systemImage: "paperplane", action: openSubmission).buttonStyle(.bordered)
        if typeSize.isAccessibilitySize { Spacer() }
      }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      if typeSize.isAccessibilitySize { Text(saveStatus).font(.caption).foregroundStyle(saveFailed ? Color.red : Color.secondary).frame(maxWidth: .infinity, alignment: .leading) }
    }.padding(12).background(.bar)
  }
}
