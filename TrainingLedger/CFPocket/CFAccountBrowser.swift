import SwiftUI
import WebKit
import PocketCore

struct CFWebLanguage: Identifiable { let id: String; let name: String }

@MainActor @Observable final class CFAccountBrowser: NSObject, WKNavigationDelegate {
  let web: WKWebView
  var handle = ""
  var languages: [CFWebLanguage] = []
  var hasForm = false
  var loading = false
  var message: String?
  var readinessError: String?
  private let target: URL
  private let problem: ProblemID?
  private var inspecting = false
  private var navigationEpoch = 0
  private var resumedAfterLogin = false
  private var started = false
  init(url: URL, problem: ProblemID? = nil) {
    target = url
    self.problem = problem
    let config = WKWebViewConfiguration(); config.websiteDataStore = .default()
    web = WKWebView(frame: .zero, configuration: config)
    super.init()
    web.navigationDelegate = self; web.allowsBackForwardNavigationGestures = true
  }
  func start() { guard !started else { return }; started = true; web.load(URLRequest(url: target)) }
  func open(_ url: URL) { started = true; resumedAfterLogin = url.path != "/enter" && url.path != target.path; web.load(URLRequest(url: url)) }
  func prepareSubmission() { resumedAfterLogin = false; open(target) }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { navigationEpoch += 1; loading = true; hasForm = false; languages = []; message = nil; readinessError = nil }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; Task { await inspect() } }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false; message = "网页加载失败，可以重试。" }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading = false; message = "暂时无法连接 Codeforces，请检查网络后重试。" }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
    guard let url = action.request.url else { decisionHandler(.cancel); return }
    // Challenges may use a Cloudflare subframe. App scripts still require the exact CF origin.
    if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
    guard url.scheme == "https", url.host == "codeforces.com" else { decisionHandler(.cancel); return }
    if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) } else { decisionHandler(.allow) }
  }
  func inspect() async {
    guard web.url?.host == "codeforces.com", web.url?.scheme == "https", !loading, !inspecting else { return }
    inspecting = true
    let epoch = navigationEpoch
    defer { inspecting = false }
    do {
      guard let result = try await web.evaluateJavaScript(CFWebForm.snapshot(problem: problem)) as? [String: Any], epoch == navigationEpoch, !loading else { return }
      handle = result["handle"] as? String ?? ""
      hasForm = result["form"] as? Bool ?? false
      languages = (result["languages"] as? [[String: String]] ?? []).compactMap { x in guard let id = x["id"], let name = x["name"] else { return nil }; return CFWebLanguage(id:id, name:name) }
      readinessError = result["readinessError"] as? String
      let errors = result["errors"] as? String ?? ""
      message = !errors.isEmpty ? errors : (problem != nil ? readinessError.map(CFWebForm.failureMessage) : nil)
      if hasForm && !handle.isEmpty { resumedAfterLogin = true }
      if !handle.isEmpty, result["formPresent"] as? Bool != true, web.url?.path != target.path,
         readinessError != "VERIFICATION_REQUIRED", target.path.contains("submit"), !resumedAfterLogin {
        resumedAfterLogin = true; web.load(URLRequest(url: target))
      }
    } catch {
      if epoch == navigationEpoch { hasForm = false; languages = []; readinessError = "FORM_LOADING" }
    }
  }
  func submit(_ attempt: SubmissionAttempt, language: String) async throws -> [String: Any] {
    guard !loading else { return ["error":"FORM_LOADING"] }
    let script = try CFWebForm.submit(problem: attempt.problem, source: attempt.revision.source, languageID: language, handle: attempt.handle, nonce: attempt.id)
    return try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any] ?? [:]
  }
  func receipt(_ attempt: SubmissionAttempt) async throws -> Int? {
    let result = try await web.callAsyncJavaScript(CFWebForm.receipt(attempt), arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
    return result?["sourceVerified"] as? Bool == true ? result?["id"] as? Int : nil
  }
}
struct CFAccountWebView: UIViewRepresentable {
  let browser: CFAccountBrowser
  func makeUIView(context: Context) -> WKWebView { browser.web }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
struct CFLoginScreen: View {
  @Bindable var app: PocketModel
  @State private var browser = CFAccountBrowser(url: URL(string:"https://codeforces.com/enter")!)
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack { Label(browser.handle.isEmpty ? "在官网安全登录" : "已登录 @\(browser.handle)", systemImage:"lock.shield"); Spacer(); if browser.loading { ProgressView() } }.font(.subheadline).padding()
        if let message = browser.message { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
        CFAccountWebView(browser:browser)
      }.navigationTitle("Codeforces 账号").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.topBarLeading) { Button("刷新",systemImage:"arrow.clockwise") { browser.web.reload() } }; ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } }
        .task {
          browser.start()
          while !Task.isCancelled {
            await browser.inspect()
            if !browser.handle.isEmpty { app.handle = browser.handle; app.saveSettings() }
            do { try await Task.sleep(for:.seconds(3)) } catch { break }
          }
        }
    }
  }
}
