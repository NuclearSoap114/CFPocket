import SwiftUI
import TrainingCore

enum Theme {
  static func adaptive(_ token: PaletteToken) -> Color {
    Color(
      uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? token.dark : token.light
        return UIColor(
          red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
          blue: Double(hex & 255) / 255, alpha: 1)
      })
  }
  static let onAccent = adaptive(PaletteToken(0xFFFFFF, 0x14224D))
  static let accent = adaptive(TrainingPalette.accent)
  static let secondaryText = adaptive(TrainingPalette.secondary)
  static let success = adaptive(TrainingPalette.success)
  static let warning = adaptive(TrainingPalette.warning)
  static let favorite = adaptive(TrainingPalette.favorite)
  static let canvas = Color(uiColor: .systemGroupedBackground)
  static func color(_ oj: OJ) -> Color { adaptive(TrainingPalette.source(oj)) }
  static func avatar(_ id: UUID) -> Color {
    let choices = [accent, color(.hydro), color(.atcoder), color(.nowcoder)]
    let hash = id.uuidString.utf8.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) }
    return choices[Int(hash) % choices.count]
  }
}

extension View {
  func trainingCard() -> some View {
    padding(18).background(
      Color(uiColor: .secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
}
struct OJBadge: View {
  let oj: OJ
  var body: some View {
    Text(oj.shortName).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(
      .vertical, 5
    ).background(Theme.color(oj).opacity(0.09), in: Capsule()).foregroundStyle(Theme.color(oj))
  }
}
struct SyncButton: View {
  @Environment(TrainingStore.self) private var store
  var ids: Set<UUID>? = nil
  var body: some View {
    Button {
      if store.isBusy { store.stop() } else { store.refresh(accountIDs: ids) }
    } label: {
      if store.isBusy {
        Image(systemName: "stop.circle")
      } else {
        Image(systemName: "arrow.clockwise")
      }
    }.accessibilityLabel(store.isBusy ? "停止同步" : "同步训练记录").disabled(store.storageFailure)
  }
}
struct ProgressBanner: View {
  @Environment(TrainingStore.self) private var store
  var body: some View {
    if store.isBusy {
      HStack(spacing: 10) {
        ProgressView()
        Text(store.progress.isEmpty ? "正在准备同步" : store.progress).font(.footnote).lineLimit(2)
        Spacer()
        Button("停止") { store.stop() }.font(.footnote)
      }.padding(12).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
  }
}
struct MetricRow: View {
  let stats: TrainingStats
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        VStack(spacing: 12) {
          LabeledContent("已收集提交", value: stats.submissions.formatted())
          LabeledContent("通过题目", value: stats.uniqueSolved.formatted())
          LabeledContent("活跃天", value: stats.activeDays.formatted())
        }.font(.subheadline).monospacedDigit()
      } else {
        HStack(spacing: 0) {
          cell("已收集提交", stats.submissions)
          Divider().frame(height: 35)
          cell("通过题目", stats.uniqueSolved)
          Divider().frame(height: 35)
          cell("活跃天", stats.activeDays)
        }
      }
    }.trainingCard()
  }
  private func cell(_ name: String, _ count: Int) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(name).font(.caption).foregroundStyle(Theme.secondaryText)
      Text(count, format: .number).font(.title2.weight(.bold)).monospacedDigit()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct AccountStatus: View {
  @Environment(TrainingStore.self) private var store
  let account: OJAccount
  var body: some View {
    let info = store.info(account.id)
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        OJBadge(oj: account.oj)
        Text(account.handle).font(.subheadline.weight(.medium))
        Spacer()
        if store.activeAccount == account.id { ProgressView() }
      }
      if let error = info.error {
        Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(
          Theme.warning)
      }
      Text(info.coverage).font(.caption).foregroundStyle(Theme.secondaryText)
      if let time = info.lastSuccess {
        Text("上次成功 " + TrainingDates.text(time)).font(.caption2).foregroundStyle(
          Theme.secondaryText)
      }
      if account.oj != .codeforces && account.oj != .atcoder {
        Button("网页连接") { store.connect(account) }.font(.subheadline)
      }
    }.padding(.vertical, 5)
  }
}
struct SubmissionRow: View {
  @Environment(TrainingStore.self) private var store
  let row: Submission
  var showPerson = false
  @State private var expanded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            if let a = store.account(row.accountID) { OJBadge(oj: a.oj) }
            if showPerson {
              Text(store.owner(row.accountID)?.displayName ?? "未命名人物").font(
                .caption.weight(.semibold)
              ).foregroundStyle(.primary)
            }
            Spacer(minLength: 4)
            Text(row.accepted ? "AC" : row.verdict).font(.caption2.weight(.semibold)).lineLimit(1)
              .foregroundStyle(row.accepted ? Theme.success : Theme.warning)
            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(
              .caption2.weight(.semibold)
            ).foregroundStyle(Theme.secondaryText)
          }
          Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).frame(
            maxWidth: .infinity, alignment: .leading
          ).fixedSize(horizontal: false, vertical: true)
          HStack(alignment: .firstTextBaseline) {
            Text(row.problemID).font(.caption.monospaced()).foregroundStyle(Theme.secondaryText)
              .lineLimit(1)
            Spacer(minLength: 8)
            if let difficulty = row.difficulty {
              Text(difficulty.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            } else {
              Text("暂无难度").font(.caption).foregroundStyle(Theme.secondaryText)
            }
          }
          HStack {
            if let a = store.account(row.accountID) {
              Text(a.handle).font(.caption2.monospaced()).lineLimit(1)
            }
            Spacer()
            Text(TrainingDates.text(row.timestamp)).monospacedDigit()
          }.font(.caption2).foregroundStyle(Theme.secondaryText)
        }.contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityLabel(
        (showPerson ? (store.owner(row.accountID)?.displayName ?? "") + "，" : "") + row.title + "，"
          + row.verdict
      ).accessibilityHint("展开查看难度来源、语言和原始提交")
      if expanded {
        Divider()
        if let owner = store.owner(row.accountID), let a = store.account(row.accountID) {
          LabeledContent("人物", value: owner.displayName).font(.caption)
          LabeledContent("平台ID", value: a.handle).font(.caption).textSelection(.enabled)
          if !a.platformName.isEmpty, a.platformName != a.handle {
            LabeledContent("平台昵称", value: a.platformName).font(.caption)
          }
        }
        if let d = row.difficulty {
          Text(d.source).font(.caption2).foregroundStyle(Theme.secondaryText)
        }
        if let language = row.language {
          Text(language).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        HStack {
          if let u = URL(string: row.problemURL) { Link("打开题目", destination: u) }
          Spacer()
          if let value = row.recordURL, let u = URL(string: value) { Link("原始提交", destination: u) }
        }.font(.subheadline).padding(.top, 3)
      }
    }.padding(.vertical, 10)
  }
}

struct EmptyTraining: View {
  let title: String
  let detail: String
  var body: some View {
    ContentUnavailableView(title, systemImage: "square.grid.3x3", description: Text(detail)).frame(
      maxWidth: .infinity
    ).padding(.vertical, 20)
  }
}
