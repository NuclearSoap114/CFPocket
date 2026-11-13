import Foundation

public struct PaletteToken: Sendable {
  public let light: UInt32
  public let dark: UInt32
  public init(_ light: UInt32, _ dark: UInt32) {
    self.light = light
    self.dark = dark
  }
}
public enum TrainingPalette {
  public static let accent = PaletteToken(0x3556C8, 0xA6B8FF)
  public static let secondary = PaletteToken(0x5E6474, 0xB8BECD)
  public static let success = PaletteToken(0x176E4E, 0x8DE0B7)
  public static let warning = PaletteToken(0x915200, 0xFFD18A)
  public static let favorite = PaletteToken(0x925600, 0xF7C96D)
  public static func source(_ oj: OJ) -> PaletteToken {
    switch oj {
    case .codeforces: PaletteToken(0x275FAD, 0x9EC1FF)
    case .atcoder: PaletteToken(0x7240A8, 0xD4AFF3)
    case .luogu: PaletteToken(0x99531B, 0xF4BA8C)
    case .nowcoder: PaletteToken(0x1A7153, 0x8BD8B7)
    case .qoj: PaletteToken(0x5C4AB4, 0xBFB0FA)
    case .hydro: PaletteToken(0x0B7279, 0x85D7DD)
    case .vjudge: PaletteToken(0xA33F6B, 0xF0A8C9)
    }
  }
  public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    func luminance(_ c: UInt32) -> Double {
      let rgb = [
        Double((c >> 16) & 255) / 255, Double((c >> 8) & 255) / 255, Double(c & 255) / 255,
      ].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
      return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
    }
    let x = luminance(a)
    let y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
  }
  public static func blend(_ front: UInt32, onto back: UInt32, opacity: Double) -> UInt32 {
    let r = UInt32(
      (Double((front >> 16) & 255) * opacity + Double((back >> 16) & 255) * (1 - opacity)).rounded()
    )
    let g = UInt32(
      (Double((front >> 8) & 255) * opacity + Double((back >> 8) & 255) * (1 - opacity)).rounded())
    let b = UInt32((Double(front & 255) * opacity + Double(back & 255) * (1 - opacity)).rounded())
    return (r << 16) | (g << 8) | b
  }
}
