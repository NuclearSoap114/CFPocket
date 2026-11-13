import SwiftUI
import PocketCore

struct SubmissionScreen: View {
  @Bindable var model: WorkspaceModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var browser: CFAccountBrowser
  @State private var language = ""
  @State private var currentID: UUID?
  @State private var busy = false
  @State private var checking = false
  @State private var submissionErrors: [UUID: String] = [:]
  @State private var showHistory = false
  @State private var showOfficial = false
  @State private var returnAfterLogin = false
  @State private var manualID = ""
  @State private var confirmRetry = false
  private var current: SubmissionAttempt? { model.workspace.submissions.first { $0.id == currentID } }
  private var pending: Bool { current.map { [.sending, .uncertain, .tracking, .judging, .networkFailure].contains($0.state) } ?? false }
  private var submitURL: URL { model.app.submitter.officialURL(problem: model.problem.key) }
  init(model: WorkspaceModel) {
    self.model = model
    _browser = State(initialValue: CFAccountBrowser(url: model.app.submitter.officialURL(problem: model.problem.key), problem: model.problem.key))
    let attempt = model.workspace.submissions.last(where: { [.sending, .uncertain, .tracking, .judging, .networkFailure].contains($0.state) }) ?? model.workspace.submissions.last
    _currentID = State(initialValue: attempt?.id)
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if !showOfficial {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              HStack {
                Text(model.problem.id).font(.title2.bold())
                Spacer()
                if !browser.handle.isEmpty { Text("@\(browser.handle)").font(.subheadline).foregroundStyle(.secondary) }
              }
              if let current {
                OfficialResultView(attempt: current).pocketSurface()
                if pending {
                  HStack(spacing: 12) {
                    ProgressView()
                    Text(current.submissionID == nil ? "正在核对提交记录，请勿重复发送。" : "官方判题中，结果会自动更新。")
                      .font(.subheadline).foregroundStyle(.secondary)
                  }
                  if current.submissionID == nil {
                    // Successful submission normally navigates to a status page without a form.
                    if let message = browser.message, browser.readinessError != "FORM_MISSING" {
                      Text(message).font(.subheadline).foregroundStyle(PocketStyle.amber)
                    }
                    Button("登录或完成官网验证", systemImage: "lock.shield") { openOfficial() }.buttonStyle(.bordered)
                    Button("恢复结果核对") { showHistory = true }.font(.subheadline)
                  }
                } else if current.state == .final {
                  HStack {
                    Button("继续修改", systemImage: "curlybraces") { dismiss() }.buttonStyle(PocketPrimaryButton())
                    Button("提交新版本") { prepareNew() }.buttonStyle(.bordered)
                  }
                  if current.submissionID != nil {
                    Button(checking ? "正在更新结果…" : "更新官方结果", systemImage: "arrow.clockwise") {
                      if let id = current.submissionID { Task { await reconcile(current, id: id) } }
                    }.disabled(checking).font(.subheadline).frame(minHeight: 44)
                  }
                }
              }
              if !pending && current?.state != .final { preparation.pocketSurface() }
              if current?.state == .final {
                Button("查看官网详情", systemImage: "globe") {
                  if let current, let id = current.submissionID { openOfficial(url: recordURL(current, id)) }
                }.font(.subheadline).frame(minHeight: 44)
              }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
          }.background(PocketStyle.canvas)
        } else {
          HStack {
            Text("官网登录与验证在此完成").font(.subheadline)
            Spacer()
            if browser.loading { ProgressView() }
            Button("刷新", systemImage: "arrow.clockwise") { browser.web.reload() }.labelStyle(.iconOnly).frame(width: 44, height: 44)
          }.padding(.horizontal)
        }
        // One persistent WebView owns the authenticated form and receipt across both presentations.
        // A compact host keeps the session alive without putting webpage content in the result UI.
        CFAccountWebView(browser: browser)
          .frame(maxWidth: .infinity, maxHeight: showOfficial ? .infinity : 1)
          .opacity(showOfficial ? 1 : 0).allowsHitTesting(showOfficial).accessibilityHidden(!showOfficial)
      }.navigationTitle(showOfficial ? "Codeforces 官网" : "提交与结果").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            if showOfficial { Button("返回结果", systemImage: "chevron.left") { showOfficial = false; returnAfterLogin = false } }
            else { Button("记录", systemImage: "clock.arrow.circlepath") { showHistory = true } }
          }
          ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
        }
        .task {
          if current?.submissionID == nil { browser.start() }
          while !Task.isCancelled {
            if scenePhase == .active {
              await browser.inspect(); chooseLanguage()
              if !browser.handle.isEmpty { model.app.handle = browser.handle; model.app.saveSettings() }
              if returnAfterLogin, browser.hasForm, !browser.handle.isEmpty {
                showOfficial = false; returnAfterLogin = false
              }
              if !busy, !checking, let attempt = current, pending {
                if let id = attempt.submissionID { await reconcile(attempt, id: id) }
                else if let id = try? await browser.receipt(attempt) {
                  var verified = attempt; verified.sourceVerified = true; verified.submissionID = id; verified.state = .tracking
                  verified.note = "已核对官网源码，正在读取判题结果。"
                  if let i = model.workspace.submissions.firstIndex(where: { $0.id == verified.id }) {
                    model.workspace.submissions[i] = verified; await model.flush()
                  }
                }
              }
            }
            do { try await Task.sleep(for: .seconds(5)) } catch { break }
          }
        }
        .sheet(isPresented: $showHistory) { history }
    }
  }
  private var preparation: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !browser.handle.isEmpty {
        Label("已登录 @\(browser.handle)", systemImage: "checkmark.shield").font(.headline)
      }
      if browser.hasForm && !browser.handle.isEmpty {
        Picker("提交语言", selection: $language) { ForEach(availableLanguages) { Text($0.name).tag($0.id) } }
          .pickerStyle(.menu).disabled(busy)
        Button("提交当前代码", systemImage: "paperplane.fill") { send() }
          .buttonStyle(PocketPrimaryButton()).disabled(busy || browser.loading || language.isEmpty || model.source.isEmpty)
        Text("\(model.workspace.language.rawValue) · \(model.source.count) 字符").font(.subheadline).foregroundStyle(.secondary)
      } else if browser.loading {
        ProgressView("正在连接 Codeforces…").padding(.vertical, 12)
        Button("查看连接页面") { openOfficial() }.frame(minHeight: 44)
      } else {
        if browser.handle.isEmpty { Label("登录后即可提交", systemImage: "lock.shield").font(.headline) }
        else { Text("提交页面尚未就绪").font(.headline) }
        Button(browser.handle.isEmpty ? "登录 Codeforces" : "打开官网检查") {
          returnAfterLogin = true
          openOfficial(url: browser.handle.isEmpty ? URL(string: "https://codeforces.com/enter")! : submitURL)
        }.buttonStyle(PocketPrimaryButton())
      }
      if let error = current.flatMap({ submissionErrors[$0.id] }) ?? browser.message {
        Text(error).font(.subheadline).foregroundStyle(PocketStyle.amber)
      }
      if !browser.loading && (!browser.handle.isEmpty || current?.state == .notSent) {
        HStack {
          Button("重新准备提交", systemImage: "arrow.clockwise") {
            if let current { submissionErrors[current.id] = nil }
            browser.prepareSubmission()
          }
          .disabled(busy).frame(minHeight: 44)
          if browser.hasForm {
            Button("官网检查", systemImage: "globe") { openOfficial() }.frame(minHeight: 44)
          }
        }.font(.subheadline)
      }
    }
  }
  private func prepareNew() {
    guard !pending && !busy else { return }
    currentID = nil; browser.prepareSubmission()
  }
  private func openOfficial(url: URL? = nil) {
    if let url { browser.open(url) } else { browser.start() }
    showOfficial = true
  }
  private func recordURL(_ attempt: SubmissionAttempt, _ id: Int) -> URL {
    URL(string: "https://codeforces.com/contest/\(attempt.problem.contest)/submission/\(id)")!
  }
  private var availableLanguages: [CFWebLanguage] {
    browser.languages.filter {
      let name = $0.name.lowercased()
      return model.workspace.language == .cpp ? name.contains("c++") || name.contains("g++") || name.contains("clang") : name.contains("python") || name.contains("pypy")
    }
  }
  private func chooseLanguage() {
    guard !availableLanguages.contains(where: { $0.id == language }) else { return }
    language = availableLanguages.first(where: { model.workspace.language == .cpp ? ($0.name.contains("C++20") || $0.name.contains("G++20")) : $0.name.contains("PyPy 3") })?.id ?? availableLanguages.first?.id ?? ""
  }
  private func send() {
    guard !busy, !pending, browser.hasForm, !browser.loading, !browser.handle.isEmpty, !language.isEmpty else { return }
    busy = true
    let selectedLanguage = language
    let revision = CodeRevision(source: model.source, language: model.workspace.language)
    var attempt = SubmissionAttempt(problem: model.problem.key, revision: revision, handle: browser.handle)
    attempt.state = .sending; attempt.language = availableLanguages.first(where: { $0.id == language })?.name
    attempt.note = "正在通过官网提交；请勿重复发送。"
    currentID = attempt.id; model.workspace.submissions.append(attempt)
    Task {
      await model.flush()
      guard model.app.saveError == nil else {
        update(attempt, state: .notSent, note: "本地记录保存失败，代码没有发送。")
        submissionErrors[attempt.id] = "本地记录未保存，代码没有发送。请返回检查存储状态后再试。"
        busy = false; return
      }
      do {
        let result = try await browser.submit(attempt, language: selectedLanguage)
        if let reason = result["error"] as? String {
          let detail = "\(friendly(reason))（\(reason)）"
          update(attempt, state: .notSent, note: "代码未发送：\(detail)"); submissionErrors[attempt.id] = friendly(reason)
          await browser.inspect()
        } else {
          update(attempt, state: .uncertain, note: "已触发官网提交，正在核对新记录与代码；不会自动重发。若需要登录或验证，可打开内嵌官网。")
        }
      } catch { update(attempt, state: .uncertain, note: "网页跳转或网络中断，发送结果尚未确认。请查看官网记录，应用不会重复提交。") }
      await model.flush(); busy = false
    }
  }
  private func update(_ attempt: SubmissionAttempt, state: SubmissionState, note: String) {
    guard let i = model.workspace.submissions.firstIndex(where: { $0.id == attempt.id }) else { return }
    var value = attempt; value.state = state; value.note = note; model.workspace.submissions[i] = value; model.scheduleSave()
  }
  private func reconcile(_ attempt: SubmissionAttempt, id: Int) async {
    guard !checking else { return }; checking = true; defer { checking = false }
    do {
      let updated = try await model.app.submitter.reconcile(attempt, submissionID: id)
      if let i = model.workspace.submissions.firstIndex(where: { $0.id == attempt.id }) { model.workspace.submissions[i] = updated; await model.flush() }
      submissionErrors[attempt.id] = nil
    } catch { submissionErrors[attempt.id] = "暂时未取得最新结果，已有提交记录保留，可稍后重试。" }
  }
  private func friendly(_ error: String) -> String {
    CFWebForm.failureMessage(error)
  }
  private var history: some View {
    NavigationStack {
      List {
        if let current, pending {
          Section("恢复结果核对") {
            Text("填写官网提交 ID 即可继续读取结果，不会重发代码。")
            TextField("官网提交 ID", text: $manualID).keyboardType(.numberPad)
            Button("关联并读取结果") { if let id = Int(manualID) { Task { await reconcile(current, id: id); showHistory = false } } }
              .disabled((Int(manualID) ?? 0) <= 0 || checking)
            Button("确认官网没有收到，重新准备") { confirmRetry = true }
          }
        }
        Section("本题提交") {
          if model.workspace.submissions.isEmpty { Text("还没有提交记录") }
          ForEach(model.workspace.submissions.reversed()) { attempt in
            NavigationLink {
              ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                  OfficialResultView(attempt: model.workspace.submissions.first { $0.id == attempt.id } ?? attempt).pocketSurface()
                  if let id = attempt.submissionID {
                    Button("更新官方结果", systemImage: "arrow.clockwise") { Task { await reconcile(attempt, id: id) } }.disabled(checking)
                    Button("查看官网详情", systemImage: "globe") { showHistory = false; openOfficial(url: recordURL(attempt, id)) }
                  }
                  if let error = submissionErrors[attempt.id] { Text(error).foregroundStyle(PocketStyle.amber) }
                }.padding(20)
              }.background(PocketStyle.canvas).navigationTitle("提交结果").navigationBarTitleDisplayMode(.inline)
            } label: {
              HStack(spacing: 14) {
                VerdictBadge(verdict: .official(attempt))
                VStack(alignment: .leading, spacing: 5) {
                  Text(attempt.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                  Text(attempt.submissionID.map { "#\(String($0)) · @\(attempt.handle)" } ?? ResultVerdict.official(attempt).title)
                    .font(.subheadline).foregroundStyle(.secondary)
                }
              }.padding(.vertical, 4)
            }
          }
        }
      }.navigationTitle("本题提交记录").toolbar { Button("完成") { showHistory = false } }
        .confirmationDialog("仅在核对官网确定没有收到后继续。重新准备不会自动提交。", isPresented: $confirmRetry, titleVisibility: .visible) {
          Button("已确认没有收到") {
            if let current {
              update(current, state: .notSent, note: "用户核对官网后确认没有收到，允许重新准备。")
              currentID = nil; browser.prepareSubmission(); showHistory = false
            }
          }
        }
    }
  }
}
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }
