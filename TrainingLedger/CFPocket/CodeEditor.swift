import SwiftUI
import UIKit
import JavaScriptCore

struct CodeEdit: Decodable {
  let start: Int; let end: Int; let text: String; let selectionStart: Int; let selectionEnd: Int
}
struct CodeSuggestion: Decodable { let id: String; let label: String; let kind: String; let edit: CodeEdit }
@MainActor final class EditingRules {
  static let shared = EditingRules()
  private let context = JSContext()
  private init() {
    if let folder = Bundle.main.url(forResource: "Reader", withExtension: nil), let js = try? String(contentsOf: folder.appendingPathComponent("editor-core.js"), encoding: .utf8) { context?.evaluateScript(js) }
  }
  func call<T: Decodable>(_ name: String, _ args: [Any], as: T.Type = T.self) -> T? {
    guard let raw = context?.objectForKeyedSubscript("PocketEditing")?.invokeMethod(name, withArguments: args)?.toString(), let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }
}
@MainActor @Observable final class EditorControl {
  weak var textView: UITextView?
  weak var coordinator: CodeEditor.Coordinator?
  func insert(_ text: String) { coordinator?.insert(text) }
  func undo() { textView?.undoManager?.undo(); coordinator?.refreshAfterCommand() }
  func redo() { textView?.undoManager?.redo(); coordinator?.refreshAfterCommand() }
  func find() { textView?.findInteraction?.presentFindNavigator(showingReplace: true) }
  func replaceTemplate(_ text: String? = nil, multiple: Bool = false) {
    guard let view = textView, let coordinator else { return }
    if let text { coordinator.apply(CodeEdit(start: 0, end: (view.text as NSString).length, text: text, selectionStart: (text as NSString).length, selectionEnd: (text as NSString).length)) }
    else if let edit: CodeEdit = EditingRules.shared.call("templateJSON", [view.text ?? "",coordinator.parent.python,multiple]) { coordinator.apply(edit) }
  }
  func jump(line: Int) {
    guard let view = textView else { return }; let ns = view.text as NSString
    var at = 0
    for _ in 1..<max(1,line) { let r = ns.range(of: "\n", range: NSRange(location: at, length: ns.length-at)); if r.location == NSNotFound { break }; at = r.location + 1 }
    view.becomeFirstResponder(); view.selectedRange = NSRange(location: at, length: 0); view.scrollRangeToVisible(view.selectedRange)
  }
}
struct CodeEditor: UIViewRepresentable {
  @Binding var text: String
  let control: EditorControl
  let python: Bool
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator; view.backgroundColor = .secondarySystemGroupedBackground
    view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular)); view.adjustsFontForContentSizeCategory = true
    view.textColor = .label; view.tintColor = .systemTeal
    view.autocapitalizationType = .none; view.autocorrectionType = .no; view.smartQuotesType = .no; view.smartDashesType = .no; view.smartInsertDeleteType = .no; view.spellCheckingType = .no
    view.isFindInteractionEnabled = true; view.keyboardDismissMode = .interactive
    view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 30, right: 10)
    view.accessibilityLabel = "代码编辑器"; view.accessibilityHint = "支持查找替换、符号输入、缩进和撤销重做。"
    view.text = text; control.textView = view; control.coordinator = context.coordinator
    view.inputAccessoryView = context.coordinator.makeAccessory(view)
    context.coordinator.highlight(view); context.coordinator.refreshSuggestions(view)
    return view
  }
  func updateUIView(_ view: UITextView, context: Context) {
    let changedTheme = context.coordinator.parent.colorScheme != colorScheme || context.coordinator.parent.python != python || context.coordinator.parent.dynamicTypeSize != dynamicTypeSize
    if context.coordinator.parent.python != python { view.undoManager?.removeAllActions() }
    context.coordinator.parent = self
    if changedTheme { context.coordinator.highlight(view) }
    if view.text != text && view.markedTextRange == nil { let selection = view.selectedRange; view.text = text; view.selectedRange = NSRange(location: min(selection.location,(text as NSString).length),length:0); context.coordinator.highlight(view); context.coordinator.refreshSuggestions(view) }
  }
  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
  @MainActor final class Coordinator: NSObject, UITextViewDelegate {
    var parent: CodeEditor
    private var task: Task<Void,Never>?
    private var applying = false
    private var numbers = false
    private weak var suggestionStack: UIStackView?
    private weak var symbolsStack: UIStackView?
    private weak var numberButton: UIButton?
    private var suggestionsSignature = ""

    init(parent: CodeEditor) { self.parent = parent }
    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
      if textView.markedTextRange == nil { refreshSuggestions(textView) }
      task?.cancel(); task = Task { try? await Task.sleep(for: .milliseconds(100)); guard !Task.isCancelled, textView.markedTextRange == nil else { return }; highlight(textView) }
    }
    func textViewDidChangeSelection(_ textView: UITextView) { if !applying && textView.markedTextRange == nil { markBracket(textView); refreshSuggestions(textView) } }
    func textViewDidBeginEditing(_ textView: UITextView) { refreshSuggestions(textView) }

    func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
      guard (view.text as NSString).length - range.length + (text as NSString).length <= 262144 else { return false }
      guard !applying, view.markedTextRange == nil else { return true }
      let backspace = text.isEmpty && view.selectedRange.length == 0 && NSMaxRange(range) == view.selectedRange.location
      if let edit: CodeEdit = EditingRules.shared.call("editJSON", [view.text ?? "",range.location,NSMaxRange(range),text,parent.python,backspace]) { apply(edit, focus: false); return false }
      return true
    }
    func apply(_ edit: CodeEdit, focus: Bool = true) {
      guard let view = parent.control.textView, view.markedTextRange == nil else { return }
      let length = (view.text as NSString).length
      guard edit.start >= 0, edit.end >= edit.start, edit.end <= length,
        length - (edit.end-edit.start) + (edit.text as NSString).length <= 262144 else { return }
      applying = true
      if focus { view.becomeFirstResponder() }
      // Range replacement is a distinct editing command, not a continuation of typing.
      if edit.start != edit.end || !edit.text.isEmpty {
        view.undoManager?.beginUndoGrouping()
        if let start = view.position(from: view.beginningOfDocument, offset: edit.start),
           let end = view.position(from: view.beginningOfDocument, offset: edit.end),
           let range = view.textRange(from: start, to: end) { view.replace(range, withText: edit.text) }
        view.undoManager?.endUndoGrouping()
      }
      let end = (view.text as NSString).length
      view.selectedRange = NSRange(location: min(end,max(0,edit.selectionStart)),length: max(0,min(end,edit.selectionEnd)-min(end,max(0,edit.selectionStart))))
      applying = false; textViewDidChange(view); view.scrollRangeToVisible(view.selectedRange)
    }
    func insert(_ text: String) {
      guard let view = parent.control.textView, view.markedTextRange == nil else { return }
      let r = view.selectedRange
      if text == "⇥" || text == "⇤" {
        if let edit: CodeEdit = EditingRules.shared.call("indentJSON", [view.text ?? "",r.location,NSMaxRange(r),text == "⇤"]) { apply(edit) }
      } else if let edit: CodeEdit = EditingRules.shared.call("editJSON", [view.text ?? "",r.location,NSMaxRange(r),text,parent.python,false]) { apply(edit) }
      else { apply(CodeEdit(start: r.location,end: NSMaxRange(r),text: text,selectionStart: r.location+(text as NSString).length,selectionEnd: r.location+(text as NSString).length)) }
    }
    func refreshAfterCommand() { if let view = parent.control.textView { textViewDidChange(view) } }
    func complete(_ id: String) {
      guard let view = parent.control.textView, view.markedTextRange == nil else { return }
      let r = view.selectedRange
      let options: [CodeSuggestion] = EditingRules.shared.call("suggestJSON", [view.text ?? "",r.location,NSMaxRange(r),parent.python]) ?? []
      if let candidate = options.first(where: { $0.id == id }) { apply(candidate.edit) }
    }
    func refreshSuggestions(_ view: UITextView) {
      guard let stack = suggestionStack else { return }
      let r = view.selectedRange
      let options: [CodeSuggestion] = view.markedTextRange == nil ? (EditingRules.shared.call("suggestJSON", [view.text ?? "",r.location,NSMaxRange(r),parent.python]) ?? []) : []
      let signature = options.map { $0.id + $0.label }.joined(separator: "/")
      guard signature != suggestionsSignature || stack.arrangedSubviews.isEmpty else { return }; suggestionsSignature = signature
      stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
      for option in options {
        let button = accessoryButton(option.id, label: "补全 \(option.label)，\(option.kind)") { [weak self] in self?.complete(option.id) }
        button.configuration = .tinted(); button.configuration?.title = option.id; button.configuration?.baseForegroundColor = .label
        button.configuration?.baseBackgroundColor = .tertiarySystemFill; button.configuration?.cornerStyle = .capsule
        stack.addArrangedSubview(button)
      }
    }
    private func accessoryButton(_ title: String, label: String? = nil, action: @escaping () -> Void) -> UIButton {
      let button = UIButton(type: .system); button.setTitle(title, for: .normal)
      button.titleLabel?.font = .monospacedSystemFont(ofSize: 17, weight: .medium); button.accessibilityLabel = label ?? title
      button.addAction(UIAction { _ in action() }, for: .touchUpInside)
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      button.heightAnchor.constraint(equalToConstant: 44).isActive = true
      return button
    }
    func makeAccessory(_ view: UITextView) -> UIView {
      let accessory = UIView(frame: CGRect(x: 0,y: 0,width: 390,height: 96)); accessory.backgroundColor = .secondarySystemBackground
      let rows = UIStackView(); rows.axis = .vertical; rows.spacing = 4; accessory.addSubview(rows); rows.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([rows.leadingAnchor.constraint(equalTo: accessory.leadingAnchor,constant: 6),rows.trailingAnchor.constraint(equalTo: accessory.trailingAnchor,constant: -6),rows.topAnchor.constraint(equalTo: accessory.topAnchor,constant: 2),rows.bottomAnchor.constraint(equalTo: accessory.bottomAnchor,constant: -2)])
      func scrollStack() -> (UIScrollView,UIStackView) {
        let scroll = UIScrollView();scroll.showsHorizontalScrollIndicator = false; let stack = UIStackView();stack.axis = .horizontal;stack.spacing = 6;scroll.addSubview(stack);stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
        return (scroll,stack)
      }
      let top = UIStackView(); top.spacing = 6; let (suggestions,stack) = scrollStack(); suggestionStack = stack; top.addArrangedSubview(suggestions)
      let done = accessoryButton("完成", label: "收起键盘") { [weak view] in view?.resignFirstResponder() };done.widthAnchor.constraint(equalToConstant: 52).isActive = true;top.addArrangedSubview(done);rows.addArrangedSubview(top)
      let bottom = UIStackView();bottom.spacing = 4
      let toggle = accessoryButton("123", label: "切换数字与符号") { [weak self] in self?.numbers.toggle(); self?.populateSymbols() };toggle.widthAnchor.constraint(equalToConstant: 48).isActive = true;numberButton = toggle;bottom.addArrangedSubview(toggle)
      let (symbols,symbolsRow) = scrollStack();symbolsStack = symbolsRow;bottom.addArrangedSubview(symbols)
      for (title,offset) in [("←",-1),("→",1)] { let button = accessoryButton(title,label: offset < 0 ? "光标左移" : "光标右移") { [weak view] in
        guard let view, view.markedTextRange == nil else { return };view.becomeFirstResponder()
        let at = offset < 0 ? view.selectedRange.location : NSMaxRange(view.selectedRange)
        if let p = view.position(from: view.beginningOfDocument,offset: at), let next = view.position(from: p,in: offset < 0 ? .left : .right,offset: 1), let r = view.textRange(from: next,to: next) { view.selectedTextRange = r;view.scrollRangeToVisible(view.selectedRange) }
      };button.widthAnchor.constraint(equalToConstant: 44).isActive = true;bottom.addArrangedSubview(button) }
      rows.addArrangedSubview(bottom); populateSymbols(); return accessory
    }
    private func populateSymbols() {
      guard let stack = symbolsStack else { return }; stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
      numberButton?.setTitle(numbers ? "符号" : "123", for: .normal)
      for symbol in numbers ? ["1","2","3","4","5","6","7","8","9","0",".","-"] : ["⇥","⇤","{","}","(",")","[","]",";","<<",">>","++","==","&&","||","<",">","=","+","-","*","/","%","&","|","!","\"","'","_",",",":","#"] {
        stack.addArrangedSubview(accessoryButton(symbol,label: symbol == "⇥" ? "缩进" : symbol == "⇤" ? "取消缩进" : "输入 \(symbol)") { [weak self] in self?.insert(symbol) })
      }
    }
    func highlight(_ view: UITextView) {
      let range = NSRange(location: 0, length: (view.text as NSString).length)
      let highlighter = CodeHighlight.shared, colors = highlighter.palette(dark: parent.colorScheme == .dark)
      let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
      view.backgroundColor = colors["background"] ?? .systemBackground
      view.tintColor = colors["foreground"] ?? .label
      view.undoManager?.disableUndoRegistration(); view.textStorage.beginEditing()
      view.textStorage.addAttributes([.foregroundColor: colors["foreground"] ?? UIColor.label, .font: font], range: range)
      var offset = 0
      for token in highlighter.tokens(view.text, python: parent.python) {
        let length = (token.text as NSString).length
        if length > 0, offset + length <= range.length { view.textStorage.addAttribute(.foregroundColor, value: colors[token.kind] ?? colors["foreground"] ?? UIColor.label, range: NSRange(location: offset, length: length)) }
        offset += length
      }
      view.typingAttributes = [.foregroundColor: colors["foreground"] ?? UIColor.label, .font: font]
      view.textStorage.endEditing(); view.undoManager?.enableUndoRegistration(); markBracket(view)
    }
    func markBracket(_ view: UITextView) {
      guard !view.text.isEmpty else { return }
      view.undoManager?.disableUndoRegistration(); defer { view.undoManager?.enableUndoRegistration() }
      let ns = view.text as NSString, at = view.selectedRange.location
      view.textStorage.removeAttribute(.backgroundColor, range: NSRange(location:0,length:ns.length))
      guard at > 0, view.selectedRange.length == 0 else { return }
      let c = ns.substring(with:NSRange(location:at-1,length:1))
      let pairs = ["(":")","[":"]","{":"}"]
      if let close = pairs[c] {
        var depth = 1, i = at
        while i < min(ns.length,at+20000) { let x = ns.substring(with:NSRange(location:i,length:1));if x == c { depth += 1 };if x == close { depth -= 1 };if depth == 0 { view.textStorage.addAttribute(.backgroundColor,value:UIColor.systemTeal.withAlphaComponent(0.18),range:NSRange(location:i,length:1));break };i += 1 }
      }
    }
  }
}
