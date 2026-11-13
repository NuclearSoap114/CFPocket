import SwiftUI
import UIKit
import JavaScriptCore
import PocketCore

/// The editor and article reader use the same bundled C++ / Python grammar and palette.
@MainActor final class CodeHighlight {
  static let shared = CodeHighlight()
  struct Token: Decodable { let text: String; let kind: String }
  private let context: JSContext?
  private var lastSource = "", lastLanguage = ""
  private var lastTokens: [Token] = []
  private var palettes: [Bool: [String: UIColor]] = [:]
  private init() {
    context = JSContext()
    if let root = Bundle.main.url(forResource: "Reader", withExtension: nil),
       let script = try? String(contentsOf: root.appendingPathComponent("code-highlight.js"), encoding: .utf8) { context?.evaluateScript(script) }
  }
  func tokens(_ source: String, python: Bool) -> [Token] {
    let language = python ? "python" : "cpp"
    if source == lastSource && language == lastLanguage { return lastTokens }
    let raw = context?.objectForKeyedSubscript("PocketCode")?.invokeMethod("tokensJSON", withArguments: [source, language])?.toString()
    let parsed = raw?.data(using: .utf8).flatMap { try? JSONDecoder().decode([Token].self, from: $0) }
    let tokens = parsed?.map(\.text).joined() == source ? parsed! : [Token(text: source, kind: "foreground")]
    lastSource = source; lastLanguage = language; lastTokens = tokens
    return tokens
  }
  func palette(dark: Bool) -> [String: UIColor] {
    if let cached = palettes[dark] { return cached }
    let raw = context?.objectForKeyedSubscript("PocketCode")?.invokeMethod("paletteJSON", withArguments: [dark])?.toString()
    let values = raw?.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    let colors = values.mapValues { hex -> UIColor in
      let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
      return UIColor(red: CGFloat((v >> 16) & 255)/255, green: CGFloat((v >> 8) & 255)/255, blue: CGFloat(v & 255)/255, alpha: 1)
    }
    palettes[dark] = colors; return colors
  }
}

struct CodeSnapshot: View {
  let source: String
  var python = false
  @State private var height: CGFloat = 120
  var body: some View {
    FragmentReader(html: "<pre><code class=\"language-\(python ? "python" : "cpp")\">\(PocketMarkdown.escape(source))</code></pre>",
                   source: URL(string: "https://codeforces.com")!, readingKey: "code-snapshot", measuredHeight: $height)
      .frame(height: height).accessibilityIdentifier("code-snapshot")
  }
}
