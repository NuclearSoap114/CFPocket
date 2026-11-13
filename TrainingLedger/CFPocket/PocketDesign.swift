import SwiftUI
import TrainingCore

/// One palette across navigation, reading, conversation and statistics.
enum PocketStyle {
  static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
      let value = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255, blue: CGFloat(value & 255)/255, alpha: 1)
    })
  }
  static let accent = adaptive(0x12685D, 0x80D8C8)
  static let action = adaptive(0x176B60, 0x226E65)
  static let canvas = adaptive(0xF2F5F0, 0x0E181E)
  static let paper = adaptive(0xFFFFFF, 0x192A30)
  static let readingPaper = adaptive(0xFAFBF8, 0x121E23)
  static let ink = adaptive(0x20353D, 0xECF3EF)
  static let line = adaptive(0xDEE7DF, 0x2F4349)
  static let wash = adaptive(0xE5F0E8, 0x213D3B)
  static let amber = adaptive(0xA85C20, 0xEBC18C)
  static let teal = accent
  static let hero = Color(red: 0.09, green: 0.19, blue: 0.23)
  static let heroAccent = Color(red: 0.67, green: 0.89, blue: 0.75)
}
extension View {
  func pocketSurface() -> some View {
    padding(20).background(PocketStyle.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(PocketStyle.line.opacity(0.7), lineWidth: 0.7) }
  }
}
struct PocketPrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.subheadline.weight(.semibold)).padding(.horizontal, 17).padding(.vertical, 12)
      .foregroundStyle(.white).background(PocketStyle.action, in: Capsule())
      .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
  }
}
struct PocketSectionTitle: View {
  let title: String
  var subtitle: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 9) { RoundedRectangle(cornerRadius: 2).fill(PocketStyle.accent).frame(width: 4, height: 18); Text(title).font(.title3.bold()).foregroundStyle(PocketStyle.ink) }
      if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct PocketMetric: View {
  let value: String
  let title: String
  var color: Color = .primary
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(value).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(color)
      Text(title).font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
  }
}
struct PocketDestinationLabel: View {
  let title: String
  let detail: String
  let symbol: String
  var color: Color = PocketStyle.accent
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(color)
        .frame(width: 44, height: 44).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline).foregroundStyle(PocketStyle.ink)
        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 4)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.frame(minHeight: 50).contentShape(Rectangle()).accessibilityElement(children: .combine)
  }
}
struct PracticeEntryTile: View {
  let title: String; let detail: String; let symbol: String; let color: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack { Image(systemName: symbol).font(.system(size: 23, weight: .medium)).foregroundStyle(color); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary) }
      VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline).foregroundStyle(PocketStyle.ink); Text(detail).font(.caption).foregroundStyle(.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading).pocketSurface()
  }
}
