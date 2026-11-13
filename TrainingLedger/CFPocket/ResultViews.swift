import SwiftUI
import PocketCore

extension ResultVerdict {
  var color: Color {
    switch tone {
    case .success: PocketStyle.adaptive(0x14783C, 0x6FE3A0)
    case .failure: PocketStyle.adaptive(0xBE2939, 0xFF8E97)
    case .caution: PocketStyle.amber
    case .neutral: PocketStyle.accent
    }
  }
  var symbol: String {
    switch tone { case .success: "checkmark.circle.fill"; case .failure: "xmark.circle.fill"; case .caution: "exclamationmark.circle.fill"; case .neutral: "clock" }
  }
}

struct VerdictCard: View {
  let verdict: ResultVerdict
  let scope: String
  var detail: String? = nil
  @ScaledMetric(relativeTo: .largeTitle) private var resultSize = 52
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(scope).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
      HStack(alignment: .center, spacing: 14) {
        Text(verdict.code).font(.system(size: resultSize, weight: .heavy, design: .rounded))
          .minimumScaleFactor(0.65).lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: verdict.symbol).font(.system(.largeTitle, design: .rounded)).accessibilityHidden(true)
      }.foregroundStyle(verdict.color)
      Text(detail ?? verdict.title).font(.headline).fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
      .background(verdict.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
      .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(verdict.color.opacity(0.2), lineWidth: 1) }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("verdict-card")
  }
}

struct VerdictBadge: View {
  let verdict: ResultVerdict
  var body: some View {
    Text(verdict.code).font(.system(.headline, design: .rounded, weight: .heavy))
      .foregroundStyle(verdict.color).padding(.horizontal, 12).padding(.vertical, 8)
      .background(verdict.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
      .accessibilityLabel("\(verdict.code)，\(verdict.title)")
  }
}

struct RunResultView: View {
  let run: LocalRun
  let specialJudge: Bool
  var showVerdict = true
  @State private var showOutput: Bool
  @State private var showDiagnostics: Bool
  init(run: LocalRun, specialJudge: Bool, showVerdict: Bool = true) {
    self.run = run; self.specialJudge = specialJudge; self.showVerdict = showVerdict
    _showOutput = State(initialValue: run.textMatches == false || run.expected == nil)
    _showDiagnostics = State(initialValue: run.status != "ok" && !run.stderr.isEmpty)
  }
  private var verdict: ResultVerdict { .local(run, specialJudge: specialJudge) }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if showVerdict { VerdictCard(verdict: verdict, scope: "本地样例" + (run.sampleNumber.map { " · \($0)" } ?? "")) }
      DisclosureGroup(run.expected == nil ? "查看输出" : "输出对比", isExpanded: $showOutput) {
        VStack(alignment: .leading, spacing: 16) {
          output("实际输出", run.stdout)
          if let expected = run.expected { output("期望输出", expected) }
        }.padding(.top, 12)
      }.font(.subheadline.weight(.medium))
      if !run.stderr.isEmpty {
        DisclosureGroup("诊断信息", isExpanded: $showDiagnostics) {
          Text(run.stderr).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled).padding(.top, 12)
        }.font(.subheadline.weight(.medium))
      }
      DisclosureGroup("运行详情") {
        VStack(alignment: .leading, spacing: 12) {
          Text("本地 AC / WA 只比较空白分隔后的样例文本，不代表官网判题结果。")
          if specialJudge { Text("本题可能存在多种正确输出或误差判定，请以官网结果为准。") }
          Text(String(format: "本机总耗时 %.0f ms（含编译）", run.durationMS))
          Text(run.environment)
          Text("代码版本 \(run.revision.hash.prefix(8))")
          output("本次输入", run.input)
        }.font(.subheadline).foregroundStyle(.secondary).padding(.top, 12)
      }.font(.subheadline)
    }.padding(.vertical, 4)
  }
  private func output(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      Text(text.isEmpty ? "（空）" : text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(PocketStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
    }
  }
}

struct OfficialResultView: View {
  let attempt: SubmissionAttempt
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VerdictCard(verdict: .official(attempt), scope: "Codeforces 官方判题")
      if let id = attempt.submissionID {
        Text("#\(String(id)) · @\(attempt.handle)").font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
        if attempt.sourceVerified != true { Text("手动关联记录 · 未核对源码").font(.subheadline).foregroundStyle(PocketStyle.amber) }
      }
      if let count = attempt.tested, count >= 0 { Text("已通过 \(count) 个测试").font(.subheadline) }
      if attempt.testset == "PRETESTS", attempt.verdict == "OK" { Text("当前为预测试结果，系统测试后可能变化。").font(.subheadline).foregroundStyle(.secondary) }
      DisclosureGroup("提交详情") {
        VStack(alignment: .leading, spacing: 12) {
          Text(attempt.language ?? attempt.revision.language.rawValue)
          Text(attempt.createdAt.formatted(date: .abbreviated, time: .standard))
          if let ms = attempt.timeConsumedMillis { Text("耗时 \(ms) ms") }
          if let bytes = attempt.memoryConsumedBytes { Text("内存 \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))") }
          Text(attempt.note)
          DisclosureGroup("提交时的代码") { CodeSnapshot(source: attempt.revision.source, python: attempt.revision.language == .python) }
        }.font(.subheadline).padding(.top, 12)
      }.font(.subheadline)
    }
  }
}
