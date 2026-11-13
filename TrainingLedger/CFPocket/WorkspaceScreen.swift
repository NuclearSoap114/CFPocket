import SwiftUI
import PocketCore

struct WorkspaceScreen: View {
  @State var model: WorkspaceModel
  let engine: RuntimeEngine
  @State private var showOfficial = false
  @State private var showNotes = false
  @State private var showSources = false
  @State private var showAISettings = false
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    VStack(spacing: 0) {
      ProblemMetadataView(model: model)
      StatementScreen(model: model, openOfficial: { showOfficial = true }, openSettings: { showAISettings = true })
    }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          if let error = model.app.saveError { Text(error).font(.caption).foregroundStyle(.red) }
          HStack(spacing: 12) {
            Button { showSources = true } label: { Label("题解", systemImage: "book.closed").frame(maxWidth: .infinity, minHeight: 32) }.buttonStyle(.bordered)
            NavigationLink { SolveScreen(model: model, engine: engine) } label: { Label("做题", systemImage: "pencil.and.scribble").frame(maxWidth: .infinity, minHeight: 32) }.buttonStyle(PocketPrimaryButton())
          }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
      }
      .toolbar(.hidden, for: .tabBar)
      .background(PocketStyle.readingPaper).navigationTitle(model.problem.id).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button(model.workspace.favorite ? "取消收藏" : "收藏", systemImage: model.workspace.favorite ? "star.fill" : "star") { model.workspace.favorite.toggle(); model.scheduleSave() }
            Button("笔记与复盘", systemImage: "note.text") { showNotes = true }
            Button("官方题面", systemImage: "link") { showOfficial = true }
            Button("AI 设置", systemImage: "slider.horizontal.3") { showAISettings = true }
            Picker("当前场景", selection: $model.workspace.mode) { ForEach(PracticeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
          } label: { Image(systemName: "ellipsis") }.accessibilityLabel("题目选项")
        }
      }
      .task { await model.load(); model.translateOnOpen() }
      .task { await model.luogu.loadMetadata() }
      .onChange(of: model.statement?.hash) { _, _ in model.translateOnOpen() }
      .onChange(of: model.app.dataGeneration) { _, _ in model.resetPrivateState() }
      .onChange(of: model.workspace.mode) { _, _ in model.aiTask?.cancel(); model.scheduleSave() }
      .onChange(of: scenePhase) { _, phase in if phase != .active { model.aiTask?.cancel(); Task { await model.flush() } } }
      .onDisappear { Task { await model.flush() } }
      .sheet(isPresented: $showOfficial) { OfficialSourceScreen(problem: model.problem.key) { html, url in Task { await model.acceptPage(html: html, url: url); showOfficial = false; model.translateOnOpen() } } }
      .sheet(isPresented: $showSources) { SourceScreen(model: model) }
      .sheet(isPresented: $showAISettings, onDismiss: { model.translateOnOpen() }) { NavigationStack { SettingsScreen(model: model.app, engine: engine).toolbar { Button("完成") { showAISettings = false } } } }
      .sheet(isPresented: $showNotes) { NavigationStack { Form { TextEditor(text: $model.workspace.notes).frame(minHeight: 250).onChange(of: model.workspace.notes) { _, _ in model.scheduleSave() } }.navigationTitle("\(model.problem.id) · 笔记").toolbar { Button("完成") { showNotes = false } } } }
  }
}
struct SolveScreen: View {
  @Bindable var model: WorkspaceModel
  let engine: RuntimeEngine
  @State private var section = 0
  @State private var showSubmission = false
  @State private var showTests = false
  var body: some View {
    VStack(spacing: 0) {
      Picker("做题方式", selection: $section) { Label("口糊", systemImage: "bubble.left").tag(0); Label("代码", systemImage: "curlybraces").tag(1) }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 10)
      if section == 0 { DraftScreen(model: model) }
      else { CodeScreen(model: model, engine: engine, openTests: { showTests = true }, openSubmission: { showSubmission = true }) }
    }
    .navigationTitle("\(model.problem.id) · 做题").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
    .background(PocketStyle.canvas)
    .sheet(isPresented: $showSubmission) { SubmissionScreen(model: model) }
    .sheet(isPresented: $showTests) { NavigationStack { TestScreen(model: model, engine: engine).navigationTitle("本地测试").toolbar { Button("完成") { showTests = false } } } }
    .onDisappear { Task { await model.flush() } }
  }
}
enum ReadingLanguage: String, CaseIterable { case original = "原文", chinese = "中文", bilingual = "双语" }
struct StatementScreen: View {
  @Bindable var model: WorkspaceModel
  let openOfficial: () -> Void
  let openSettings: () -> Void
  @State private var language: ReadingLanguage = .chinese
  var body: some View {
    VStack(spacing: 0) {
      if let statement = model.statement {
        HStack {
          Text(model.problem.name).font(.subheadline.weight(.semibold)).lineLimit(2)
          Spacer(minLength: 12)
          Menu {
            Picker("题面语言", selection: $language) { ForEach(ReadingLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Button("重新翻译") { translate() }.disabled(model.aiBusy)
            Button("官方原文", action: openOfficial)
          } label: { Label(language.rawValue, systemImage: "globe").font(.subheadline).frame(minHeight: 44) }.accessibilityLabel("题面语言，\(language.rawValue)")
        }.padding(.horizontal, 20).padding(.vertical, 4)
        Divider()
        if model.aiBusy { HStack { ProgressView(); Text(model.activeIntent == .translation ? "正在翻译题面…" : "正在生成回复…").font(.caption); Spacer(); Button("停止") { model.aiTask?.cancel() } }.padding(.horizontal, 20).padding(.vertical, 10) }
        if let error = model.aiError { Text(error).font(.footnote).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08)) }
        InlineTranslatedReader(statement: statement, translation: model.canReadMaterials ? model.readingRecord(.translation)?.response.translatedText : nil,
          explanation: nil, language: language, allowed: model.canReadMaterials,
          generate: translate, busy: model.aiBusy, hasKey: KeychainKey.exists)
      } else if model.busy {
        ProgressView("正在读取题面…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView { Label("暂时未取得题面", systemImage: "doc.text.magnifyingglass") } description: { Text(model.sourceError ?? "可在官方网页完成站点验证，然后读取题面。") } actions: {
          Button("打开官方题面", action: openOfficial).buttonStyle(PocketPrimaryButton())
          Button("重试") { Task { await model.refreshStatement(); model.translateOnOpen() } }
        }
      }
    }
  }
  func translate() { if KeychainKey.exists { model.generate(.translation) } else { openSettings() } }
}
struct InlineTranslatedReader: View {
  let statement: Statement
  let translation: String?
  let explanation: String?
  let language: ReadingLanguage
  let allowed: Bool
  let generate: () -> Void
  let busy: Bool
  var hasKey = true
  @State private var rendered: String?
  @State private var error: String?
  private var key: String { fingerprint(statement.html + (translation ?? "") + (explanation ?? "") + language.rawValue) }
  var body: some View {
    Group {
      if !allowed && language != .original {
        ScrollView { ContentUnavailableView("当前仅开放原文阅读", systemImage: "shield.lefthalf.filled", description: Text("比赛状态未知、正在比赛或虚拟训练期间，AI 回复与缓存提示保持隐藏。")) }
      } else if translation == nil && language != .original {
        ScrollView { ContentUnavailableView { Label(busy ? "正在翻译题面" : "中文题面", systemImage: "character.book.closed") } description: {
          Text(busy ? "首次打开需要一点时间，译文会保存在本题。也可以从右上角先看原文。" : hasKey ? "自动翻译尚未完成。可以重试，或从右上角切换原文。" : "首次使用请配置 AI。之后打开题目会自动翻译为中文，使用你设置的额度；原文随时可看。")
        } actions: { if !busy { Button(hasKey ? "重试翻译" : "配置 AI", action: generate).buttonStyle(PocketPrimaryButton()) } } }
      } else if let rendered {
        FragmentReader(html: rendered, source: statement.source, readingKey: language.rawValue)
      } else if let error { ContentUnavailableView("阅读内容暂时无法显示", systemImage: "doc.text", description: Text(error)) }
      else { ProgressView("正在排版…").frame(maxWidth: .infinity, maxHeight: .infinity) }
    }.task(id: key) {
      error = nil
      do {
        let statement = statement, translation = translation, explanation = explanation, language = language
        rendered = try await Task.detached(priority: .userInitiated) {
          var result = language == .original ? statement.html : ""
          if let translation, language != .original {
            if language == .bilingual { result += "<h2>原文</h2>" + statement.html + "<hr><h2>中文译文</h2>" }
            result += try PocketMarkdown.html(translation, source: statement.source)
            if !statement.samples.isEmpty {
              result += "<h2>样例 · 与原文一致</h2>"
              for (index, sample) in statement.samples.enumerated() {
                result += "<h3>输入 \(index + 1)</h3><pre>" + PocketMarkdown.escape(sample.input) + "</pre><h3>输出 \(index + 1)</h3><pre>" + PocketMarkdown.escape(sample.output) + "</pre>"
              }
            }
            result += "<p class=\"reader-note\">AI 翻译 · 题意以官方原文为准</p>"
          }
          if let explanation { result += "<hr><h2>题意解释</h2>" + (try PocketMarkdown.html(explanation, source: statement.source)) }
          return result
        }.value
      } catch { self.error = error.localizedDescription }
    }
  }
}
struct DraftScreen: View {
  @Bindable var model: WorkspaceModel
  @FocusState private var editing: Bool
  @State private var visibleCount = 8
  private var input: Binding<String> { Binding(get: { model.workspace.chatDraft ?? "" }, set: { model.workspace.chatDraft = $0; model.scheduleSave() }) }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 26) {
          if model.discussionRecords.isEmpty && model.pendingQuestion == nil {
            VStack(alignment: .leading, spacing: 16) {
              Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 30, weight: .light)).foregroundStyle(PocketStyle.accent).padding(18).background(PocketStyle.wash, in: RoundedRectangle(cornerRadius: 22))
              Text("把想法说出来").font(.title2.bold()).foregroundStyle(PocketStyle.ink)
              Text("一起推导，或直接问解法。").font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 28).padding(.bottom, 20)
          }
          if model.discussionRecords.count > visibleCount { Button("更早的对话") { visibleCount += 8 }.font(.footnote) }
          if model.canReadMaterials {
            ForEach(model.discussionRecords.suffix(visibleCount)) { record in
              if let question = model.workspace.revisions.first(where: { $0.number == record.draftRevision })?.text {
                UserQuestionBubble(text: question)
              }
              AIAnswerView(record: record, source: model.problem.key.url)
            }
          }
          if let question = model.pendingQuestion { UserQuestionBubble(text: question) }
          if model.aiBusy && model.activeIntent == .coach { HStack(spacing: 10) { ProgressView(); Text("正在思考…").font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 8) }
          if !model.aiBusy && (model.aiError != nil || model.pendingQuestion != nil) {
            VStack(alignment: .leading, spacing: 8) {
              Text(model.aiError ?? "上次提问尚未完成，可以继续重试。").font(.footnote).foregroundStyle(.secondary)
              if model.pendingQuestion != nil { Button("重试") { model.retryQuestion() }.font(.subheadline.weight(.semibold)) }
            }
          }
          Color.clear.frame(height: 1).id("conversation-bottom")
        }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
      }.scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          HStack(alignment: .bottom, spacing: 10) {
            TextField("写下思路，或直接提问…", text: input, axis: .vertical)
              .lineLimit(1...6).font(.body).focused($editing).padding(.vertical, 12).padding(.leading, 16)
              .accessibilityLabel("口糊与提问")
            if model.aiBusy {
              Button { model.aiTask?.cancel() } label: { Image(systemName: "stop.fill").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44).foregroundStyle(.white).background(PocketStyle.action, in: Circle()) }.accessibilityLabel("停止回答")
            } else {
              Button { editing = false; model.sendQuestion() } label: { Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44).foregroundStyle(.white).background(PocketStyle.action, in: Circle()) }
                .accessibilityLabel("发送提问").accessibilityHint("发送当前输入，使用已配置的 AI 额度")
                .opacity((model.workspace.chatDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.38 : 1)
                .disabled((model.workspace.chatDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }.padding(6).background(PocketStyle.paper, in: RoundedRectangle(cornerRadius: 27)).overlay { RoundedRectangle(cornerRadius: 27).strokeBorder(PocketStyle.line) }
            .padding(.horizontal, 16).padding(.vertical, 10).background(PocketStyle.canvas)
        }
        .onChange(of: model.discussionRecords.count) { _, _ in proxy.scrollTo("conversation-bottom", anchor: .bottom) }
        .onChange(of: model.pendingQuestion) { _, _ in proxy.scrollTo("conversation-bottom", anchor: .bottom) }
        .task { model.prepareComposer() }
    }.background(PocketStyle.canvas)
      .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { editing = false } } }
  }
}
struct UserQuestionBubble: View {
  let text: String
  var body: some View {
    HStack { Spacer(minLength: 28); Text(text).font(.body).textSelection(.enabled).padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(PocketStyle.ink).background(PocketStyle.wash, in: RoundedRectangle(cornerRadius: 19)) }
  }
}
struct AIAnswerView: View {
  let record: TutorRecord
  let source: URL
  @State private var details = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        Image(systemName: "sparkle").font(.system(size: 15, weight: .medium)).foregroundStyle(PocketStyle.accent).frame(width: 28, height: 28).background(PocketStyle.wash, in: Circle())
        Text("思路助手").font(.caption.weight(.semibold)).foregroundStyle(PocketStyle.accent)
        Spacer()
        Menu {
          Button("复制回复", systemImage: "doc.on.doc") { UIPasteboard.general.string = PocketMarkdown.normalized(record.response.translatedText ?? record.response.feedback) }
          Button("依据与版本", systemImage: "info.circle") { details = true }
        } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: 44) }.accessibilityLabel("回复选项")
      }
      EmbeddedMarkdown(text: record.response.translatedText ?? record.response.feedback, source: source)
      if let example = record.response.counterexample {
        DisclosureGroup("反例建议 · 尚未运行") { Text("输入：\(example.input)\n推测输出：\(example.userOutput)\n参考输出：\(example.correctOutput)\n\(example.basis)").font(.footnote).textSelection(.enabled) }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .sheet(isPresented: $details) {
        NavigationStack { List {
          Section { Label(record.officialMaterialRead ? "参考了已核验官方材料" : "基于题面独立推导", systemImage: "doc.text"); Text("AI 分析未实际运行代码，结果需通过测试核实。").font(.footnote).foregroundStyle(.secondary) }
          if !record.response.restatement.isEmpty { Section("对你的思路的理解") { Text(record.response.restatement) } }
          if !record.response.missingOrAssumed.isEmpty { Section("缺失或假设") { ForEach(record.response.missingOrAssumed, id: \.self) { Text($0) } } }
          Section("回复记录") { LabeledContent("模型", value: record.model); LabeledContent("草稿版本", value: String(record.draftRevision)); Text(record.createdAt, style: .date) }
        }.navigationTitle("回复依据").toolbar { Button("完成") { details = false } } }
      }
  }
}
struct AIResponseSection: View {
  @Bindable var model: WorkspaceModel
  var intents: [TutorIntent] = [.nextHint, .independent, .compare]
  var body: some View {
    if model.aiBusy { HStack { ProgressView(); Text("正在整理解答…").font(.subheadline).foregroundStyle(.secondary); Spacer(); Button("停止") { model.aiTask?.cancel() } } }
    if let error = model.aiError { Text(error).font(.footnote).foregroundStyle(.secondary) }
    if model.canReadMaterials, let record = model.latestAIRecord(intents: intents) { AIAnswerView(record: record, source: model.problem.key.url) }
    else if !model.canReadMaterials { Text("请在赛后练习中查看 AI 解答。").font(.footnote).foregroundStyle(.secondary) }
  }
}
struct SourceScreen: View {
  @State private var luoguSelected = true
  @Bindable var model: WorkspaceModel
  @Environment(\.dismiss) private var dismiss
  @State private var showAI: Bool
  @State private var showHint = false
  init(model: WorkspaceModel) {
    self.model = model
    _showAI = State(initialValue: model.latestAIRecord(intents: [.answer, .independent]) != nil)
  }
  func chineseAnswer(force: Bool = false) {
    showAI = true; showHint = false
    if force || model.latestAIRecord(intents: [.answer, .independent]) == nil { model.generate(.answer) }
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ProblemMetadataView(model: model)
        Picker("题解来源", selection: $luoguSelected) { Text("洛谷题解").tag(true); Text("官方 / AI").tag(false) }.pickerStyle(.segmented).padding()
        if luoguSelected {
          if model.canReadMaterials { LuoguSolutionsPane(model: model.luogu) }
          else { ContentUnavailableView("当前练习模式不开放题解", systemImage: "shield.lefthalf.filled", description: Text("请在比赛结束后的普通练习中查看。")) }
        } else {
        VStack(alignment: .leading, spacing: 8) {
          Text(model.problem.name).font(.headline).lineLimit(3)
          HStack {
            Text(model.editorial?.isUsable == true ? "本题官方题解" : "本题解答").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("中文解答", systemImage: "sparkles") { chineseAnswer() }.font(.subheadline).frame(minHeight: 44).disabled(model.aiBusy)
            Menu {
              Button("给一点提示") { showAI = true; showHint = true; model.generate(.nextHint) }.disabled(model.aiBusy)
              if model.editorial?.isUsable == true { Button(showAI ? "查看官方原文" : "查看 AI 解答") { showAI.toggle() } }
              Button("重新生成中文解答") { chineseAnswer(force: true) }.disabled(model.aiBusy)
              Button("刷新官方题解") { Task { await model.fetchEditorial() } }.disabled(model.busy)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("题解选项")
          }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }.padding(.horizontal, 20).padding(.vertical, 12)
        Divider()
        if !model.canReadMaterials { ContentUnavailableView("当前练习模式不开放题解", systemImage: "shield.lefthalf.filled", description: Text("请在比赛结束后的普通练习中查看。")) }
        else if showAI { ScrollView { VStack(alignment: .leading, spacing: 16) { AIResponseSection(model: model, intents: showHint ? [.nextHint] : [.answer, .independent]); if !model.aiBusy && model.latestAIRecord(intents: [.answer, .nextHint, .independent]) == nil && model.aiError == nil { Button("生成中文完整解答") { model.generate(.answer) }.buttonStyle(PocketPrimaryButton()) } }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity) }.background(PocketStyle.readingPaper) }
        else if let editorial = model.editorial, editorial.isUsable { FragmentReader(html: editorial.content, source: editorial.source) }
        else if model.busy { ProgressView("正在获取本题题解…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        else {
          ScrollView { ContentUnavailableView { Label("官方题解暂不可用", systemImage: "book.closed") } description: { Text(model.sourceError ?? "可以直接生成中文解答，按本题单独保存。AI 推导会明确标注来源。") } actions: { Button("生成中文解答") { chineseAnswer() }.buttonStyle(PocketPrimaryButton()); Button("重试官方题解") { Task { await model.fetchEditorial() } } } }
        }
        }
      }.navigationTitle("\(model.problem.id) · 题解").navigationBarTitleDisplayMode(.inline).toolbar { Button("完成") { dismiss() } }
        .task(id: luoguSelected) { if !luoguSelected && !showAI && model.editorial?.isUsable != true && model.canReadMaterials { await model.fetchEditorial() } }
    }
  }
}
