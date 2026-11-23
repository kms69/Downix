//
//  BrowserIntegration.swift
//  Download Manager for Mac - Feature #5: Browser Integration
//
//  Created on February 15, 2026
//

import Foundation

/// Supported browsers
enum BrowserType: String, Codable, CaseIterable {
    case safari = "Safari"
    case chrome = "Chrome"
    case brave = "Brave"
    case firefox = "Firefox"
    case edge = "Microsoft Edge"
    
    var icon: String {
        switch self {
        case .safari: return "safari"
        case .chrome: return "globe"
        case .brave: return "shield.fill"
        case .firefox: return "flame.fill"
        case .edge: return "e.circle.fill"
        }
    }
    
    var extensionID: String {
        // Chrome, Brave, Edge all share the same Chromium extension loaded from
        // BrowserExtensions/Chrome (or Brave) — the manifest.json "key" field pins
        // the extension to ID eeikofcgbbeahbphkdbgonopangmdcga on every machine.
        switch self {
        case .safari: return "com.rapiddownload.safari-extension"
        case .chrome: return "eeikofcgbbeahbphkdbgonopangmdcga"
        case .brave:  return "eeikofcgbbeahbphkdbgonopangmdcga"
        case .edge:   return "eeikofcgbbeahbphkdbgonopangmdcga"
        case .firefox: return "rapid_download_manager@firefox"
        }
    }
    
    var nativeMessagingHostName: String {
        return "com.rapiddownload.native"
    }
}

/// Download capture rules
struct CaptureRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var pattern: CapturePattern
    var action: CaptureAction
    var priority: Int
    
    enum CapturePattern: Codable, Equatable {
        case fileExtension([String])
        case urlPattern(String)
        case mimeType([String])
        case minFileSize(Int64) // bytes
        case domain([String])
        case all
        
        func matches(url: String, mimeType: String?, contentLength: Int64?) -> Bool {
            switch self {
            case .fileExtension(let extensions):
                let urlLower = url.lowercased()
                return extensions.contains { ext in
                    urlLower.hasSuffix(".\(ext.lowercased())")
                }
            case .urlPattern(let pattern):
                return url.range(of: pattern, options: .regularExpression) != nil
            case .mimeType(let types):
                guard let mime = mimeType else { return false }
                return types.contains { mime.contains($0) }
            case .minFileSize(let minSize):
                guard let size = contentLength else { return false }
                return size >= minSize
            case .domain(let domains):
                return domains.contains { domain in
                    url.contains(domain)
                }
            case .all:
                return true
            }
        }
    }
    
    enum CaptureAction: String, Codable {
        case capture = "Capture with Download Manager"
        case ignore = "Ignore"
        case ask = "Ask User"
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        pattern: CapturePattern,
        action: CaptureAction = .capture,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.pattern = pattern
        self.action = action
        self.priority = priority
    }
}

/// Native messaging message types
enum NativeMessage: Codable {
    case downloadRequest(DownloadRequest)
    case downloadResponse(DownloadResponse)
    case ping
    case pong
    case error(String)
    
    struct DownloadRequest: Codable {
        let url: String
        let filename: String?
        let referrer: String?
        let cookies: String?
        let userAgent: String?
        let mimeType: String?
        let contentLength: Int64?
    }
    
    struct DownloadResponse: Codable {
        let success: Bool
        let taskId: String?
        let error: String?
    }
}

/// Browser extension status
struct BrowserExtensionStatus: Identifiable {
    let id: UUID
    let browser: BrowserType
    var isInstalled: Bool
    var isEnabled: Bool
    var version: String?
    var lastCommunication: Date?
    var downloadsIntercepted: Int
    
    init(
        id: UUID = UUID(),
        browser: BrowserType,
        isInstalled: Bool = false,
        isEnabled: Bool = false,
        version: String? = nil,
        lastCommunication: Date? = nil,
        downloadsIntercepted: Int = 0
    ) {
        self.id = id
        self.browser = browser
        self.isInstalled = isInstalled
        self.isEnabled = isEnabled
        self.version = version
        self.lastCommunication = lastCommunication
        self.downloadsIntercepted = downloadsIntercepted
    }
}

/// Browser integration settings
struct BrowserIntegrationSettings: Codable {
    var isEnabled: Bool
    var autoCapture: Bool
    var captureRules: [CaptureRule]
    var blacklistedDomains: [String]
    var whitelistedDomains: [String]
    var minFileSizeForCapture: Int64 // bytes, 0 = no minimum
    var showNotifications: Bool
    var closeOriginalDownload: Bool
    
    init(
        isEnabled: Bool = true,
        autoCapture: Bool = true,
        captureRules: [CaptureRule] = [],
        blacklistedDomains: [String] = [],
        whitelistedDomains: [String] = [],
        minFileSizeForCapture: Int64 = 1_048_576, // 1 MB default
        showNotifications: Bool = true,
        closeOriginalDownload: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.autoCapture = autoCapture
        self.captureRules = captureRules
        self.blacklistedDomains = blacklistedDomains
        self.whitelistedDomains = whitelistedDomains
        self.minFileSizeForCapture = minFileSizeForCapture
        self.showNotifications = showNotifications
        self.closeOriginalDownload = closeOriginalDownload
    }
    
    static var defaultRules: [CaptureRule] {
        return [
            CaptureRule(
                name: "Large Files (>10MB)",
                pattern: .minFileSize(10_485_760),
                action: .capture,
                priority: 100
            ),
            CaptureRule(
                name: "Videos",
                pattern: .fileExtension(["mp4", "mkv", "avi", "mov", "webm", "flv"]),
                action: .capture,
                priority: 90
            ),
            CaptureRule(
                name: "Archives",
                pattern: .fileExtension(["zip", "rar", "7z", "tar", "gz", "dmg", "iso"]),
                action: .capture,
                priority: 80
            ),
            CaptureRule(
                name: "Software",
                pattern: .fileExtension(["exe", "dmg", "pkg", "deb", "rpm"]),
                action: .capture,
                priority: 70
            ),
            CaptureRule(
                name: "Documents",
                pattern: .fileExtension(["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx"]),
                action: .ask,
                priority: 50
            )
        ]
    }
}

// MARK: - Preset Configurations

extension BrowserIntegrationSettings {
    static var aggressiveCapture: BrowserIntegrationSettings {
        var settings = BrowserIntegrationSettings()
        settings.autoCapture = true
        settings.minFileSizeForCapture = 0 // Capture everything
        settings.captureRules = defaultRules
        settings.closeOriginalDownload = true
        return settings
    }
    
    static var conservativeCapture: BrowserIntegrationSettings {
        var settings = BrowserIntegrationSettings()
        settings.autoCapture = true
        settings.minFileSizeForCapture = 10_485_760 // 10 MB
        settings.captureRules = [
            CaptureRule(
                name: "Large Files Only",
                pattern: .minFileSize(10_485_760),
                action: .capture,
                priority: 100
            )
        ]
        settings.closeOriginalDownload = false
        return settings
    }
    
    static var manualCapture: BrowserIntegrationSettings {
        var settings = BrowserIntegrationSettings()
        settings.autoCapture = false
        settings.captureRules = []
        return settings
    }
}
