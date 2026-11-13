import Foundation

public enum ReaderImagePolicy {
  /// External article images are data, not executable content. Accept public HTTPS
  /// hosts instead of maintaining a brittle list of two image CDNs.
  public static func url(_ raw: String, base: URL) -> URL? {
    let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty, let absolute = URL(string: raw, relativeTo: base)?.absoluteURL,
          var parts = URLComponents(url: absolute, resolvingAgainstBaseURL: true),
          ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
          parts.user == nil, parts.password == nil,
          parts.port == nil || parts.port == 80 || parts.port == 443,
          var host = parts.host?.lowercased() else { return nil }
    if host.hasSuffix(".") { host.removeLast() }
    guard host.range(of: #"\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}\z"#, options: .regularExpression) != nil,
          ![".localhost", ".local", ".internal", ".lan", ".home", ".test", ".invalid"].contains(where: host.hasSuffix) else { return nil }
    parts.scheme = "https"; parts.port = nil; parts.fragment = nil
    parts.host = host == "cdn.luogu.org" ? "cdn.luogu.com.cn" : host
    return parts.url
  }
}
