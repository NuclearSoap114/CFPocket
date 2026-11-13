import SwiftUI
import WebKit
import Network
import PocketCore

/// Loopback-only immutable asset server. It cannot compile, read user files, accept uploads, or proxy requests.
private final class ListenerGate: @unchecked Sendable { var resumed = false }
final class RuntimeAssetServer: @unchecked Sendable {
  private var listener: NWListener?
  private let queue = DispatchQueue(label: "cfpocket.runtime.assets")
  private let root: URL
  private let nonce = UUID().uuidString
  private var connections: [UUID: NWConnection] = [:]
  private let connectionLock = NSLock()
  init(root: URL) { self.root = root }
  func start() async throws -> URL {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters); self.listener = listener
    return try await withCheckedThrowingContinuation { continuation in
      let gate = ListenerGate()
      listener.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          if !gate.resumed, let port = listener.port { gate.resumed = true; continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.nonce)/index.html")!) }
        case .failed(let error): if !gate.resumed { gate.resumed = true; continuation.resume(throwing: error) }
        default: break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
      listener.start(queue: queue)
    }
  }
  private func accept(_ connection: NWConnection) {
    let id = UUID(); connectionLock.withLock { connections[id] = connection }
    connection.stateUpdateHandler = { [weak self] state in if case .cancelled = state { self?.removeConnection(id) } }
    connection.start(queue: queue)
    readHeader(connection, data: Data())
  }
  private func readHeader(_ connection: NWConnection, data: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, complete, error in
      guard let self else { connection.cancel(); return }
      var data = data; if let bytes { data.append(bytes) }
      guard data.count < 16384, error == nil else { connection.cancel(); return }
      if let header = String(data: data, encoding: .utf8), header.contains("\r\n\r\n") { self.respond(connection, header: header) }
      else if complete { connection.cancel() } else { self.readHeader(connection, data: data) }
    }
  }
  private func respond(_ connection: NWConnection, header: String) {
    let fields = header.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
    guard fields.count == 3, fields[0] == "GET" || fields[0] == "HEAD", let path = String(fields[1]).removingPercentEncoding, !path.contains("?"), !path.contains(".."), path.hasPrefix("/\(nonce)/") else { connection.cancel(); return }
    let relative = String(path.dropFirst(nonce.count + 2))
    let file = root.appendingPathComponent(relative).standardizedFileURL
    guard file.path.hasPrefix(root.standardizedFileURL.path + "/"), let attr = try? FileManager.default.attributesOfItem(atPath: file.path), attr[.type] as? FileAttributeType == .typeRegular, let handle = try? FileHandle(forReadingFrom: file) else {
      connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() }); return
    }
    let count = (attr[.size] as? NSNumber)?.intValue ?? 0
    let mime: String
    switch file.pathExtension { case "html": mime = "text/html; charset=utf-8"; case "js", "mjs": mime = "text/javascript"; case "json": mime = "application/json"; case "wasm": mime = "application/wasm"; default: mime = "application/octet-stream" }
    // unsafe-eval is needed by the bundled Pyodide JS bridge. No remote scripts/URLs/native secrets are exposed.
    let csp = "default-src 'none'; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'; img-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'"
    let head = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(count)\r\nContent-Security-Policy: \(csp)\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
    connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
      if error != nil || fields[0] == "HEAD" { try? handle.close(); connection.cancel() } else { self?.sendFile(handle, connection: connection) }
    })
  }
  private func sendFile(_ handle: FileHandle, connection: NWConnection) {
    guard let data = try? handle.read(upToCount: 262144), !data.isEmpty else { try? handle.close(); connection.cancel(); return }
    connection.send(content: data, completion: .contentProcessed { [weak self] error in
      if error != nil { try? handle.close(); connection.cancel() } else { self?.sendFile(handle, connection: connection) }
    })
  }
  private func removeConnection(_ id: UUID) { connectionLock.withLock { connections[id] = nil } }
  deinit { listener?.cancel(); let active = connectionLock.withLock { let list = Array(connections.values); connections.removeAll(); return list }; active.forEach { $0.cancel() } }
}

@MainActor @Observable final class RuntimeEngine: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  var ready = false
  var inForeground = true
  var running = false
  var phase = "未运行"
  var result: LocalRun?
  var failure: String?
  let webView: WKWebView
  private var server: RuntimeAssetServer?
  private var current: (id: String, revision: CodeRevision, input: String, expected: String?)?
  private var watchdog: Task<Void, Never>?
  private var prepareTask: Task<Void, Never>?
  var completion: ((LocalRun) -> Void)?
  override init() {
    let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
    webView = WKWebView(frame: .zero, configuration: config)
    super.init(); config.userContentController.add(self, name: "runtime"); webView.navigationDelegate = self
    webView.isInspectable = false
  }
  func prepare() {
    guard !ready, prepareTask == nil else { return }
    prepareTask = Task {
      do {
        guard let root = Bundle.main.url(forResource: "Runtime", withExtension: nil) else { throw PocketError.unavailable("安装包缺少本地运行环境。") }
        let server = RuntimeAssetServer(root: root); self.server = server
        let url = try await server.start(); webView.load(URLRequest(url: url))
      } catch { failure = error.localizedDescription }
      prepareTask = nil
    }
  }
  func run(revision: CodeRevision, input: String, expected: String?, timeoutMS: Int = 2000, standard: String = "c++20") {
    guard inForeground else { failure = "回到前台后才能开始本地运行。"; return }
    guard ready, !running else { failure = ready ? "请先停止当前运行。" : "运行环境仍在初始化。"; return }
    guard revision.source.utf8.count <= 262144, input.utf8.count <= 65536 else { failure = "代码上限 256 KB，输入上限 64 KB。"; return }
    UIApplication.shared.isIdleTimerDisabled = true
    let id = UUID().uuidString; current = (id, revision, input, expected); running = true; result = nil; failure = nil; phase = "初始化本地环境"
    let payload: [String: Any] = ["id":id,"source":revision.source,"language":revision.language.rawValue,"stdin":input,"timeoutMS":timeoutMS,"standard":standard]
    guard let json = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: json, encoding: .utf8) else { return }
    webView.evaluateJavaScript("window.startJob(\(text));") { [weak self] _, error in if let error { Task { @MainActor in self?.finish(status: "setup-error", stdout: "", stderr: error.localizedDescription, ms: 0, environment: "WebKit") } } }
    watchdog?.cancel()
    watchdog = Task { try? await Task.sleep(for: .seconds(100)); guard !Task.isCancelled, current?.id == id else { return }; hardReset(reason: "本地环境无响应，已销毁 WebView 与运行任务，可重新运行。") }
  }
  func stop(reason: String = "已停止，底层 Worker 已终止。") {
    guard running else { return }
    webView.evaluateJavaScript("window.stopJob(\(jsString(reason)));") { [weak self] _, error in if error != nil { Task { @MainActor in self?.hardReset(reason: reason) } } }
  }
  private func hardReset(reason: String) {
    webView.loadHTMLString("", baseURL: nil); ready = false
    finish(status: "stopped", stdout: "", stderr: reason, ms: 0, environment: "WebKit reset")
    server = nil; prepare()
  }
  private func finish(status: String, stdout: String, stderr: String, ms: Double, environment: String) {
    guard let current else { return }; UIApplication.shared.isIdleTimerDisabled = false; self.current = nil; watchdog?.cancel(); watchdog = nil; running = false; phase = status
    let value = LocalRun(revision: current.revision, input: current.input, expected: current.expected, status: status, stdout: stdout, stderr: stderr, durationMS: ms, environment: environment)
    result = value; completion?(value)
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.webView === webView, message.frameInfo.isMainFrame, let data = message.body as? [String: Any], let type = data["type"] as? String else { return }
    if type == "ready" { ready = true; return }
    guard data["jobID"] as? String == current?.id else { return }
    if type == "phase" { phase = ["setup":"初始化","compile":"本地编译","link":"本地链接","run":"本地执行"][data["phase"] as? String ?? ""] ?? "运行中" }
    if type == "result" { finish(status: data["status"] as? String ?? "runtime-error", stdout: data["stdout"] as? String ?? "", stderr: data["stderr"] as? String ?? "", ms: data["durationMS"] as? Double ?? 0, environment: data["environment"] as? String ?? "WebKit") }
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; finish(status: "resource-error", stdout: "", stderr: "WebKit 运行进程被系统终止，可能是内存压力。草稿未受影响。", ms: 0, environment: "WebKit"); server = nil; prepare() }
}
func jsString(_ text: String) -> String { String(data: try! JSONEncoder().encode(text), encoding: .utf8)! }
struct RuntimeHost: UIViewRepresentable {
  let engine: RuntimeEngine
  func makeUIView(context: Context) -> WKWebView { engine.webView.accessibilityElementsHidden = true; engine.webView.isAccessibilityElement = false; engine.webView.clipsToBounds = true; engine.prepare(); return engine.webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
