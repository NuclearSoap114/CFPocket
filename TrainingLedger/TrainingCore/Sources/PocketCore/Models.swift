import Foundation
import CryptoKit

public enum PocketError: Error, LocalizedError, Equatable {
  case invalid(String), source(String), blocked(String), unavailable(String)
  public var errorDescription: String? {
    switch self { case .invalid(let s), .source(let s), .blocked(let s), .unavailable(let s): return s }
  }
}
public func fingerprint(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

public struct ProblemID: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
  public let contest: Int
  public let index: String
  public var id: String { index.first?.isNumber == true ? "\(contest)-\(index)" : description }
  public var description: String { "\(contest)\(index)" }
  public var url: URL { URL(string: "https://codeforces.com/contest/\(contest)/problem/\(index)")! }
  public init(contest: Int, index: String) throws {
    let value = index.uppercased()
    guard contest > 0, value.range(of: "^(?:[A-Z][0-9]{0,2}|[0-9]{2})$", options: .regularExpression) != nil else { throw PocketError.invalid("题号应为比赛 ID 和题目索引，例如 4 / A。") }
    self.contest = contest; self.index = value
  }
  public init(url: URL) throws {
    guard url.scheme == "https", url.host == "codeforces.com", url.user == nil, url.password == nil else { throw PocketError.invalid("不是 Codeforces 官方题目链接。") }
    let parts = url.path.split(separator: "/").map(String.init)
    if parts.count == 4, parts[0] == "contest", parts[2] == "problem", let contest = Int(parts[1]) {
      try self.init(contest: contest, index: parts[3])
    } else if parts.count == 4, parts[0] == "problemset", parts[1] == "problem", let contest = Int(parts[2]) {
      try self.init(contest: contest, index: parts[3])
    } else { throw PocketError.invalid("这个链接没有可识别的官方题号。") }
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(contest: c.decode(Int.self, forKey: .contest), index: c.decode(String.self, forKey: .index))
  }
}
public struct PocketProblem: Codable, Identifiable, Hashable, Sendable {
  public let key: ProblemID
  public var name: String
  public var rating: Int?
  public var tags: [String]
  public var solvedCount: Int?
  public var id: String { key.id }
  public init(key: ProblemID, name: String, rating: Int? = nil, tags: [String] = [], solvedCount: Int? = nil) { self.key = key; self.name = name; self.rating = rating; self.tags = tags; self.solvedCount = solvedCount }
}
public struct Sample: Codable, Sendable, Equatable, Identifiable {
  public var id: String { fingerprint(input + "\0" + output) }
  public var input: String
  public var output: String
  public init(input: String, output: String) { self.input = input; self.output = output }
}
public struct Statement: Codable, Sendable, Equatable {
  public let problem: ProblemID
  public let title: String
  public let html: String
  public let plainText: String
  public let samples: [Sample]
  public let fetchedAt: Date
  public let source: URL
  public let hash: String
  public let parserVersion: String
  public let requiresSpecialJudge: Bool
}
public enum PracticeMode: String, Codable, CaseIterable, Sendable { case practice = "赛后练习", virtual = "虚拟训练", competition = "比赛中" }
public struct ContestSafety: Codable, Sendable {
  public let phase: String
  public let checkedAt: Date
  public func allowsAI(mode: PracticeMode, now: Date = Date()) -> Bool {
    mode == .practice && phase == "FINISHED" && now.timeIntervalSince(checkedAt) >= 0 && now.timeIntervalSince(checkedAt) < 3600
  }
}
public struct EditorialEvidence: Codable, Sendable, Equatable {
  public enum Completeness: String, Codable, Sendable { case complete, partial, unavailable }
  public let problem: ProblemID
  public let source: URL
  public let author: String
  public let fetchedAt: Date
  public let modifiedAt: Date?
  public let association: String
  public let content: String
  public let hash: String
  public let completeness: Completeness
  public let reason: String
  public let parserVersion: String
  public var isUsable: Bool { completeness == .complete && !association.isEmpty && content.count > 200 && hash == fingerprint(content) }
}
public enum DraftStatus: String, Codable, CaseIterable, Sendable {
  case incomplete = "思路尚不完整", bug = "存在明确漏洞", complexity = "复杂度超限", proof = "证明待补充", noCounterexample = "小规模验证未发现反例", implementation = "待实现验证"
}
public struct DraftRevision: Codable, Sendable, Identifiable, Equatable {
  public let id: UUID
  public let number: Int
  public let createdAt: Date
  public let text: String
  public let status: DraftStatus
  public init(number: Int, text: String, status: DraftStatus = .incomplete) { id = UUID(); self.number = number; createdAt = Date(); self.text = text; self.status = status }
}
public enum CodeLanguage: String, Codable, Sendable, CaseIterable { case cpp = "C++20", python = "Python" }
public struct CodeRevision: Codable, Sendable, Equatable, Identifiable {
  public let id: UUID
  public let createdAt: Date
  public let source: String
  public let language: CodeLanguage
  public let hash: String
  public init(source: String, language: CodeLanguage) { id = UUID(); createdAt = Date(); self.source = source; self.language = language; hash = fingerprint(source) }
}
public struct Workspace: Codable, Sendable, Identifiable {
  public var id: String { problem.id }
  public let problem: ProblemID
  public var draft = ""
  public var chatDraft: String? = nil
  public var pendingChatQuestion: String? = nil
  public var revisions: [DraftRevision] = []
  public var cpp = "#include <iostream>\nusing namespace std;\n\nint main() {\n    ios::sync_with_stdio(false);\n    cin.tie(nullptr);\n    \n    return 0;\n}\n"
  public var python = "import sys\n\ndef solve():\n    data = sys.stdin.read().split()\n    \n\nif __name__ == '__main__':\n    solve()\n"
  public var language = CodeLanguage.cpp
  public var stdin = ""
  public var expected = ""
  public var notes = ""
  public var favorite = false
  public var updatedAt = Date()
  public var hintLevel = 0
  public var aiRecords: [TutorRecord] = []
  public var runs: [LocalRun] = []
  public var submissions: [SubmissionAttempt] = []
  public var mode: PracticeMode = .practice
  public init(problem: ProblemID) { self.problem = problem }
}
public struct LocalRun: Codable, Sendable, Identifiable {
  public let id: UUID
  public let revision: CodeRevision
  public let input: String
  public let expected: String?
  public let startedAt: Date
  public let status: String
  public let stdout: String
  public let stderr: String
  public let durationMS: Double
  public let environment: String
  /// Optional so runs saved by earlier versions remain readable.
  public var sampleNumber: Int?
  public var batchID: UUID?
  public var batchSize: Int?
  public init(revision: CodeRevision, input: String, expected: String?, status: String, stdout: String, stderr: String, durationMS: Double, environment: String) {
    id = UUID(); self.revision = revision; self.input = input; self.expected = expected; startedAt = Date(); self.status = status; self.stdout = stdout; self.stderr = stderr; self.durationMS = durationMS; self.environment = environment
  }
  public var textMatches: Bool? { guard status == "ok", let expected else { return nil }; return Self.normalize(stdout) == Self.normalize(expected) }
  private static func normalize(_ text: String) -> [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }
}
public struct CounterexampleEvidence: Codable, Sendable {
  public let revisionID: UUID
  public let input: String
  public let inputLegality: String
  public let claimedUserOutput: String
  public let correctOutput: String
  public let basis: String
  public let executedRunIDs: [UUID]
  public var hasExecutionEvidence: Bool { !executedRunIDs.isEmpty }
}
