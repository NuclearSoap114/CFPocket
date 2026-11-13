import SwiftUI
import WebKit
import SafariServices
import PocketCore

final class ReaderAssets: NSObject, WKURLSchemeHandler {
  var html = ""
  func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
    guard let url = task.request.url, !url.path.contains("..") else { return }
    let data: Data; let type: String
    if url.path == "/index.html" { data = Data(html.utf8); type = "text/html" }
    else {
      let path = String(url.path.dropFirst())
      guard let root = Bundle.main.url(forResource: "Reader", withExtension: nil), let bytes = try? Data(contentsOf: root.appendingPathComponent(path)) else { task.didFailWithError(URLError(.fileDoesNotExist)); return }
      data = bytes
      switch url.pathExtension { case "js":type = "text/javascript";case "css":type = "text/css";case "woff2":type = "font/woff2";case "woff":type = "font/woff";default:type = "application/octet-stream" }
    }
    let response = URLResponse(url:url,mimeType:type,expectedContentLength:data.count,textEncodingName:type.hasPrefix("text/") ? "utf-8" : nil)
    task.didReceive(response);task.didReceive(data);task.didFinish()
  }
  func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
struct FragmentReader: UIViewRepresentable {
  let html: String
  let source: URL
  var readingKey: String = "document"
  var measuredHeight: Binding<CGFloat>? = nil
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.userContentController.add(context.coordinator, name: "readerHeight"); config.userContentController.add(context.coordinator, name: "readerCopy"); config.setURLSchemeHandler(context.coordinator.assets, forURLScheme:"pocket-reader")
    let view = WKWebView(frame:.zero,configuration:config);view.navigationDelegate = context.coordinator;view.isOpaque = false;view.backgroundColor = .systemBackground;view.scrollView.backgroundColor = .systemBackground; return view
  }
  func updateUIView(_ view: WKWebView, context: Context) {
    context.coordinator.measuredHeight = measuredHeight
    view.scrollView.isScrollEnabled = measuredHeight == nil
    let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
    let size = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize
    let key = readingKey + source.absoluteString + fingerprint(html) + "\(colorScheme)\(dynamicTypeSize)\(size)"
    guard key != context.coordinator.key else { return }
    if !context.coordinator.key.isEmpty { context.coordinator.positions[context.coordinator.readingKey] = view.scrollView.contentOffset.y }
    context.coordinator.key = key; context.coordinator.readingKey = readingKey
    let dark = colorScheme == .dark
    let embedded = measuredHeight != nil
    view.backgroundColor = embedded ? .clear : UIColor(PocketStyle.readingPaper)
    view.scrollView.backgroundColor = view.backgroundColor
    // Only the app's own local scripts execute. No original CF scripts, styles, events, forms or frames survive parsing.
    let content = """
    <!doctype html><html lang="zh-Hans" data-theme="\(dark ? "dark" : "light")"><head><meta charset="utf-8"><meta name="referrer" content="no-referrer"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src pocket-reader:; style-src pocket-reader: 'unsafe-inline'; font-src pocket-reader:; img-src https:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'">
    <link rel="stylesheet" href="katex.min.css"><style>
    :root{color-scheme:\(dark ? "dark" : "light");--ink:\(dark ? "#edf1ef" : "#202d32");--muted:\(dark ? "#a9b7b8" : "#586a6e");--accent:\(dark ? "#80d8c8" : "#11675c");--line:\(dark ? "#344348" : "#dce5df");--code:\(dark ? "#0c161c" : "#172c34");--wash:\(dark ? "#1e2c31" : "#edf2ee")}
    *{box-sizing:border-box}body{max-width:760px;margin-left:auto;margin-right:auto;font-family:-apple-system,system-ui;font-size:\(size)px;line-height:1.75;margin:0;padding:\(embedded ? "0 0 4px" : "22px 22px 36px");background:\(embedded ? "transparent" : dark ? "#121e23" : "#fafbf8");color:var(--ink);overflow-wrap:anywhere;-webkit-text-size-adjust:100%}
    h1,h2,h3,h4,.title{line-height:1.4;font-weight:700;letter-spacing:-.025em}h1,.title{font-size:1.4em;margin:0 0 1em}h2{font-size:1.15em;margin:1.8em 0 .65em;padding-top:.2em}h3,h4{font-size:1em;margin:1.35em 0 .5em}p{margin:.7em 0 1em}body>:first-child{margin-top:0}.header{text-align:left;margin-bottom:1.4em}.property-title{display:inline;color:var(--muted)}strong{font-weight:700;color:var(--ink)}ul,ol{padding-left:1.45em;margin:.7em 0 1em}li{margin:.45em 0}li::marker{color:var(--accent);font-weight:600}
    pre{position:relative;white-space:pre;overflow-x:auto;border-radius:0 0 14px 14px;padding:16px;margin:0 0 1.35em;background:var(--code);color:#edf6f2;font:.86em/1.65 ui-monospace,Menlo,monospace;-webkit-overflow-scrolling:touch}pre code{padding:0;background:none;color:inherit;font:inherit}code{font-family:ui-monospace,Menlo,monospace;font-size:.88em;padding:.12em .35em;background:var(--wash);border-radius:5px;color:var(--accent)}.code-tools{display:flex;align-items:center;justify-content:space-between;padding:4px 8px 4px 16px;border-radius:14px 14px 0 0;background:var(--code);border-bottom:1px solid #ffffff20;color:#b0c7ca;font:600 .72em/1.5 -apple-system,system-ui;letter-spacing:.04em}.code-tools button{font:inherit;color:#bde8df;background:transparent;border:0;min-width:60px;min-height:44px;border-radius:8px}.code-tools button:focus-visible{outline:2px solid #80d8c8}
    img{max-width:100%;height:auto}table{display:block;width:100%;overflow-x:auto;border-collapse:collapse;margin:1.2em 0;font-size:.9em}td,th{border:1px solid var(--line);padding:10px 12px;text-align:left;min-width:72px}th{background:var(--wash);font-weight:650}a{color:var(--accent)}blockquote{margin:1.2em 0;padding:4px 14px;border-left:3px solid var(--accent);background:var(--wash);border-radius:0 8px 8px 0;color:var(--muted)}.katex-display{overflow:auto;padding:8px 0}.reader-note{font-size:.8em;color:var(--muted)}hr{border:0;border-top:1px solid var(--line);margin:26px 0}.spoiler-title{font-weight:600}.spoiler-content{display:block!important}
    </style><link rel="stylesheet" href="code-theme.css"><script src="code-highlight.js" defer></script><script src="katex.min.js" defer></script><script src="auto-render.min.js" defer></script><script src="render.js" defer></script></head><body>\(html)</body></html>
    """
    context.coordinator.assets.html = content;view.load(URLRequest(url:URL(string:"pocket-reader://document/index.html")!))
  }
  @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let assets = ReaderAssets();var key = ""
    var readingKey = "document"
    var positions: [String: CGFloat] = [:]
    var measuredHeight: Binding<CGFloat>?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "pocket-reader" else { return }
      if message.name == "readerHeight", let height = message.body as? Double, height.isFinite, let measuredHeight {
        let value = min(100_000, max(40, height))
        if abs(measuredHeight.wrappedValue - value) > 1 { measuredHeight.wrappedValue = value }
      } else if message.name == "readerCopy", let text = message.body as? String, text.utf8.count <= 262_144 {
        UIPasteboard.general.string = text
      }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      if measuredHeight == nil {
        let y = positions[readingKey] ?? 0
        webView.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
      }
    }
    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy)->Void) {
      guard let url = action.request.url else { decisionHandler(.cancel);return }
      if url.scheme == "pocket-reader" { decisionHandler(.allow) }
      else { if action.navigationType == .linkActivated, url.scheme == "https", ["codeforces.com", "www.luogu.com.cn"].contains(url.host ?? "") { UIApplication.shared.open(url) };decisionHandler(.cancel) }
    }
  }
}
struct OfficialSourceScreen: View {
  let problem: ProblemID
  let accept: (String,URL)->Void
  @Environment(\.dismiss) private var dismiss
  @State private var browser = OfficialBrowserControl()
  var body: some View {
    NavigationStack {
      VStack(spacing:0) {
        Text("官方网页验证步骤。请本人完成验证或登录；App 不读取 Cookie 或密码。看到完整题面后再点击“读取题面”。").font(.caption).foregroundStyle(.secondary).padding(12)
        OfficialBrowser(control:browser,url:problem.url)
        if let error = browser.error { Text(error).font(.caption).foregroundStyle(.red).padding(8) }
      }.navigationTitle("Codeforces 官方网页").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement:.cancellationAction){Button("关闭"){dismiss()}}
        ToolbarItem(placement:.confirmationAction){Button("读取题面") { browser.capture(problem:problem,accept:accept) }}
      }
    }
  }
}
@MainActor @Observable final class OfficialBrowserControl {
  weak var view: WKWebView?
  var error: String?
  func capture(problem:ProblemID,accept:@escaping(String,URL)->Void) {
    guard let view, let url = view.url, url.scheme == "https", url.host == "codeforces.com", url.path == problem.url.path || url.path == "/problemset/problem/\(problem.contest)/\(problem.index)" else { error = "请先回到这道题的官方题面页面。";return }
    view.evaluateJavaScript("document.documentElement.outerHTML") { value,error in
      Task { @MainActor in
        guard error == nil, let html = value as? String, html.utf8.count < 5_000_000 else { self.error = "当前页面无法读取，或页面过大。";return }
        accept(html,url)
      }
    }
  }
}
struct OfficialBrowser: UIViewRepresentable {
  let control:OfficialBrowserControl;let url:URL
  func makeUIView(context:Context)->WKWebView { let config=WKWebViewConfiguration();config.websiteDataStore = .default();let view=WKWebView(frame:.zero,configuration:config);control.view=view;view.load(URLRequest(url:url));return view }
  func updateUIView(_ view:WKWebView,context:Context){}
}
struct OfficialSafari: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context:Context)->SFSafariViewController{SFSafariViewController(url:url)}
  func updateUIViewController(_ controller:SFSafariViewController,context:Context){}
}

struct EmbeddedMarkdown: View {
  let text: String
  let source: URL
  @State private var html = ""
  @State private var height: CGFloat = 80
  @State private var error: String?
  var body: some View {
    Group {
      if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
      else { FragmentReader(html: html, source: source, measuredHeight: $height).frame(height: height) }
    }.task(id: text) {
      do { html = try PocketMarkdown.html(text, source: source); error = nil }
      catch { self.error = "这段回复暂时无法排版，请通过回复菜单复制原文。" }
    }
  }
}
private extension UIContentSizeCategory {
  init(_ value: DynamicTypeSize) {
    switch value {
    case .xSmall: self = .extraSmall
    case .small: self = .small
    case .medium: self = .medium
    case .large: self = .large
    case .xLarge: self = .extraLarge
    case .xxLarge: self = .extraExtraLarge
    case .xxxLarge: self = .extraExtraExtraLarge
    case .accessibility1: self = .accessibilityMedium
    case .accessibility2: self = .accessibilityLarge
    case .accessibility3: self = .accessibilityExtraLarge
    case .accessibility4: self = .accessibilityExtraExtraLarge
    default: self = .accessibilityExtraExtraExtraLarge
    }
  }
}

/// The website session is isolated from the local reader. Credentials never leave WebKit.
@MainActor final class LuoguSession: NSObject, WKNavigationDelegate {
  let webView: WKWebView
  private var waiting: CheckedContinuation<Void, Error>?
  private var timeout: Task<Void, Never>?
  override init() {
    let config = WKWebViewConfiguration(); config.websiteDataStore = .default()
    webView = WKWebView(frame: .zero, configuration: config)
    super.init(); webView.navigationDelegate = self
  }
  private func finish(_ error: Error? = nil) {
    timeout?.cancel(); timeout = nil
    let continuation = waiting; waiting = nil
    if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
  }
  func context(path: String) async throws -> Data {
    guard path.range(of: #"^/problem/(?:solution/)?CF[1-9][0-9]*[A-Z][0-9]{0,2}(?:\?page=[1-9][0-9]{0,3})?$"#, options: .regularExpression) != nil else { throw PocketError.invalid("无效的洛谷读取路径。") }
    if webView.url?.host != "www.luogu.com.cn" || webView.isLoading {
      guard waiting == nil else { throw PocketError.unavailable("洛谷正在连接，请稍后重试。") }
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        waiting = continuation
        timeout = Task { try? await Task.sleep(for: .seconds(30)); guard !Task.isCancelled else { return }; self.finish(PocketError.unavailable("连接洛谷超时，可以重试或完成网站验证。")) }
        webView.load(URLRequest(url: URL(string: "https://www.luogu.com.cn" + path)!, timeoutInterval: 25))
      }
    }
    let value: Any?
    do { value = try await webView.callAsyncJavaScript("""
      if (location.origin !== 'https://www.luogu.com.cn') throw Error('请先完成洛谷登录');
      const abort = new AbortController(); const timer = setTimeout(() => abort.abort(), 25000);
      try {
        const response = await fetch(path, {credentials:'same-origin', signal:abort.signal});
        if (new URL(response.url).origin !== location.origin) throw Error('洛谷返回了其它站点');
        const html = await response.text(); if (html.length > 8000000) throw Error('题解页面过大');
        const context = new DOMParser().parseFromString(html,'text/html').querySelector('script#lentille-context[type="application/json"]');
        if (!context) throw Error('请完成洛谷网站验证后重试，原缓存仍保留。');
        const raw = JSON.parse(context.textContent);
        return JSON.stringify({template:raw.template,status:raw.status,data:raw.data});
      } finally { clearTimeout(timer); }
      """, arguments: ["path": path], in: nil, contentWorld: .page)
    } catch {
      let reason = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
      throw PocketError.source("读取洛谷失败，原缓存保留。" + (reason.map { " " + String($0.prefix(200)) } ?? "请检查网络，或完成网站验证后重试。"))
    }
    guard let text = value as? String else { throw PocketError.source("未收到洛谷数据。") }; return Data(text.utf8)
  }
  func showLogin() { webView.load(URLRequest(url: URL(string: "https://www.luogu.com.cn/auth/login")!)) }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
    if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
    guard let url = action.request.url, url.scheme == "https", url.host == "www.luogu.com.cn", url.user == nil else { decisionHandler(.cancel); return }
    decisionHandler(.allow)
  }
}
@MainActor @Observable final class LuoguReaderModel {
  let id: ProblemID
  let storage: PocketStorage
  let session = LuoguSession()
  var problem: LuoguProblem?
  var pages: [LuoguPage] = []
  var error: String?
  var needsLogin = false
  var busy = false
  var loaded = false
  var articles: [LuoguArticle] { var seen = Set<String>(); return pages.flatMap(\.articles).filter { seen.insert($0.id).inserted } }
  init(id: ProblemID, storage: PocketStorage) { self.id = id; self.storage = storage }
  func loadMetadata() async {
    guard !busy else { return }; busy = true; defer { busy = false }
    if !loaded { loaded = true; problem = try? await storage.loadLuoguProblem(id); pages = (try? await storage.loadLuoguPages(id)) ?? [] }
    do { let pid = try LuoguParser.pid(id); let bytes = try await session.context(path: "/problem/\(pid)"); let value = try LuoguParser.problem(bytes, pid: pid); try await storage.saveLuoguProblem(value, id: id); problem = value; error = nil }
    catch { self.error = error.localizedDescription }
  }
  func loadPage(more: Bool = false) async {
    guard !busy else { return }; busy = true; defer { busy = false }
    error = nil; needsLogin = false
    do {
      let pid = try LuoguParser.pid(id), page = more ? (pages.last?.page ?? 0) + 1 : 1
      let data = try await session.context(path: "/problem/solution/\(pid)?page=\(page)")
      let result = try LuoguParser.solutions(data, pid: pid, page: page)
      let next = more ? pages + [result] : [result]
      try await storage.saveLuoguPages(next, id: id)
      pages = next
    } catch { self.error = error.localizedDescription; if case PocketError.blocked = error { needsLogin = true } }
  }
}
struct DifficultyBadge: View {
  let title: String
  let rgb: UInt32
  private var tint: Color { Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255) }
  var body: some View {
    HStack(spacing: 7) {
      Circle().fill(tint).frame(width: 10, height: 10).overlay(Circle().stroke(.gray.opacity(0.35), lineWidth: 0.5)).accessibilityHidden(true)
      Text(title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
    }.font(.subheadline.weight(.medium)).padding(.horizontal, 11).padding(.vertical, 7)
      .background(tint.opacity(0.09), in: Capsule())
      .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
      .accessibilityElement(children: .combine)
  }
}
struct LuoguDifficulty: View {
  let problem: LuoguProblem
  var body: some View { DifficultyBadge(title: "洛谷 · \(problem.difficultyLabel)", rgb: DifficultyPalette.luogu(problem.difficulty)).accessibilityLabel("洛谷难度，\(problem.difficultyLabel)") }
}
struct ProblemMetadataView: View {
  @Bindable var model: WorkspaceModel
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 0) { revealControls }
      } else {
        HStack(spacing: 16) { revealControls; Spacer(minLength: 0) }
      }
      if model.showsDifficulty {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { difficultyBadges }
          VStack(alignment: .leading, spacing: 8) { difficultyBadges }
        }.accessibilityIdentifier("problem-difficulties")
        if model.luogu.problem == nil {
          HStack {
            Text(model.luogu.busy ? "正在获取洛谷难度…" : "洛谷难度暂未获取").font(.footnote).foregroundStyle(.secondary)
            if !model.luogu.busy { Button("重试洛谷") { Task { await model.luogu.loadMetadata() } }.font(.footnote).frame(minHeight: 44) }
          }
        }
      }
      if model.showsTags, let metadata = model.cfMetadata {
        if metadata.tags.isEmpty { Text("CF 暂无 tag").font(.subheadline).foregroundStyle(.secondary) }
        else {
          ScrollView(.horizontal) {
            HStack(spacing: 7) {
              ForEach(Array(Set(metadata.tags)).sorted(), id: \.self) { tag in
                Text(tag).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 7).background(.quaternary, in: Capsule()).accessibilityLabel("CF tag，\(tag)")
              }
            }
          }.scrollIndicators(.hidden).accessibilityIdentifier("problem-tags")
        }
      }
      if (model.showsTags || model.showsDifficulty) && model.cfMetadata == nil {
        HStack {
          if model.app.libraryBusy { ProgressView(); Text("正在获取 CF 信息…").font(.footnote) }
          else {
            Text(model.app.libraryError == nil ? "CF 题库暂无本题信息" : "CF 信息暂未获取").font(.footnote).foregroundStyle(.secondary)
            Button("重试 CF") { Task { await model.app.refresh() } }.font(.footnote).frame(minHeight: 44)
          }
        }
      }
    }.padding(.horizontal, 20).padding(.bottom, model.showsDifficulty || model.showsTags ? 10 : 0)
  }
  @ViewBuilder private var revealControls: some View {
        revealButton(model.showsDifficulty ? "隐藏难度" : "显示难度", expanded: model.showsDifficulty, id: "reveal-difficulty") {
          model.showsDifficulty.toggle()
          if model.showsDifficulty { Task { await model.ensureCFMetadata() } }
        }
        revealButton(model.showsTags ? "隐藏 tag" : "显示 tag", expanded: model.showsTags, id: "reveal-tags") {
          model.showsTags.toggle()
          if model.showsTags { Task { await model.ensureCFMetadata() } }
        }
  }
  @ViewBuilder private var difficultyBadges: some View {
    if let metadata = model.cfMetadata { DifficultyBadge(title: metadata.rating.map { "CF · \($0)" } ?? "CF · 暂未评级", rgb: DifficultyPalette.codeforces(metadata.rating)) }
    if let problem = model.luogu.problem { LuoguDifficulty(problem: problem) }
  }
  private func revealButton(_ title: String, expanded: Bool, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { HStack(spacing: 5) { Text(title).fixedSize(horizontal: false, vertical: true); Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold)) }.font(.subheadline).frame(minHeight: 44) }
      .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityValue(expanded ? "已展开" : "已隐藏").accessibilityIdentifier(id)
  }
}
struct LuoguSolutionsPane: View {
  @Bindable var model: LuoguReaderModel
  @State private var login = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 8) {
            Text("洛谷社区题解").font(.title2.bold())
            Text("\(model.articles.count) 篇已载入" + (model.pages.first.map { " · 共 \($0.total) 篇" } ?? "")).font(.subheadline).foregroundStyle(.secondary)
          }
          Spacer()
          Button { Task { await model.loadPage() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("刷新洛谷题解").disabled(model.busy)
        }
        if let error = model.error {
          VStack(alignment: .leading, spacing: 12) {
            Text(error).font(.body)
            if !model.articles.isEmpty { Text("仍可阅读上次保存的题解。").foregroundStyle(.secondary) }
            HStack { Button("登录 / 验证洛谷") { model.session.showLogin(); login = true }.buttonStyle(.bordered); Button("重试") { Task { await model.loadPage() } }.disabled(model.busy) }
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        }
        if model.busy { ProgressView("正在读取洛谷…").frame(maxWidth: .infinity).padding() }
        if model.pages.first?.total == 0 { ContentUnavailableView("暂没有题解", systemImage: "book.closed", description: Text("洛谷当前没有返回这道题的社区题解。")) }
        LazyVStack(spacing: 0) {
          ForEach(model.articles) { article in
            NavigationLink { LuoguArticleScreen(article: article, pid: model.problem?.pid ?? model.id.description) } label: {
              VStack(alignment: .leading, spacing: 10) {
                HStack { Text(article.author).font(.subheadline.weight(.medium)); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                Text(article.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(3)
                Text("约 \(article.minutes) 分钟 · \(article.publishedAt.formatted(.dateTime.year().month().day()))" + (article.votes.map { " · \($0) 赞" } ?? "")).font(.subheadline).foregroundStyle(.secondary)
              }.padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Divider()
          }
        }
        if model.pages.last?.hasMore == true { Button("加载更多题解") { Task { await model.loadPage(more: true) } }.buttonStyle(.borderedProminent).disabled(model.busy).frame(maxWidth: .infinity) }
        if let problem = model.problem { Link("洛谷原题 · \(problem.pid)", destination: problem.url).font(.subheadline).frame(minHeight: 44) }
        if let at = model.pages.first?.fetchedAt { Text("保存于 \(at.formatted(date: .abbreviated, time: .shortened)) · 作者及原文链接见文章页").font(.footnote).foregroundStyle(.secondary) }
      }.padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }.background(PocketStyle.readingPaper)
      .task { while model.busy && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(150)) }; if !model.loaded { await model.loadMetadata() }; if model.pages.isEmpty { await model.loadPage() } }
      .sheet(isPresented: $login, onDismiss: { Task { await model.loadPage() } }) {
        NavigationStack { LuoguLoginWeb(session: model.session).navigationTitle("登录洛谷").navigationBarTitleDisplayMode(.inline).toolbar { Button("返回题解") { login = false } } }
      }
  }
}
private struct LuoguLoginWeb: UIViewRepresentable {
  let session: LuoguSession
  func makeUIView(context: Context) -> WKWebView { session.webView }
  func updateUIView(_ view: WKWebView, context: Context) {}
}
struct LuoguArticleScreen: View {
  let article: LuoguArticle
  let pid: String
  @State private var rendered: String?
  @State private var error: String?
  var body: some View {
    Group {
      if let rendered { FragmentReader(html: rendered, source: article.url, readingKey: "luogu-\(article.id)") }
      else if let error { ContentUnavailableView("排版暂时失败", systemImage: "doc.text", description: Text(error)) }
      else { ProgressView("正在排版…") }
    }.navigationTitle("\(pid) · 题解").navigationBarTitleDisplayMode(.inline)
      .toolbar { ShareLink(item: article.url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享原文链接") }
      .task(id: article.id) {
        do { let article = article; rendered = try await Task.detached(priority: .userInitiated) {
          let esc = PocketMarkdown.escape
          let header = "<h1>\(esc(article.title))</h1><p class=\"reader-note\">\(esc(article.author)) · \(article.publishedAt.formatted(date: .abbreviated, time: .omitted)) · 约 \(article.minutes) 分钟</p><hr>"
          let note = try article.adminNote.map { "<blockquote>管理组提示" + (try PocketMarkdown.html($0, source: article.url, luogu: true)) + "</blockquote>" } ?? ""
          return header + note + (try PocketMarkdown.html(article.markdown, source: article.url, luogu: true)) + "<hr><p class=\"reader-note\">来源：洛谷社区 · 版权归原作者所有 · <a href=\"\(article.url.absoluteString)\">查看原文</a></p>"
        }.value } catch { self.error = error.localizedDescription }
      }
  }
}
