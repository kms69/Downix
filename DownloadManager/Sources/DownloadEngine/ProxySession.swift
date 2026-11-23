import Foundation
import CFNetwork

/// Thread-safe holder for the active proxy. NetworkManager is @MainActor, so the
/// download engine (SegmentDownloader, ExternalToolRunner, ...) reads from here instead.
public final class ActiveProxyStore: @unchecked Sendable {
    public static let shared = ActiveProxyStore()
    private let lock = NSLock()
    private var current: ProxyConfig?
    private var synced = false

    public var proxy: ProxyConfig? {
        lock.lock(); defer { lock.unlock() }
        if synced { return current }
        // NetworkManager hasn't synced yet (early in launch): read the saved settings.
        return Self.loadPersisted()
    }

    public func update(_ proxy: ProxyConfig?) {
        lock.lock(); current = proxy; synced = true; lock.unlock()
    }

    private static func loadPersisted() -> ProxyConfig? {
        guard let data = UserDefaults.standard.data(forKey: "com.downloadmanager.networkConfiguration"),
              let cfg = try? JSONDecoder().decode(NetworkConfiguration.self, from: data) else { return nil }
        return cfg.getActiveProxy()
    }
}

public enum ProxySession {
    static var debug: Bool { ProcessInfo.processInfo.environment["PROXY_DEBUG"] != nil }

    public static func dictionary(for proxy: ProxyConfig) -> [String: Any] {
        switch proxy.type {
        case .http, .https:
            return [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: proxy.host,
                kCFNetworkProxiesHTTPSPort as String: proxy.port
            ]
        case .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: proxy.host,
                kCFNetworkProxiesSOCKSPort as String: proxy.port
            ]
        case .system:
            return CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        default:
            return [:]
        }
    }

    /// Session config carrying the active proxy, if any. Safe to call from any thread.
    public static func makeConfiguration(base: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        if let p = ActiveProxyStore.shared.proxy, p.isValid {
            base.connectionProxyDictionary = dictionary(for: p)
            if debug { print("[ProxySession] \(p.type.rawValue) proxy \(p.host):\(p.port)") }
        } else if debug {
            print("[ProxySession] no active proxy - connecting directly")
        }
        return base
    }

    public static func makeSession() -> URLSession {
        URLSession(configuration: makeConfiguration())
    }

    /// yt-dlp is a separate process, so it needs the proxy as an argument (ffmpeg etc. are left alone).
    public static func arguments(for binary: String, _ args: [String]) -> [String] {
        let name = (binary as NSString).lastPathComponent.lowercased()
        return name.hasPrefix("yt-dlp") ? ytDlpArgs() + args : args
    }

    public static func ytDlpArgs() -> [String] {
        guard let p = ActiveProxyStore.shared.proxy, p.isValid else { return [] }
        let hostPart = "\(credentials(p))\(p.host):\(p.port)"
        switch p.type {
        case .http, .https: return ["--proxy", "http://\(hostPart)"]
        case .socks5:       return ["--proxy", "socks5h://\(hostPart)"]
        default:            return []
        }
    }

    private static func credentials(_ p: ProxyConfig) -> String {
        guard p.requiresAuthentication, !p.username.isEmpty else { return "" }
        let u = p.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? p.username
        let pw = p.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? p.password
        return "\(u):\(pw)@"
    }
}
