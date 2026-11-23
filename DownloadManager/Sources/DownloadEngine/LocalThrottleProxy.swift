//
//  LocalThrottleProxy.swift
//  Download Manager for Mac
//
//  Created on October 26, 2026
//

import Foundation
import Darwin

/// Tiny in-process HTTP proxy that paces the data flowing through it.
///
/// yt-dlp only reads `--limit-rate` at launch, so live limit changes used to
/// require a process restart — which reset the transfer to zero on servers
/// without Range support. yt-dlp downloads now run through this proxy;
/// changing the limit just updates `rate` and the transfer keeps its progress.
final class LocalThrottleProxy: @unchecked Sendable {

    static let shared = LocalThrottleProxy()

    private let stateLock = NSLock()
    private var listenFD: Int32 = -1
    private var _port: UInt16 = 0

    private let rateBox = RateBox()

    /// One limiter for ALL paced relays: with parallel segment connections,
    /// their combined throughput (not each connection) must equal the rate.
    private let limiter: PacingLimiter

    /// Bytes/second applied to paced transfers; nil = unlimited.
    var rate: Int64? {
        get { rateBox.value }
        set { rateBox.value = newValue }
    }

    var port: UInt16? {
        stateLock.lock(); defer { stateLock.unlock() }
        return listenFD >= 0 ? _port : nil
    }

    private init() {
        let box = rateBox
        limiter = PacingLimiter(rateProvider: { [weak box] in box?.value ?? 0 })
    }

    /// Starts listening on an ephemeral 127.0.0.1 port. Idempotent.
    func ensureRunning() -> UInt16? {
        stateLock.lock()
        if listenFD >= 0 {
            let p = _port
            stateLock.unlock()
            return p
        }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { stateLock.unlock(); return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var bound: Int32 = -1
        withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bound = bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            stateLock.unlock()
            return nil
        }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                _ = getsockname(fd, sa, &len)
            }
        }
        _port = UInt16(bigEndian: actual.sin_port)
        listenFD = fd
        stateLock.unlock()

        signal(SIGPIPE, SIG_IGN)          // a dead socket must not kill the app
        Thread.detachNewThread { [weak self] in self?.acceptLoop(fd) }
        return _port
    }

    // MARK: - Accept / dispatch

    private func acceptLoop(_ fd: Int32) {
        while true {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let c = withUnsafeMutablePointer(to: &clientAddr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(fd, sa, &len)
                }
            }
            if c < 0 { break }
            Thread.detachNewThread { [weak self] in self?.handleConnection(c) }
        }
        close(fd)
        // The listener died; allow a later ensureRunning() to rebind.
        stateLock.lock()
        if listenFD == fd { listenFD = -1 }
        stateLock.unlock()
    }

    private func handleConnection(_ client: Int32) {
        defer { close(client) }
        guard let head = readHead(client) else { return }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/") else { return }
        let method = String(parts[0])
        let target = String(parts[1])
        let headers = Array(lines.dropFirst())

        if method == "CONNECT" {
            let hp = target.split(separator: ":", maxSplits: 1)
            guard hp.count == 2, let port = UInt16(hp[1]) else { return }
            guard let upstream = openUpstream(String(hp[0]), port) else {
                writeAll(client, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
                return
            }
            if writeAll(client, "HTTP/1.1 200 Connection Established\r\n\r\n") {
                tunnel(client: client, upstream: upstream)
            }
            close(upstream)
            return
        }

        guard let u = URL(string: target), let host = u.host,
              method == "GET" || method == "POST" else {
            writeAll(client, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
            return
        }
        guard let upstream = openUpstream(host, UInt16(u.port ?? 80)) else {
            writeAll(client, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        }
        let path = (u.path.isEmpty ? "/" : u.path) + (u.query.map { "?\($0)" } ?? "")
        var forward = "\(method) \(path) HTTP/1.1\r\n"
        for h in headers {
            let lower = h.lowercased()
            if lower.hasPrefix("proxy-connection:") || lower.hasPrefix("connection:") { continue }
            forward += h + "\r\n"
        }
        forward += "Connection: close\r\n\r\n"
        guard writeAll(upstream, forward) else {
            close(upstream)
            return
        }
        if method == "POST" {
            guard forwardRequestBody(client, upstream, headers) else {
                close(upstream)
                return
            }
        }
        relay(from: upstream, to: client, paced: true)
        close(upstream)
    }

    private func forwardRequestBody(_ client: Int32, _ upstream: Int32,
                                    _ headers: [String]) -> Bool {
        var length = 0
        for h in headers where h.lowercased().hasPrefix("content-length:") {
            length = Int(h.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        }
        var remaining = length
        var buf = [UInt8](repeating: 0, count: 16384)
        while remaining > 0 {
            let n = read(client, &buf, min(remaining, buf.count))
            if n <= 0 { return false }
            if !writeAll(upstream, Data(buf[..<n])) { return false }
            remaining -= n
        }
        return true
    }

    // MARK: - Relays

    /// Bidirectional tunnel (CONNECT). The download direction (upstream →
    /// client) is paced; client requests are small and pass through.
    ///
    /// `upstream` is owned by the caller, which closes it after this returns.
    /// The client→upstream thread must be fully done before then: it signals
    /// `done` and we join it here, otherwise a stray shutdown() could hit a
    /// recycled fd handed to the next connection (that stalled transfers).
    private func tunnel(client: Int32, upstream: Int32) {
        let done = DispatchSemaphore(value: 0)
        let c2u = Thread { [weak self] in
            self?.relay(from: client, to: upstream, paced: false)
            shutdown(upstream, SHUT_WR)
            done.signal()
        }
        c2u.start()
        relay(from: upstream, to: client, paced: true)
        shutdown(client, SHUT_RDWR)          // wake the c2u reader
        done.wait()                          // join: c2u no longer touches upstream
    }

    private func relay(from src: Int32, to dst: Int32, paced: Bool) {
        let buf = UnsafeMutableRawBufferPointer.allocate(byteCount: 256 * 1024, alignment: 8)
        defer { buf.deallocate() }
        while true {
            let n = read(src, buf.baseAddress, buf.count)
            if n <= 0 { break }
            var written = 0
            while written < n {
                let slice = paced ? min(n - written, limiter.sliceBytes) : n - written
                let delay = paced ? limiter.reserve(bytes: slice) : 0
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                let w = write(dst, buf.baseAddress! + written, slice)
                if w <= 0 { return }
                written += w
            }
        }
    }

    // MARK: - Helpers

    /// Reads the request head (up to the blank line). Any pipelined bytes
    /// after it are dropped; clients should not pipeline against a proxy.
    private func readHead(_ fd: Int32) -> String? {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 16384 {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return nil }
            data.append(buf, count: n)
            if let range = data.range(of: Data("\r\n\r\n".utf8)) {
                return String(data: data[..<range.lowerBound], encoding: .utf8)
            }
        }
        return nil
    }

    /// Opens a TCP connection to `host:port`, going through the app's configured
    /// proxy when there is one. The proxy becomes yt-dlp's only `--proxy`, so it
    /// must carry the same routing (and remote DNS) the user relies on.
    private func openUpstream(_ host: String, _ port: UInt16) -> Int32? {
        guard let p = ActiveProxyStore.shared.proxy, p.isValid,
              let proxyPort = UInt16(exactly: p.port) else {
            return connectHost(host, port)
        }
        switch p.type {
        case .http, .https:
            guard let fd = connectHost(p.host, proxyPort) else { return nil }
            var req = "CONNECT \(host):\(port) HTTP/1.1\r\nHost: \(host):\(port)\r\n"
            if p.requiresAuthentication, !p.username.isEmpty {
                let raw = Data("\(p.username):\(p.password)".utf8).base64EncodedString()
                req += "Proxy-Authorization: Basic \(raw)\r\n"
            }
            req += "\r\n"
            if writeAll(fd, req), let status = readProxyStatus(fd), (200...299).contains(status) {
                return fd
            }
            close(fd)
            return nil
        case .socks5:
            guard let fd = connectHost(p.host, proxyPort),
                  socks5Connect(fd, proxy: p, host: host, port: port) else { return nil }
            return fd
        default:
            return connectHost(host, port)
        }
    }

    /// Reads an HTTP proxy's CONNECT reply head and returns its status code.
    /// Byte-by-byte so no tunnelled TLS bytes are consumed along with it.
    private func readProxyStatus(_ fd: Int32) -> Int? {
        var head: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 1)
        while head.count < 16384 {
            let n = read(fd, &buf, 1)
            if n <= 0 { return nil }
            head.append(buf[0])
            if head.count >= 4, head.suffix(4) == [13, 10, 13, 10] {
                let text = String(decoding: head, as: UTF8.self)
                let parts = text.split(separator: " ", maxSplits: 2)
                guard parts.count >= 2 else { return nil }
                return Int(parts[1])
            }
        }
        return nil
    }

    // MARK: - Upstream proxy protocols

    /// SOCKS5 CONNECT (RFC 1928/1929). The host name is sent as a domain so the
    /// proxy resolves it — local DNS is exactly what a censored network breaks.
    private func socks5Connect(_ fd: Int32, proxy p: ProxyConfig,
                               host: String, port: UInt16) -> Bool {
        let useAuth = p.requiresAuthentication && !p.username.isEmpty
        var greeting: [UInt8] = [0x05, useAuth ? 2 : 1, 0x00]
        if useAuth { greeting.append(0x02) }
        guard writeAll(fd, Data(greeting)),
              let method = readExactly(fd, 2), method[0] == 0x05 else { return false }
        switch method[1] {
        case 0x00:
            break
        case 0x02 where useAuth:
            guard socks5Auth(fd, p) else { return false }
        default:
            return false
        }

        let name = Array(host.utf8)
        guard name.count <= 255 else { return false }
        var req: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(name.count)]
        req += name
        req.append(UInt8(port >> 8))
        req.append(UInt8(port & 0xff))
        guard writeAll(fd, Data(req)),
              let reply = readExactly(fd, 4), reply[0] == 0x05, reply[1] == 0x00 else { return false }

        let addrLength: Int
        switch reply[3] {
        case 0x01: addrLength = 4
        case 0x04: addrLength = 16
        case 0x03:
            guard let len = readExactly(fd, 1) else { return false }
            addrLength = Int(len[0])
        default:
            return false
        }
        return readExactly(fd, addrLength + 2) != nil
    }

    private func socks5Auth(_ fd: Int32, _ p: ProxyConfig) -> Bool {
        let user = Array(p.username.utf8)
        let pass = Array(p.password.utf8)
        guard user.count <= 255, pass.count <= 255 else { return false }
        var msg: [UInt8] = [0x01, UInt8(user.count)]
        msg += user
        msg.append(UInt8(pass.count))
        msg += pass
        guard writeAll(fd, Data(msg)), let reply = readExactly(fd, 2) else { return false }
        return reply[0] == 0x01 && reply[1] == 0x00
    }

    private func readExactly(_ fd: Int32, _ count: Int) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: count)
        var got = 0
        while got < count {
            let n = out.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, count - got) }
            if n <= 0 { return nil }
            got += n
        }
        return out
    }

    private func connectHost(_ host: String, _ port: UInt16) -> Int32? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0 else { return nil }
        defer { freeaddrinfo(res) }
        var ai = res
        while let current = ai {
            let info = current.pointee
            let fd = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if fd >= 0 {
                if connect(fd, info.ai_addr, info.ai_addrlen) == 0 { return fd }
                close(fd)
            }
            ai = info.ai_next
        }
        return nil
    }

    @discardableResult
    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var written = 0
            while written < data.count {
                let w = write(fd, raw.baseAddress! + written, data.count - written)
                if w <= 0 { return false }
                written += w
            }
            return true
        }
    }

    @discardableResult
    private func writeAll(_ fd: Int32, _ text: String) -> Bool {
        writeAll(fd, Data(text.utf8))
    }

    /// The live rate, owned by the proxy and observed by the limiter (so the
    /// limiter never needs a strong reference to the proxy).
    private final class RateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Int64?
        var value: Int64? {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = (newValue ?? 0) > 0 ? newValue : nil; lock.unlock() }
        }
    }

    /// Paces byte slices against a live rate with the same debt accounting as
    /// the engine's RateLimiter, so a transfer averages exactly the set rate.
    private final class PacingLimiter {
        private let lock = NSLock()
        private var nextFree: TimeInterval = 0
        private let rateProvider: () -> Int64

        init(rateProvider: @escaping () -> Int64) { self.rateProvider = rateProvider }

        /// Slice size in bytes. Small slices keep the gaps between writes short
        /// (below yt-dlp's socket timeout); large slices keep overhead low.
        var sliceBytes: Int {
            let r = rateProvider()
            guard r > 0 else { return 256 * 1024 }
            return max(1024, min(16 * 1024, Int(r / 2)))
        }

        func reserve(bytes: Int) -> TimeInterval {
            let rate = rateProvider()
            guard rate > 0 else { return 0 }
            lock.lock(); defer { lock.unlock() }
            let now = Date().timeIntervalSinceReferenceDate
            if nextFree == 0 { nextFree = now }
            if nextFree < now - 0.5 { nextFree = now - 0.5 }
            nextFree += Double(bytes) / Double(rate)
            return max(0, nextFree - now)
        }
    }
}
