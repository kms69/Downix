//
//  BrowserIntegrationManager.swift
//  Download Manager for Mac - Feature #5: Browser Integration Manager
//
//  Created on February 15, 2026
//

import Foundation
import Combine

/// Manages browser integration and extension communication
@MainActor
class BrowserIntegrationManager: ObservableObject {
    
    static let shared = BrowserIntegrationManager()
    
    @Published var settings: BrowserIntegrationSettings
    @Published var extensionStatuses: [BrowserExtensionStatus] = []
    @Published var isNativeHostInstalled: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private let downloadManager = DownloadManager.shared
    
    // Statistics
    @Published var totalIntercepted: Int = 0
    @Published var totalCaptured: Int = 0
    @Published var totalIgnored: Int = 0
    
    private static let settingsKey = "BrowserIntegrationSettings"

    private init() {
        // Load persisted settings if available
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(BrowserIntegrationSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = BrowserIntegrationSettings()
            self.settings.captureRules = BrowserIntegrationSettings.defaultRules
        }
        
        // Initialize extension statuses
        for browser in BrowserType.allCases {
            extensionStatuses.append(BrowserExtensionStatus(browser: browser))
        }
        
        checkNativeHostInstallation()
    }
    
    // MARK: - Settings Management
    
    func updateSettings(_ settings: BrowserIntegrationSettings) {
        DispatchQueue.main.async {
            self.settings = settings
            // Persist to disk
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
        }
    }
    
    func addCaptureRule(_ rule: CaptureRule) {
        DispatchQueue.main.async {
            self.settings.captureRules.append(rule)
            self.settings.captureRules.sort { $0.priority > $1.priority }
        }
    }
    
    func removeCaptureRule(_ rule: CaptureRule) {
        DispatchQueue.main.async {
            self.settings.captureRules.removeAll { $0.id == rule.id }
        }
    }
    
    func updateCaptureRule(_ rule: CaptureRule) {
        DispatchQueue.main.async {
            if let index = self.settings.captureRules.firstIndex(where: { $0.id == rule.id }) {
                self.settings.captureRules[index] = rule
                self.settings.captureRules.sort { $0.priority > $1.priority }
            }
        }
    }
    
    // MARK: - Download Capture
    
    func handleDownloadRequest(_ request: NativeMessage.DownloadRequest) -> NativeMessage.DownloadResponse {
        totalIntercepted += 1
        
        guard settings.isEnabled else {
            print("📡 Browser integration disabled, ignoring request")
            totalIgnored += 1
            return NativeMessage.DownloadResponse(
                success: false,
                taskId: nil,
                error: "Browser integration is disabled"
            )
        }
        
        // Check if should capture
        let shouldCapture = evaluateCaptureRules(request)
        
        guard shouldCapture else {
            print("📡 Download doesn't match capture rules, ignoring")
            totalIgnored += 1
            return NativeMessage.DownloadResponse(
                success: false,
                taskId: nil,
                error: "Download doesn't match capture rules"
            )
        }
        
        // Create download task
        return captureDownload(request)
    }
    
    private func evaluateCaptureRules(_ request: NativeMessage.DownloadRequest) -> Bool {
        guard settings.autoCapture else { return false }
        
        // Check blacklist
        if !settings.blacklistedDomains.isEmpty {
            for domain in settings.blacklistedDomains {
                if request.url.contains(domain) {
                    print("📡 URL in blacklist: \(domain)")
                    return false
                }
            }
        }
        
        // Check whitelist (if set, only whitelist allowed)
        if !settings.whitelistedDomains.isEmpty {
            var inWhitelist = false
            for domain in settings.whitelistedDomains {
                if request.url.contains(domain) {
                    inWhitelist = true
                    break
                }
            }
            if !inWhitelist {
                print("📡 URL not in whitelist")
                return false
            }
        }
        
        // Check minimum file size
        if let contentLength = request.contentLength,
           contentLength < settings.minFileSizeForCapture {
            print("📡 File too small: \(contentLength) < \(settings.minFileSizeForCapture)")
            return false
        }
        
        // Evaluate capture rules
        let enabledRules = settings.captureRules.filter { $0.isEnabled }
        
        for rule in enabledRules {
            if rule.pattern.matches(
                url: request.url,
                mimeType: request.mimeType,
                contentLength: request.contentLength
            ) {
                print("📡 Matched rule: \(rule.name) - \(rule.action.rawValue)")
                
                switch rule.action {
                case .capture:
                    return true
                case .ignore:
                    return false
                case .ask:
                    // For now, default to capture
                    // TODO: Show user notification with choice
                    return true
                }
            }
        }
        
        // No rules matched, check if we have a minimum file size requirement
        if let contentLength = request.contentLength,
           contentLength >= settings.minFileSizeForCapture {
            return true
        }
        
        return false
    }
    
    private func captureDownload(_ request: NativeMessage.DownloadRequest) -> NativeMessage.DownloadResponse {
        do {
            guard let url = URL(string: request.url) else {
                throw NSError(
                    domain: "BrowserIntegration",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]
                )
            }
            
            let filename = request.filename ?? url.lastPathComponent
            
            // Add download to manager
            let task: DownloadTask
            if Thread.isMainThread {
                task = downloadManager.addDownload(
                    url: url,
                    destinationPath: nil,
                    filename: filename,
                    numberOfSegments: nil
                )
            } else {
                var capturedTask: DownloadTask?
                let sema = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    capturedTask = self.downloadManager.addDownload(url: url, destinationPath: nil, filename: filename, numberOfSegments: nil)
                    sema.signal()
                }
                sema.wait()
                task = capturedTask!
            }
            
            totalCaptured += 1
            
            print("✅ Captured download: \(filename)")
            
            return NativeMessage.DownloadResponse(
                success: true,
                taskId: task.id.uuidString,
                error: nil
            )
            
        } catch {
            print("❌ Failed to capture download: \(error)")
            return NativeMessage.DownloadResponse(
                success: false,
                taskId: nil,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Extension Status
    
    func updateExtensionStatus(_ browser: BrowserType, isInstalled: Bool, isEnabled: Bool) {
        DispatchQueue.main.async {
            if let index = self.extensionStatuses.firstIndex(where: { $0.browser == browser }) {
                self.extensionStatuses[index].isInstalled = isInstalled
                self.extensionStatuses[index].isEnabled = isEnabled
                self.extensionStatuses[index].lastCommunication = Date()
            }
        }
    }
    
    func recordExtensionCommunication(_ browser: BrowserType) {
        DispatchQueue.main.async {
            if let index = self.extensionStatuses.firstIndex(where: { $0.browser == browser }) {
                self.extensionStatuses[index].lastCommunication = Date()
                self.extensionStatuses[index].downloadsIntercepted += 1
            }
        }
    }
    
    func getExtensionStatus(_ browser: BrowserType) -> BrowserExtensionStatus? {
        return extensionStatuses.first { $0.browser == browser }
    }
    
    // MARK: - Native Host Installation

    func checkNativeHostInstallation() {
        let fm = FileManager.default
        isNativeHostInstalled = fm.fileExists(atPath: getNativeHostPath().path)
            && fm.fileExists(atPath: getNativeHostScriptPath().path)
    }

    func installNativeHost() throws {
        // 1. Create the host directory
        let hostPath = getNativeHostPath()          // /bin/sh launcher: what browsers execute
        let scriptPath = getNativeHostScriptPath()  // python host logic
        try FileManager.default.createDirectory(
            at: hostPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 2. Write the Python host and the launcher that finds a *working* python3.
        //    (Browsers start hosts with a minimal PATH, and /usr/bin/python3 on a Mac
        //    without Xcode Command Line Tools is only an installer stub.)
        try nativeHostScript().write(to: scriptPath, atomically: true, encoding: .utf8)
        try nativeHostLauncherScript().write(to: hostPath, atomically: true, encoding: .utf8)

        // 3. Make both executable
        for url in [scriptPath, hostPath] {
            var attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            attrs[.posixPermissions] = NSNumber(value: 0o755)
            try FileManager.default.setAttributes(attrs, ofItemAtPath: url.path)
        }

        // 4. Install manifests for every browser (they point at the launcher)
        for browser in BrowserType.allCases {
            try installManifest(for: browser, hostPath: hostPath)
        }

        isNativeHostInstalled = true
    }

    func uninstallNativeHost() throws {
        for url in [getNativeHostPath(), getNativeHostScriptPath()] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        // Remove manifests
        for browser in BrowserType.allCases {
            if let dir = nativeHostManifestDirectory(for: browser) {
                let file = dir.appendingPathComponent("com.rapiddownload.native.json")
                try? FileManager.default.removeItem(at: file)
            }
        }
        isNativeHostInstalled = false
    }

    // MARK: - Native host scripts

    /// POSIX sh launcher. Chrome/Edge/Brave/Firefox execute this file (the manifest
    /// `path`). It locates a real python3 and runs native-host.py; if none exists it
    /// still answers the browser with a clear native-messaging error instead of
    /// failing silently ("Native host has exited").
    private func nativeHostLauncherScript() -> String {
        return #"""
#!/bin/sh
# Rapid Download Manager - native messaging launcher
DIR=$(cd "$(dirname "$0")" && pwd)
HOST="$DIR/native-host.py"

# RDM_PYTHON is only used by tests.
if [ -n "$RDM_PYTHON" ] && [ -x "$RDM_PYTHON" ]; then
    exec "$RDM_PYTHON" "$HOST"
fi

for PY in \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
    /Library/Developer/CommandLineTools/usr/bin/python3 \
    /Applications/Xcode.app/Contents/Developer/usr/bin/python3
do
    if [ -x "$PY" ]; then
        exec "$PY" "$HOST"
    fi
done

# /usr/bin/python3 is only a real interpreter once the Command Line Tools exist.
if /usr/bin/xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then
    exec /usr/bin/python3 "$HOST"
fi

# No python3: reply with a native-messaging error frame (4-byte little-endian length + JSON).
MSG='{"success":false,"error":"python3 not found. Run xcode-select --install (or install Homebrew python3), then retry."}'
LEN=${#MSG}
printf "$(printf '\\%03o' "$LEN")\\000\\000\\000%s" "$MSG"
exit 1
"""#
    }

    /// Native host logic. Receives {type:'downloadRequest', data:{url, filename, referer,
    /// cookie, userAgent, kind}} from the extension and forwards it to the app as
    /// downloadmanager://add?url=&filename=&referer=&cookie=&ua=&kind=<file|video>
    private func nativeHostScript() -> String {
        return #"""
#!/usr/bin/env python3
# Rapid Download Manager - Native Messaging Host (v3)
# - downloadRequest: forward a browser download to the app via downloadmanager://add
# - formats: analyze a video page with yt-dlp and return the available qualities
#   (used by the IDM-style quality menu on YouTube and other video sites).

import json
import os
import shutil
import struct
import subprocess
import sys
import time
import urllib.parse
import uuid

OPEN_BIN = os.environ.get('RDM_OPEN_BIN', '/usr/bin/open')
APP_BUNDLE_ID = 'com.downloadmanager.app'
MAX_COOKIE = 6000
HOST_VERSION = '3.3'
HOME = os.path.expanduser('~')
COOKIE_DIR = os.path.join(HOME, 'Library/Application Support/DownloadManager/Cookies')
BATCH_DIR = os.path.join(HOME, 'Library/Application Support/DownloadManager/Batches')


def read_message():
    raw_len = sys.stdin.buffer.read(4)
    if len(raw_len) < 4:
        sys.exit(0)
    length = struct.unpack('<I', raw_len)[0]
    if length > 8 * 1024 * 1024:
        raise ValueError('message too large')
    return json.loads(sys.stdin.buffer.read(length).decode('utf-8'))


def send_message(data):
    encoded = json.dumps(data).encode('utf-8')
    sys.stdout.buffer.write(struct.pack('<I', len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def clean(value, limit=None):
    if value is None:
        return ''
    value = str(value)
    return value[:limit] if limit else value


def cookie_file(cookies, prefix='rdm'):
    """Write Chrome cookie objects to a private Netscape cookie file for yt-dlp.

    The extension reads cookies with the chrome.cookies API (no Keychain access),
    so unlike --cookies-from-browser this never asks for the Mac login password.
    The file is always created (possibly with only a header) so callers can rely
    on --cookies and avoid falling back to the Keychain.
    """
    lines = ['# Netscape HTTP Cookie File', '']
    total = 0
    for item in cookies or []:
        if not isinstance(item, dict):
            continue
        name = clean(item.get('name'))
        value = clean(item.get('value'))
        domain = clean(item.get('domain')).strip()
        if not name or not domain or '\t' in name or '\t' in value or '\n' in value or '\r' in value:
            continue
        host_only = bool(item.get('hostOnly'))
        if host_only:
            domain = domain.lstrip('.')
        elif not domain.startswith('.'):
            domain = '.' + domain
        http_only = '#HttpOnly_' if item.get('httpOnly') else ''
        secure = 'TRUE' if item.get('secure') else 'FALSE'
        expiry = item.get('expirationDate')
        try:
            expiry = str(int(float(expiry))) if expiry else '0'
        except Exception:
            expiry = '0'
        path = clean(item.get('path')) or '/'
        line = '%s%s\t%s\t%s\t%s\t%s\t%s\t%s' % (
            http_only, domain, 'FALSE' if host_only else 'TRUE',
            path, secure, expiry, name, value)
        total += len(line) + 1
        if total > 512 * 1024:
            break
        lines.append(line)
    try:
        os.makedirs(COOKIE_DIR, mode=0o700, exist_ok=True)
        path = os.path.join(COOKIE_DIR, '%s-%s.txt' % (prefix, uuid.uuid4().hex))
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as handle:
            handle.write('\n'.join(lines) + '\n')
        return path
    except Exception:
        return None


def cleanup_cookie_files(max_age=86400):
    try:
        now = time.time()
        for name in os.listdir(COOKIE_DIR):
            path = os.path.join(COOKIE_DIR, name)
            try:
                if os.path.isfile(path) and now - os.path.getmtime(path) > max_age:
                    os.unlink(path)
            except Exception:
                pass
    except Exception:
        pass


def build_scheme_url(data):
    """Return the downloadmanager://add URL for a request dict, or None if it has no http(s) URL."""
    url = clean(data.get('url'))
    if not url.lower().startswith(('http://', 'https://')):
        return None
    params = [('url', url)]
    filename = clean(data.get('filename') or data.get('suggestedFilename'))
    referer = clean(data.get('referer') or data.get('referrer'))
    cookie = clean(data.get('cookie'), MAX_COOKIE)
    ua = clean(data.get('ua') or data.get('userAgent'))
    kind = 'video' if data.get('kind') == 'video' else 'file'
    quality = clean(data.get('quality'))
    audio_only = data.get('audioOnly') is True or str(data.get('audioOnly')).lower() in ('1', 'true', 'yes')
    if filename:
        params.append(('filename', filename))
    if referer:
        params.append(('referer', referer))
    if kind != 'video' and cookie:
        params.append(('cookie', cookie))
    if ua:
        params.append(('ua', ua))
    params.append(('kind', kind))
    if kind == 'video':
        path = cookie_file(data.get('cookies') or [], 'dl')
        if path:
            params.append(('cookiefile', path))
        if quality in ('', '0'):
            if quality == '0':
                params.append(('quality', 'best'))
        else:
            params.append(('quality', quality))
        if audio_only:
            params.append(('audio', '1'))
    query = '&'.join('%s=%s' % (k, urllib.parse.quote(v, safe='')) for k, v in params)
    return 'downloadmanager://add?' + query


def find_ytdlp():
    candidates = [
        os.path.join(HOME, 'Library/Application Support/DownloadManager/bin/yt-dlp'),
        '/opt/homebrew/bin/yt-dlp',
        '/usr/local/bin/yt-dlp',
        '/usr/bin/yt-dlp',
    ]
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return shutil.which('yt-dlp')


def cookie_sources():
    """Cookie arg sets to try, in order. YouTube sometimes rejects a browser's
    cookies ("sign in to confirm", "page needs to be reloaded"), so callers
    should fall back to the next browser."""
    pref = os.environ.get('RDM_COOKIES_FROM_BROWSER', 'auto')
    if pref == 'none':
        return [[]]
    if pref != 'auto':
        return [['--cookies-from-browser', pref]]
    candidates = [
        ('chrome', os.path.join(HOME, 'Library/Application Support/Google/Chrome')),
        ('brave', os.path.join(HOME, 'Library/Application Support/BraveSoftware/Brave-Browser')),
        ('edge', os.path.join(HOME, 'Library/Application Support/Microsoft Edge')),
        ('firefox', os.path.join(HOME, 'Library/Application Support/Firefox')),
        ('safari', os.path.join(HOME, 'Library/Cookies')),
    ]
    sets = [['--cookies-from-browser', name] for name, path in candidates if os.path.exists(path)]
    return sets or [[]]


RETRYABLE = ('sign in to confirm', 'needs to be reloaded', 'player response',
             'playability', 'unable to extract', 'http error 403', 'please report this issue',
             'timed out', 'temporarily unavailable')


def is_retryable(error):
    low = (error or '').lower()
    return any(token in low for token in RETRYABLE)


def friendly_format_error(error):
    """Never expose yt-dlp's raw stderr in the floating quality menu."""
    low = (error or '').lower()
    if 'yt-dlp not found' in low:
        return 'yt-dlp is not installed. Install it with: brew install yt-dlp'
    if ('needs to be reloaded' in low or 'playability' in low
            or 'player response' in low or 'unable to extract' in low):
        return ('The site asked for a fresh session. Reload the video page, '
                'then press Retry.')
    if 'sign in' in low or 'bot' in low or 'login' in low:
        return ('This video needs a signed-in browser session. Sign in to the site, '
                'reload the page, then press Retry.')
    if '403' in low or 'forbidden' in low:
        return ('The site denied access to this video. Open it in the browser, '
                'then press Retry.')
    if 'timed out' in low or 'temporarily unavailable' in low:
        return 'The site took too long to respond. Press Retry in a moment.'
    return 'Could not read this video. Reload the page, then press Retry.'


def trim_error(proc):
    err = proc.stderr.decode('utf-8', 'replace').strip()
    if not err:
        return 'yt-dlp exited with status %d' % proc.returncode
    return err[-800:]


def app_proxy_args():
    """yt-dlp args for the app's active proxy.

    On filtered networks a direct connection to video sites just times out, and
    the app itself reaches them through this proxy, so the quality menu has to
    use the same route.
    """
    try:
        import plistlib
        raw = subprocess.run(['/usr/bin/defaults', 'export', APP_BUNDLE_ID, '-'],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             timeout=5).stdout
        blob = plistlib.loads(raw).get('com.downloadmanager.networkConfiguration')
        cfg = json.loads(blob.decode('utf-8')) if isinstance(blob, (bytes, bytearray)) else blob
        if not isinstance(cfg, dict):
            return []
        active = cfg.get('activeProxyID')
        proxy = next((p for p in cfg.get('proxyConfigs') or []
                      if p.get('id') == active and p.get('isEnabled', True)), None)
        if not proxy:
            return []
        scheme = {'socks5': 'socks5h', 'http': 'http', 'https': 'http'}.get(
            (proxy.get('type') or '').lower())
        host = clean(proxy.get('host'))
        port = proxy.get('port')
        if not scheme or not host or not port:
            return []
        if proxy.get('requiresAuthentication') and proxy.get('username'):
            user = urllib.parse.quote(clean(proxy.get('username')), safe='')
            password = urllib.parse.quote(clean(proxy.get('password')), safe='')
            host = '%s:%s@%s' % (user, password, host)
        return ['--proxy', '%s://%s:%d' % (scheme, host, int(port))]
    except Exception:
        return []


def analyze_once(ytdlp, url, cookies, extra=None):
    """Run yt-dlp -J once. Returns (info_dict or None, error_text or None)."""
    cmd = [ytdlp, '-J', '--no-playlist', '--no-warnings'] + app_proxy_args() + (extra or []) + cookies + [url]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45)
    except subprocess.TimeoutExpired:
        return None, 'Timed out while analyzing the video'
    except Exception as exc:
        return None, 'Could not run yt-dlp: %s' % exc
    if proc.returncode != 0 or not proc.stdout:
        return None, trim_error(proc)
    try:
        return json.loads(proc.stdout.decode('utf-8', 'replace')), None
    except Exception as exc:
        return None, 'Could not parse yt-dlp output: %s' % exc


def format_attempts(cookie_args, url):
    """Retry strategies for the yt-dlp 'page needs to be reloaded' error.

    The first pass uses the cookies supplied by the extension. The follow-up
    passes disable yt-dlp's player cache and ask for different YouTube player
    clients (the known workaround for stale player responses). The extension
    makes a second request with freshly read cookies if all of these fail.
    """
    attempts = [list(cookie_args)]
    if 'youtube.com' in url or 'youtu.be' in url:
        attempts.append(list(cookie_args) + [
            '--no-cache-dir',
            '--extractor-args', 'youtube:player_client=default,web_embedded',
        ])
        attempts.append(list(cookie_args) + [
            '--no-cache-dir',
            '--extractor-args', 'youtube:player_client=web_safari,web_embedded',
        ])
    else:
        attempts.append(list(cookie_args) + ['--no-cache-dir'])
    return attempts


def handle_formats(data):
    """Analyze a page with yt-dlp and return a small quality menu."""
    url = clean(data.get('url'))
    if not url.lower().startswith(('http://', 'https://')):
        send_message({'success': False, 'error': 'Missing or non-http(s) URL'})
        return
    ytdlp = find_ytdlp()
    if not ytdlp:
        send_message({'success': False, 'error': 'yt-dlp not found. Install it with: brew install yt-dlp'})
        return

    # The extension passes the site's cookies (read via chrome.cookies, no Keychain).
    # Always hand yt-dlp a cookie file, even an empty one, so it never falls back to
    # --cookies-from-browser and prompts for the macOS login password.
    path = cookie_file(data.get('cookies') or [], 'fmt')
    cookie_args = ['--cookies', path] if path else []
    ua = clean(data.get('userAgent'))
    if ua:
        cookie_args += ['--user-agent', ua]
    # Sniffed manifests live on CDNs that answer 403 unless the page is the referer.
    referer = clean(data.get('referer'))
    if referer:
        cookie_args += ['--referer', referer]
    info, last_error = None, None
    attempts = format_attempts(cookie_args, url)
    try:
        for index, args in enumerate(attempts):
            info, err = analyze_once(ytdlp, url, args)
            if info is not None:
                break
            last_error = err or 'yt-dlp could not analyze this page'
            # A private/deleted video will not improve by retrying.
            if not is_retryable(last_error):
                break
            if index + 1 < len(attempts):
                time.sleep(0.5)
    finally:
        if path:
            try:
                os.unlink(path)
            except Exception:
                pass

    if info is None:
        send_message({
            'success': False,
            'error': friendly_format_error(last_error),
            'retryable': is_retryable(last_error),
            'autoRetried': len(attempts) > 1,
        })
        return

    # Prefer MP4 / highest bitrate for each height.
    by_height = {}
    for f in info.get('formats') or []:
        if not isinstance(f, dict):
            continue
        if f.get('vcodec') in (None, 'none'):
            continue
        height = f.get('height')
        if not isinstance(height, int) or height <= 0:
            continue
        ext = (f.get('ext') or '').lower()
        tbr = f.get('tbr') or 0
        prev = by_height.get(height)
        better = prev is None or (ext == 'mp4' and prev[0] != 'mp4') or (ext == prev[0] and tbr > prev[1])
        if better:
            by_height[height] = (ext, tbr)

    menu = [{'quality': 0, 'label': 'Best available', 'audioOnly': False}]
    for height in sorted(by_height.keys(), reverse=True)[:8]:
        ext = by_height[height][0]
        label = '%dp' % height
        if ext:
            label += ' • ' + ext.upper()
        menu.append({'quality': height, 'label': label, 'audioOnly': False})
    menu.append({'quality': 0, 'label': 'Audio only (M4A)', 'audioOnly': True})

    send_message({
        'success': True,
        'url': url,
        'title': clean(info.get('title')),
        'duration': info.get('duration'),
        'uploader': clean(info.get('uploader') or info.get('channel')),
        'best': max(by_height.keys()) if by_height else 0,
        'qualityCount': len(by_height),
        'formats': menu,
    })


def run_open(args):
    """Run /usr/bin/open. Returns (ok, error_text)."""
    try:
        proc = subprocess.run([OPEN_BIN] + args, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=15)
    except Exception as exc:
        return False, 'Could not run open: %s' % exc
    if proc.returncode != 0:
        err = proc.stderr.decode('utf-8', 'replace').strip()
        return False, err or ('open exited with status %d' % proc.returncode)
    return True, None


def handle_download(data):
    scheme_url = build_scheme_url(data)
    if scheme_url is None:
        send_message({'success': False, 'error': 'Missing or non-http(s) URL'})
        return
    ok, err = run_open([scheme_url])
    if ok:
        send_message({'success': True, 'message': 'Sent to Download Manager'})
    else:
        send_message({'success': False, 'error': 'Download Manager could not be opened: ' + err})


def cleanup_batch_files(max_age=3600):
    try:
        now = time.time()
        for name in os.listdir(BATCH_DIR):
            path = os.path.join(BATCH_DIR, name)
            try:
                if os.path.isfile(path) and now - os.path.getmtime(path) > max_age:
                    os.unlink(path)
            except Exception:
                pass
    except Exception:
        pass


def handle_batch(data):
    """Several highlighted links: hand the list to the app as a private JSON file."""
    links, seen = [], set()
    for item in (data.get('links') or [])[:3000]:
        if isinstance(item, str):
            item = {'url': item}
        if not isinstance(item, dict):
            continue
        url = clean(item.get('url'), 4000)
        if not url.lower().startswith(('http://', 'https://')) or url in seen:
            continue
        seen.add(url)
        links.append({'url': url, 'text': clean(item.get('text'), 200)})
    if not links:
        send_message({'success': False, 'error': 'No http(s) links in the selection'})
        return
    payload = {
        'pageUrl': clean(data.get('pageUrl'), 4000),
        'pageTitle': clean(data.get('pageTitle'), 300),
        'referer': clean(data.get('referer'), 4000),
        'cookie': clean(data.get('cookie'), MAX_COOKIE),
        'cookieHost': clean(data.get('cookieHost'), 300),
        'userAgent': clean(data.get('userAgent'), 500),
        'links': links,
    }
    try:
        os.makedirs(BATCH_DIR, mode=0o700, exist_ok=True)
        path = os.path.join(BATCH_DIR, 'batch-%s.json' % uuid.uuid4().hex)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as handle:
            json.dump(payload, handle)
    except Exception as exc:
        send_message({'success': False, 'error': 'Could not write the link list: %s' % exc})
        return
    ok, err = run_open(['downloadmanager://addbatch?file=' + urllib.parse.quote(path, safe='')])
    if ok:
        send_message({'success': True, 'message': 'Sent %d links' % len(links)})
    else:
        send_message({'success': False, 'error': 'Download Manager could not be opened: ' + err})


def main():
    cleanup_cookie_files()
    cleanup_batch_files()
    while True:
        try:
            msg = read_message()
            msg_type = msg.get('type', '')
            action = msg.get('action', '')

            if msg_type == 'downloadRequest':
                handle_download(msg.get('data') or {})
            elif msg_type == 'batchRequest':
                handle_batch(msg.get('data') or {})
            elif action == 'download':
                handle_download(msg)
            elif msg_type == 'formats' or action == 'formats' or action == 'getFormats':
                handle_formats(msg.get('data') or msg)
            elif action == 'ping' or msg_type == 'ping':
                send_message({'success': True, 'version': HOST_VERSION, 'app': 'Download Manager',
                              'python': sys.version.split()[0]})
            elif action == 'openApp' or msg_type == 'openApp':
                ok, err = run_open(['-b', APP_BUNDLE_ID])
                send_message({'success': ok, 'message': 'App opened'} if ok else {'success': False, 'error': err})
            else:
                send_message({'success': False, 'error': 'Unknown message: type=%s action=%s' % (msg_type, action)})
        except SystemExit:
            raise
        except Exception as exc:
            send_message({'success': False, 'error': str(exc)})


if __name__ == '__main__':
    main()
"""#
    }

    // MARK: - Manifest installation

    /// The executable browsers launch (sh launcher).
    private func getNativeHostPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DownloadManager/native-host.sh")
    }

    /// The python implementation the launcher runs.
    private func getNativeHostScriptPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DownloadManager/native-host.py")
    }

    private func getNativeHostManifestPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DownloadManager/manifests")
    }

    /// Returns the browser-specific directory where the JSON manifest must be placed.
    private func nativeHostManifestDirectory(for browser: BrowserType) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch browser {
        case .chrome:
            return home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        case .brave:
            return home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts")
        case .edge:
            return home.appendingPathComponent("Library/Application Support/Microsoft Edge/NativeMessagingHosts")
        case .firefox:
            return home.appendingPathComponent("Library/Application Support/Mozilla/NativeMessagingHosts")
        case .safari:
            return nil  // Safari uses App Extension mechanism, not native messaging
        }
    }

    private func installManifest(for browser: BrowserType, hostPath: URL) throws {
        guard let dir = nativeHostManifestDirectory(for: browser) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var manifest: [String: Any] = [
            "name": "com.rapiddownload.native",
            "description": "Rapid Download Manager Browser Integration",
            "path": hostPath.path,
            "type": "stdio"
        ]

        switch browser {
        case .chrome, .brave, .edge:
            // The extension must be loaded unpacked and you use its actual ID.
            // We use a wildcard-like approach by listing a placeholder; the user
            // should replace this with their actual extension ID after loading it.
            manifest["allowed_origins"] = ["chrome-extension://\(browser.extensionID)/"]
        case .firefox:
            manifest["allowed_extensions"] = [browser.extensionID]
        case .safari:
            return  // Handled differently
        }

        let data = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        let file = dir.appendingPathComponent("com.rapiddownload.native.json")
        try data.write(to: file, options: .atomic)
    }

    private func createNativeHostManifest(for browser: BrowserType) throws {
        try installManifest(for: browser, hostPath: getNativeHostPath())
    }
    
    // MARK: - Statistics
    
    func getStatistics() -> IntegrationStatistics {
        return IntegrationStatistics(
            totalIntercepted: totalIntercepted,
            totalCaptured: totalCaptured,
            totalIgnored: totalIgnored,
            captureRate: totalIntercepted > 0 ? Double(totalCaptured) / Double(totalIntercepted) : 0,
            installedExtensions: extensionStatuses.filter { $0.isInstalled }.count,
            enabledExtensions: extensionStatuses.filter { $0.isEnabled }.count
        )
    }
    
    struct IntegrationStatistics {
        let totalIntercepted: Int
        let totalCaptured: Int
        let totalIgnored: Int
        let captureRate: Double
        let installedExtensions: Int
        let enabledExtensions: Int
    }
}
