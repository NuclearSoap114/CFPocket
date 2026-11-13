import Foundation
import SwiftSoup

public enum TrainingHTML {
  public static func parse(_ html: String, account: OJAccount, url: URL) throws -> SubmissionPage {
    let doc = try SwiftSoup.parse(html, url.absoluteString)
    let text = try doc.text()
    guard !text.contains("Cerberus Challenge"), !text.contains("Just a moment"),
      !text.contains("Access denied"), !text.contains("验证您是人类")
    else { throw TrainingError.needsBrowser("请在网页连接中完成来源的安全校验。") }
    if account.oj == .luogu {
      guard let json = try doc.select("script#lentille-context").first()?.data(), !json.isEmpty
      else { throw TrainingError.needsBrowser("洛谷页面尚未准备好，请在网页连接中打开评测记录后重试。") }
      let page =
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
          $0.name == "page"
        })?.value.flatMap(Int.init) ?? 1
      return try APIParser.luogu(Data(json.utf8), account: account, page: page)
    }
    if account.oj == .vjudge, let data = text.data(using: .utf8),
      text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
    {
      return try APIParser.vjudge(data, account: account, url: url)
    }
    var records: [Submission] = []
    var recognized = false
    for row in try doc.select("table tbody tr").array() {
      let cells = try row.select("td").array()
      if cells.isEmpty { continue }
      switch account.oj {
      case .nowcoder:
        guard cells.count == 9, let link = try cells[0].select("a[href*=submissionId]").first(),
          let problem = try cells[1].select("a[href*=/acm/problem/]").first()
        else { continue }
        recognized = true
        let rURL = try link.absUrl("href")
        let pURL = try problem.absUrl("href")
        guard
          let id = URLComponents(string: rURL)?.queryItems?.first(where: {
            $0.name == "submissionId"
          })?.value, let stamp = TrainingDates.parse(try cells[8].text())
        else { throw TrainingError.invalid("牛客记录ID或提交时间未识别。") }
        let verdict = try cells[2].text()
        records.append(
          Submission(
            accountID: account.id, recordID: id, timestamp: stamp,
            problemID: URL(string: pURL)?.lastPathComponent ?? "", title: try problem.text(),
            problemURL: pURL, verdict: verdict, accepted: verdict.contains("答案正确"),
            language: try cells[7].text(), recordURL: rURL))
      case .qoj:
        guard cells.count == 9, let link = try cells[0].select("a[href*=/submission/]").first(),
          let problem = try cells[1].select("a[href*=/problem/]").first()
        else { continue }
        recognized = true
        guard try cells[2].select("a").first()?.text().lowercased() == account.handle.lowercased()
        else { throw TrainingError.invalid("QOJ列表包含其他人的提交，请核对筛选用户名。") }
        let time =
          try cells[8].select("time[datetime]").first()?.attr("datetime") ?? cells[8].text()
        guard let stamp = TrainingDates.parse(time) else {
          throw TrainingError.invalid("QOJ提交时间未识别。")
        }
        let verdict = try cells[3].text()
        let pURL = try problem.absUrl("href")
        let rURL = try link.absUrl("href")
        records.append(
          Submission(
            accountID: account.id, recordID: URL(string: rURL)?.lastPathComponent ?? "",
            timestamp: stamp, problemID: URL(string: pURL)?.lastPathComponent ?? "",
            title: try problem.text(), problemURL: pURL, verdict: verdict,
            accepted: verdict.hasPrefix("AC"), language: try cells[6].text(), recordURL: rURL))
      case .hydro:
        guard cells.count >= 7, let link = try cells[0].select("a[href*=/record/]").first(),
          let problem = try cells[1].select("a[href*=/p/]").first(),
          let user = try cells[2].select("a[href*=/user/]").first()
        else { continue }
        recognized = true
        let userID = URL(string: try user.absUrl("href"))?.lastPathComponent ?? ""
        let name = try user.text()
        guard userID == account.handle || name.lowercased() == account.handle.lowercased() else {
          throw TrainingError.invalid("Hydro筛选未生效，返回了其他人的记录。")
        }
        let time =
          try cells.last!.select("[data-timestamp]").first()?.attr("data-timestamp")
          ?? cells.last!.text()
        guard let stamp = TrainingDates.parse(time) else {
          throw TrainingError.invalid("Hydro提交时间未识别。")
        }
        let verdict = try cells[0].text()
        let pURL = try problem.absUrl("href")
        let rURL = try link.absUrl("href")
        records.append(
          Submission(
            accountID: account.id, recordID: URL(string: rURL)?.lastPathComponent ?? "",
            timestamp: stamp, problemID: URL(string: pURL)?.lastPathComponent ?? "",
            title: try problem.text(), problemURL: pURL, verdict: verdict,
            accepted: verdict.contains("Accepted"), language: try cells[5].text(), recordURL: rURL))
      default: break
      }
    }
    if records.isEmpty {
      let empty: Bool
      switch account.oj {
      case .hydro: empty = text.contains("目前没有符合过滤条件的任务") || text.contains("No records match")
      case .qoj: empty = text.contains("No submissions") || text.contains("No Submission")
      case .nowcoder:
        empty = text.contains("暂无提交记录") || text.contains("暂无数据") || text.contains("暂时没有")
      default: empty = false
      }
      guard empty, url.host == account.recordsURL.host else {
        throw TrainingError.needsBrowser("\(account.oj.name)尚未识别到完整的提交列表，请在网页连接中打开记录页；原记录继续保留。")
      }
    } else {
      guard recognized else { throw TrainingError.invalid("未识别来源列表。") }
    }
    for r in records { try r.validate() }
    guard Set(records.map(\.id)).count == records.count else {
      throw TrainingError.invalid("来源单页出现重复记录，已停止更新。")
    }
    let page =
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "page"
      })?.value.flatMap(Int.init) ?? 1
    var next: URL?
    for a in try doc.select("a[href]").array() {
      let href = try a.absUrl("href")
      let label = try a.text()
      guard let u = URL(string: href), u.host == url.host else { continue }
      let p = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
        $0.name == "page"
      })?.value.flatMap(Int.init)
      if p == page + 1
        && (label == "下一页" || label == "Next" || label == String(page + 1) || label.isEmpty)
      {
        next = u
        break
      }
    }
    // Hydro source uses numbered pages; confirm an explicit empty page rather than assuming a page size.
    if account.oj == .hydro, !records.isEmpty {
      var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
      c.queryItems =
        (c.queryItems ?? []).filter { $0.name != "page" } + [
          .init(name: "page", value: String(page + 1))
        ]
      next = c.url
    }
    return SubmissionPage(
      rows: records, nextURL: next, finished: next == nil, source: "\(account.oj.name)公开提交页面")
  }
  public static func problemMetadata(_ html: String, oj: OJ) throws -> (String?, Difficulty?) {
    let doc = try SwiftSoup.parse(html)
    let title = try doc.title()
    let content = try doc.text()
    guard !title.contains("Cerberus"), !title.contains("Just a moment"),
      !content.contains("Access denied")
    else { throw TrainingError.needsBrowser("题目页面需要网页校验，未用校验页覆盖题名。") }
    switch oj {
    case .vjudge:
      return (
        try doc.select("h2").first()?.text().replacingOccurrences(of: "\u{f006}", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines), nil
      )
    case .nowcoder:
      let text = try doc.text()
      let regex = try NSRegularExpression(pattern: "难度[：: ]*([0-9]+)")
      if let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let r = Range(m.range(at: 1), in: text), let value = Int(text[r])
      {
        return (nil, Difficulty(value: value, label: "难度\(value)", source: "牛客官方难度分级"))
      }
      return (nil, nil)
    default: return (nil, nil)
    }
  }
}
extension APIParser {
  public static func vjudge(_ data: Data, account: OJAccount, url: URL) throws -> SubmissionPage {
    let d = try JSONHelpers.object(data)
    guard let raw = d["data"] as? [[String: Any]], d["draw"] != nil else {
      throw TrainingError.needsBrowser("VJudge接口未识别，请先连接网页。")
    }
    var rows: [Submission] = []
    for s in raw {
      guard let id = JSONHelpers.string(s["runId"]), let ms = JSONHelpers.int(s["time"]),
        let oj = s["oj"] as? String, let pid = s["probNum"] as? String,
        let verdict = s["status"] as? String, let user = s["userName"] as? String,
        user.lowercased() == account.handle.lowercased()
      else { throw TrainingError.invalid("VJudge提交字段或用户名不匹配。") }
      let problemID = "\(oj)-\(pid)"
      let escaped =
        problemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? problemID
      let r = Submission(
        accountID: account.id, recordID: id,
        timestamp: Date(timeIntervalSince1970: Double(ms) / 1000), problemID: problemID,
        title: problemID, problemURL: "https://vjudge.net/problem/\(escaped)", verdict: verdict,
        accepted: verdict == "Accepted", language: s["language"] as? String,
        recordURL: "https://vjudge.net/solution/\(id)")
      try r.validate()
      rows.append(r)
    }
    var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    var q = c.queryItems ?? []
    let length = q.first(where: { $0.name == "length" })?.value.flatMap(Int.init) ?? 100
    let start = q.first(where: { $0.name == "start" })?.value.flatMap(Int.init) ?? 0
    // VJudge's9999999 total is a sentinel, not a real record count.
    let done = rows.count < length
    q.removeAll { $0.name == "start" }
    q.append(.init(name: "start", value: String(start + length)))
    c.queryItems = q
    return SubmissionPage(
      rows: rows, nextURL: done ? nil : c.url, finished: done, source: "VJudge公开提交接口")
  }
}
