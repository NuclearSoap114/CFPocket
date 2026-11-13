import Foundation

/// Problem ratings use CF's current rank color bands; these are not difficulty names.
public enum DifficultyPalette {
  public static func codeforces(_ rating: Int?) -> UInt32 {
    guard let rating, rating > 0 else { return 0x808080 }
    switch rating {
    case ..<1200: return 0x808080
    case ..<1400: return 0x008000
    case ..<1600: return 0x03A89E
    case ..<1900: return 0x0000FF
    case ..<2100: return 0xAA00AA
    case ..<2400: return 0xFF8C00
    default: return 0xFF0000
    }
  }
  /// Luogu's 0…8 current difficulty IDs, including the cyan 提高 level.
  public static func luogu(_ difficulty: Int) -> UInt32 {
    let colors: [UInt32] = [0xBFBFBF, 0xFE4C61, 0xF39C11, 0xFFC116, 0x52C41A, 0x13C2C2, 0x3498DB, 0x9D3DCF, 0x0E1D69]
    return colors.indices.contains(difficulty) ? colors[difficulty] : colors[0]
  }
}
