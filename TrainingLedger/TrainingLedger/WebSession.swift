import SwiftUI
import TrainingCore
import WebKit

@MainActor @Observable final class WebSession {
  let webView: WKWebView
  private var generation = 0
  init() {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    webView = WKWebView(frame: .zero, configuration: config)
    webView.allowsBackForwardNavigationGestures = true
  }
  func open(_ url: URL) {
    generation += 1
    webView.load(URLRequest(url: url))
  }
  func cancel() {
    generation += 1
    webView.stopLoading()
  }
  func load(_ url: URL, account: OJAccount, metadata: Bool = false) async throws -> String {
    generation += 1
    let taskGeneration = generation
    guard url.scheme == "https", url.host == account.recordsURL.host else {
      throw TrainingError.invalid("网页连接不能跳转到其他来源。")
    }
    webView.load(
      URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    for _ in 0..<60 {
      try Task.checkCancellation()
      guard generation == taskGeneration else { throw CancellationError() }
      try await Task.sleep(for: .milliseconds(500))
      guard webView.url?.host == url.host else { continue }
      let script = """
        (()=>{ const t=document.body?.innerText||''; const oj=\(String(reflecting:account.oj.rawValue));
        let ok=false;
        if(\(metadata ? "true":"false"))ok=!!document.querySelector('h2') && document.querySelector('h2').innerText.trim().length>0;
        else if(oj==='luogu'){try{ok=Array.isArray(JSON.parse(document.querySelector('#lentille-context')?.textContent||'{}').data?.records?.result)}catch(e){ok=false}}
        else if(oj==='vjudge')ok=t.trim().startsWith('{') && t.includes('recordsFiltered');
        else if(oj==='qoj')ok=!!document.querySelector('table time[datetime]') || /No submissions|No Submission/.test(t);
        else if(oj==='hydro')ok=!!document.querySelector('tr[data-rid]') || /目前没有符合过滤条件的任务|No records match/.test(t);
        else if(oj==='nowcoder')ok=!!document.querySelector('a[href*="submissionId="]') || /暂无提交记录|暂无数据|暂时没有/.test(t);
        return ok ? document.documentElement.outerHTML : ''; })()
        """
      if let html = try? await webView.evaluateJavaScript(script) as? String, !html.isEmpty {
        return html
      }
    }
    throw TrainingError.needsBrowser("\(account.oj.name)需要连接网页。请打开账号的“网页连接”，完成登录或安全校验，再继续采集。")
  }
}
struct WebHost: UIViewRepresentable {
  let session: WebSession
  var hidesWebAccessibility = false
  func makeUIView(context: Context) -> WKWebView {
    session.webView.accessibilityElementsHidden = hidesWebAccessibility
    return session.webView
  }
  func updateUIView(_ view: WKWebView, context: Context) {
    view.accessibilityElementsHidden = hidesWebAccessibility
  }
}
struct WebConnectionPage: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let account: OJAccount
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          Text("\(account.oj.name) · \(account.handle)").font(.headline)
          Text("完成登录或页面校验后，点“继续采集”。登录状态仅保存在此手机的网页连接中。").font(.footnote).foregroundStyle(
            Theme.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
        WebHost(session: store.web)
      }.navigationTitle("网页连接").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("继续采集") {
              store.connectDone(account)
              dismiss()
            }
          }
        }
    }
  }
}
