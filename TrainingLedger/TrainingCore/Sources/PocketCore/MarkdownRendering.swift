import Foundation
import Markdown

public enum PocketMarkdown {
  /// Parse with Swift's CommonMark/GFM parser, then apply the same allowlist as official fragments.
  /// Math is protected before Markdown parsing so underscores and backslashes remain exact.
  public static func html(_ text: String, source: URL, luogu: Bool = false) throws -> String {
    guard text.utf8.count <= 262_144 else { throw PocketError.invalid("阅读内容超过 256 KB。") }
    let text = normalized(text)
    let expression = try NSRegularExpression(pattern: #"\$\$\$[\s\S]*?\$\$\$|\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)|(?<!\$)\$[^\s$][^$\n]*?\$(?!\$)"#)
    let ns = text as NSString
    let matches = expression.matches(in: text, range: NSRange(location: 0, length: ns.length))
    let prefix = "POCKETMATH" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var protected = text
    var replacements: [(String, String)] = []
    for (index, match) in matches.enumerated().reversed() {
      let token = prefix + String(index) + "END"
      replacements.append((token, ns.substring(with: match.range)))
      if let range = Range(match.range, in: protected) { protected.replaceSubrange(range, with: token) }
    }
    // HTMLFormatter emits literal node contents directly. Escape AST literals before
    // formatting so C++ templates and includes cannot become HTML elements.
    var literals = HTMLSafeLiterals()
    let document = Document(parsing: protected)
    var html = HTMLFormatter.format(literals.visit(document) ?? document)
    for (token, formula) in replacements { html = html.replacingOccurrences(of: token, with: escape(formula)) }
    return try SourceParser.sanitize(html, base: source, luogu: luogu)
  }
  /// Recover AI replies whose JSON string contains an extra layer of layout escapes.
  /// Never globally unescape JSON: that corrupts LaTeX and code string literals.
  public static func normalized(_ input: String) -> String {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("\n"), text.contains(#"\n\n"#) || text.range(of: #"\\n#{1,6} |```(?:markdown|md|cpp|python)?\\n"#, options: .regularExpression) != nil {
      let protected = try? NSRegularExpression(pattern: #"\$\$\$[\s\S]*?\$\$\$|\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)|(?<!\$)\$[^\s$][^$\n]*?\$(?!\$)|(?<!`)`[^`]*`(?!`)"#)
      let ns = text as NSString
      let ranges = protected?.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
      let breaks = try? NSRegularExpression(pattern: #"(\\+)n"#)
      for match in (breaks?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []).reversed() {
        guard !ranges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
        let count = match.range(at: 1).length
        let value = count == 1 ? "\n" : String(repeating: "\\", count: max(1, count / 2)) + "n"
        if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: value) }
      }
    }
    // Some models wrap the complete document in a Markdown fence. Keep actual code fences intact.
    if let re = try? NSRegularExpression(pattern: #"\A```(?:markdown|md)[ \t]*\n([\s\S]*)\n```\z"#, options: .caseInsensitive),
       let match = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
      text = (text as NSString).substring(with: match.range(at: 1))
    }
    return text
  }
  public static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}

private struct HTMLSafeLiterals: MarkupRewriter {
  mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
    var value = codeBlock
    value.code = PocketMarkdown.escape(codeBlock.code)
    value.language = codeBlock.language.flatMap {
      $0.range(of: #"\A[a-zA-Z0-9_+.-]{1,40}\z"#, options: .regularExpression) != nil ? $0 : nil
    }
    return value
  }
  mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
    var value = inlineCode; value.code = PocketMarkdown.escape(inlineCode.code); return value
  }
  mutating func visitText(_ text: Text) -> Markup? {
    var value = text; value.string = PocketMarkdown.escape(text.string); return value
  }
  mutating func visitLink(_ link: Link) -> Markup? {
    guard var value = defaultVisit(link) as? Link else { return nil }
    value.destination = value.destination.map(PocketMarkdown.escape); return value
  }
  mutating func visitImage(_ image: Image) -> Markup? {
    var value = image
    value.source = value.source.map(PocketMarkdown.escape)
    value.title = value.title.map(PocketMarkdown.escape)
    return value
  }
  mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> Markup? {
    var value = symbolLink; value.destination = value.destination.map(PocketMarkdown.escape); return value
  }
}
