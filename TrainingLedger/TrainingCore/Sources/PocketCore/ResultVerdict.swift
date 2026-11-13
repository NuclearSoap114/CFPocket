import Foundation

/// Presentation never upgrades execution success or an unconfirmed send into acceptance.
public struct ResultVerdict: Equatable, Sendable {
  public enum Tone: Sendable { case success, failure, caution, neutral }
  public let code: String
  public let title: String
  public let tone: Tone
  public init(_ code: String, _ title: String, _ tone: Tone) { self.code = code; self.title = title; self.tone = tone }

  public static func local(_ run: LocalRun, specialJudge: Bool) -> Self {
    switch run.status {
    case "ok":
      guard let matches = run.textMatches else { return Self("RUN", "运行完成 · 未设置期望输出", .neutral) }
      if specialJudge { return Self(matches ? "MATCH" : "DIFF", matches ? "文本一致 · 需官网判题" : "文本不同 · 需官网判题", .caution) }
      return matches ? Self("AC", "样例通过", .success) : Self("WA", "输出不一致", .failure)
    case "compile-error": return Self("CE", "编译错误", .failure)
    case "runtime-error": return Self("RE", "运行错误", .failure)
    case "timeout": return Self("TLE", "运行超时", .failure)
    case "output-limit": return Self("OLE", "输出超限", .failure)
    case "compile-timeout": return Self("TIME", "编译超时", .caution)
    case "stopped": return Self("STOP", "已停止", .neutral)
    case "unsupported-feature": return Self("ENV", "运行环境不支持", .caution)
    case "resource-error": return Self("ENV", "运行进程被系统终止", .caution)
    case "message-limit": return Self("LIMIT", "运行消息超限", .caution)
    default: return Self("ENV", "运行环境异常", .caution)
    }
  }

  public static func batch(_ runs: [LocalRun], total: Int, specialJudge: Bool) -> Self {
    let results = runs.map { local($0, specialJudge: specialJudge) }
    guard total > 0, runs.count == total else { return Self("STOP", "样例未全部运行", .neutral) }
    if let failure = results.first(where: { $0.tone == .failure }) { return Self(failure.code, "有样例未通过", .failure) }
    if results.allSatisfy({ $0.code == "AC" }) { return Self("AC", "全部样例通过", .success) }
    return results.first(where: { $0.code != "AC" }) ?? Self("RUN", "运行完成", .neutral)
  }

  public static func official(_ attempt: SubmissionAttempt) -> Self {
    guard attempt.submissionID != nil, [.final, .judging, .tracking].contains(attempt.state) else {
      switch attempt.state {
      case .sending: return Self("SEND", "正在提交", .neutral)
      case .uncertain: return Self("WAIT", "正在确认提交", .caution)
      case .notSent: return Self("READY", "尚未发送", .neutral)
      case .networkFailure: return Self("WAIT", "等待连接恢复", .caution)
      case .awaitingAuthentication: return Self("LOGIN", "需要登录或验证", .caution)
      default: return Self("WAIT", "等待官方结果", .neutral)
      }
    }
    switch attempt.verdict {
    case "OK": return Self("AC", attempt.testset == "PRETESTS" ? "预测试通过" : attempt.testset == "SAMPLES" ? "官方样例通过" : "通过", .success)
    case "WRONG_ANSWER": return Self("WA", "答案错误", .failure)
    case "COMPILATION_ERROR": return Self("CE", "编译错误", .failure)
    case "RUNTIME_ERROR": return Self("RE", "运行错误", .failure)
    case "TIME_LIMIT_EXCEEDED": return Self("TLE", "运行超时", .failure)
    case "MEMORY_LIMIT_EXCEEDED": return Self("MLE", "内存超限", .failure)
    case "IDLENESS_LIMIT_EXCEEDED": return Self("ILE", "交互等待超时", .failure)
    case "PARTIAL": return Self("PART", "部分得分", .caution)
    case "CHALLENGED": return Self("HACK", "被成功挑战", .failure)
    case "SKIPPED": return Self("SKIP", "已跳过", .neutral)
    case "REJECTED": return Self("REJECT", "提交被拒绝", .caution)
    case "SECURITY_VIOLATED": return Self("SV", "安全限制", .failure)
    case "FAILED", "CRASHED", "INPUT_PREPARATION_CRASHED": return Self("FAIL", "官方判题异常", .caution)
    case "SUBMITTED": return Self("WAIT", "排队中", .neutral)
    case "TESTING": return Self("JUDGE", "正在判题", .neutral)
    case nil, "": return Self("WAIT", "等待官方结果", .neutral)
    default: return Self("OTHER", "官方状态：\(attempt.verdict ?? "未知")", .caution)
    }
  }
}
