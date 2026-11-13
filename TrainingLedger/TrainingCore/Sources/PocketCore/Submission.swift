import Foundation
import TrainingCore

public enum SubmissionState: String, Codable, Sendable {
  case notSent = "未提交", sending = "正在发送", uncertain = "发送结果待确认", awaitingAuthentication = "需要官方网页操作", tracking = "已获得提交 ID", judging = "排队／判题中", final = "最终结果", networkFailure = "网络失败"
}
public struct SubmissionAttempt: Codable, Sendable, Identifiable {
  public let id: UUID
  public let problem: ProblemID
  public let revision: CodeRevision
  public let handle: String
  public let createdAt: Date
  public var state: SubmissionState
  public var submissionID: Int?
  public var verdict: String?
  public var language: String?
  public var tested: Int?
  public var testset: String?
  public var timeConsumedMillis: Int?
  public var memoryConsumedBytes: Int?
  public var sourceVerified: Bool?
  public var note: String
  public init(problem: ProblemID, revision: CodeRevision, handle: String) {
    id = UUID(); self.problem = problem; self.revision = revision; self.handle = handle; createdAt = Date(); state = .awaitingAuthentication
    note = "代码已冻结，等待你确认提交。"
  }
}
public protocol SubmissionAdapter: Sendable {
  func officialURL(problem: ProblemID) -> URL
  func reconcile(_ attempt: SubmissionAttempt, submissionID: Int) async throws -> SubmissionAttempt
}
public actor OfficialWebSubmissionAdapter: SubmissionAdapter {
  private let http: any HTTPGetting
  public init(http: any HTTPGetting = PublicHTTPClient()) { self.http = http }
  public nonisolated func officialURL(problem: ProblemID) -> URL { URL(string: "https://codeforces.com/contest/\(problem.contest)/submit")! }
  public func reconcile(_ attempt: SubmissionAttempt, submissionID: Int) async throws -> SubmissionAttempt {
    guard submissionID > 0, !attempt.handle.isEmpty, attempt.handle.range(of: "^[A-Za-z0-9_.-]{1,24}$", options: .regularExpression) != nil else { throw PocketError.invalid("请填写公开 handle 与实际提交 ID。") }
    let handle = attempt.handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    let data = try await http.get(URL(string: "https://codeforces.com/api/user.status?handle=\(handle)&from=1&count=100")!)
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard root?["status"] as? String == "OK", let rows = root?["result"] as? [[String: Any]], let row = rows.first(where: { $0["id"] as? Int == submissionID }) else { throw PocketError.source("最近 100 条官方提交中未找到该 ID。未自动绑定其他提交，也不会重发代码。") }
    guard let problem = row["problem"] as? [String: Any], problem["contestId"] as? Int == attempt.problem.contest, problem["index"] as? String == attempt.problem.index, let author = row["author"] as? [String: Any], let members = author["members"] as? [[String: Any]], members.contains(where: { ($0["handle"] as? String)?.lowercased() == attempt.handle.lowercased() }), let language = row["programmingLanguage"] as? String else { throw PocketError.invalid("提交 ID 的账号或题号不匹配。") }
    let lower = language.lowercased()
    guard attempt.revision.language == .cpp ? (lower.contains("c++") || lower.contains("g++") || lower.contains("clang")) : (lower.contains("python") || lower.contains("pypy")) else { throw PocketError.invalid("提交 ID 的语言与冻结代码版本不一致。") }
    var value = attempt; value.submissionID = submissionID; value.language = language; value.verdict = row["verdict"] as? String; value.tested = row["passedTestCount"] as? Int
    value.testset = row["testset"] as? String
    value.timeConsumedMillis = (row["timeConsumedMillis"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
    value.memoryConsumedBytes = (row["memoryConsumedBytes"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
    value.state = value.verdict == nil || ["", "TESTING", "SUBMITTED"].contains(value.verdict ?? "") ? .judging : .final
    value.note = value.sourceVerified == true ? "已核对官网提交源码与冻结版本，判题结果来自 CF。" : "结果来自 CF user.status；此记录由你手动关联，尚未核对官网源码。"
    return value
  }
}
