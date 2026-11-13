#if DEBUG
import SwiftUI
import PocketCore

/// Isolated layout fixture. Never attaches to PocketModel, never sends AI requests or saves history.
struct ReadingReview: View {
  @State private var language: ReadingLanguage = .chinese
  @State private var statement: Statement?
  private let translated = #"""
  # 开发排版样例
  **这不是官方题面，也不是 AI 实时结果。**

  给定数组 $$$a_i \le 10^9$$$，求元素之和。

  ## 输入格式
  - 第一行是整数 `n`。
  - 第二行包含 **n 个整数**。

  | 变量 | 含义 |
  | --- | --- |
  | n | 元素数量 |
  | a_i | 第 i 个元素 |

  ## 参考排版
  ```cpp
  for (int x : values) {
      sum += x;
  }
  ```

  > 这段代码仅用于检查等宽排版与横向滚动。
  """#
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Text("仅用于开发验收 · 不写入任何训练记录").font(.caption).padding(12).frame(maxWidth: .infinity).background(Color.orange.opacity(0.12))
        Picker("题面语言", selection: $language) { ForEach(ReadingLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding()
        if let statement {
          InlineTranslatedReader(statement: statement, translation: translated, explanation: nil, language: language, allowed: true, generate: {}, busy: false)
        }
      }.navigationTitle("开发阅读样例").navigationBarTitleDisplayMode(.inline)
    }.task {
      let source = #"<div class="problem-statement"><div class="header"><div class="title">A. Development layout fixture</div></div><p>This original development fixture is not a real Codeforces statement. It is used only to check headings, lists, tables, mathematics, sample whitespace and bilingual switching in the reading area. No history is written and no AI request is sent.</p><div class="input-specification">Read n and n integers.</div><div class="output-specification">Print their sum.</div><div class="sample-test"><div class="input"><pre>3<br>1 2 3</pre></div><div class="output"><pre>6</pre></div></div></div>"#
      if let id = try? ProblemID(contest: 1, index: "A") { statement = try? SourceParser.statement(source, id: id, source: id.url) }
    }
  }
}
#endif
