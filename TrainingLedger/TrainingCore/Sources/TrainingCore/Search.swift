import Foundation

public enum TrainingSearch {
  public static func folded(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_CN")
    ).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  public static func filter(
    _ rows: [Submission], query: String, onlyAccepted: Bool = false, day: Date? = nil,
    accountAliases: [UUID: String] = [:]
  ) throws -> [Submission] {
    let needle = folded(query)
    let start = day.map(TrainingDates.day)
    let end = start.flatMap { TrainingDates.calendar.date(byAdding: .day, value: 1, to: $0) }
    var result: [Submission] = []
    result.reserveCapacity(min(rows.count, 1000))
    for (i, row) in rows.enumerated() {
      if i % 512 == 0 { try Task.checkCancellation() }
      if onlyAccepted && !row.accepted { continue }
      if let start, let end, !(row.timestamp >= start && row.timestamp < end) { continue }
      if !needle.isEmpty,
        !folded(row.title + " " + row.problemID + " " + (accountAliases[row.accountID] ?? ""))
          .contains(needle)
      {
        continue
      }
      result.append(row)
    }
    return result
  }
}
