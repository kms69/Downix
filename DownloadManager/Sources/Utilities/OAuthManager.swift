//
//  OAuthManager.swift
//  Download Manager for Mac - OAuth 2.0 Authentication
//
//  Created on February 16, 2026
//

import Foundation
import Combine
import AuthenticationServices
import CryptoKit

/// Manages OAuth 2.0 authentication flows for cloud providers
class OAuthManager: NSObject {
    
    static let shared = OAuthManager()
    
    private var currentSession: ASWebAuthenticationSession?
    private var authContinuation: CheckedContinuation<OAuthResult, Error>?
    
    // OAuth Configuration for each provider
    // Credentials are loaded from environment variables or Secrets.plist (not tracked in git)
    private lazy var providerConfigs: [CloudProvider: OAuthConfig] = {
        let dropboxSecrets = SecretsConfig.dropboxSecrets()
        let googleSecrets = SecretsConfig.googleDriveSecrets()
        let oneDriveSecrets = SecretsConfig.oneDriveSecrets()
        let boxSecrets = SecretsConfig.boxSecrets()
        
        return [
            .dropbox: OAuthConfig(
                clientId: dropboxSecrets.clientId,
                clientSecret: dropboxSecrets.clientSecret,
                authURL: "https://www.dropbox.com/oauth2/authorize",
                tokenURL: "https://api.dropboxapi.com/oauth2/token",
                redirectURI: "com.rapiddownload:/oauth/dropbox",
                scope: "files.content.write files.content.read account_info.read"
            ),
            .googleDrive: OAuthConfig(
                clientId: googleSecrets.clientId,
                clientSecret: googleSecrets.clientSecret,
                authURL: "https://accounts.google.com/o/oauth2/v2/auth",
                tokenURL: "https://oauth2.googleapis.com/token",
                redirectURI: "com.rapiddownload:/oauth/googledrive",
                scope: "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/userinfo.email"
            ),
            .oneDrive: OAuthConfig(
                clientId: oneDriveSecrets.clientId,
                clientSecret: oneDriveSecrets.clientSecret,
                authURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                redirectURI: "com.rapiddownload:/oauth/onedrive",
                scope: "Files.ReadWrite offline_access User.Read"
            ),
            .box: OAuthConfig(
                clientId: boxSecrets.clientId,
                clientSecret: boxSecrets.clientSecret,
                authURL: "https://account.box.com/api/oauth2/authorize",
                tokenURL: "https://api.box.com/oauth2/token",
                redirectURI: "com.rapiddownload:/oauth/box",
                scope: "root_readwrite"
            )
        ]
    }()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start OAuth authentication flow
    func authenticate(provider: CloudProvider, accountId: String) async throws -> CloudCredentials {
        guard let config = providerConfigs[provider] else {
            throw OAuthError.unsupportedProvider
        }
        
        // Step 1: Get authorization code
        let authCode = try await getAuthorizationCode(config: config, provider: provider)
        
        // Step 2: Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code: authCode, config: config)
        
        // Step 3: Create credentials
        let credentials = CloudCredentials(
            accountId: accountId,
            provider: provider,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expiresIn)),
            tokenType: tokens.tokenType,
            scope: tokens.scope
        )
        
        // Step 4: Save to Keychain
        try KeychainManager.shared.saveCredentials(credentials)
        
        return credentials
    }
    
    /// Refresh access token
    func refreshToken(for accountId: String) async throws -> CloudCredentials {
        guard let credentials = try KeychainManager.shared.fetchCredentials(forAccount: accountId) else {
            throw OAuthError.credentialsNotFound
        }
        
        guard let refreshToken = credentials.refreshToken else {
            throw OAuthError.noRefreshToken
        }
        
        guard let config = providerConfigs[credentials.provider] else {
            throw OAuthError.unsupportedProvider
        }
        
        // Make refresh request
        let tokens = try await refreshAccessToken(refreshToken: refreshToken, config: config)
        
        // Update credentials
        var updatedCredentials = credentials
        updatedCredentials.accessToken = tokens.accessToken
        updatedCredentials.expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        if let newRefreshToken = tokens.refreshToken {
            updatedCredentials.refreshToken = newRefreshToken
        }
        
        // Save updated credentials
        try KeychainManager.shared.saveCredentials(updatedCredentials)
        
        return updatedCredentials
    }
    
    /// Check if credentials are expired and refresh if needed
    func ensureValidToken(for accountId: String) async throws -> CloudCredentials {
        guard let credentials = try KeychainManager.shared.fetchCredentials(forAccount: accountId) else {
            throw OAuthError.credentialsNotFound
        }
        
        // Check if token is expired or will expire in the next 5 minutes
        if let expiresAt = credentials.expiresAt,
           expiresAt.timeIntervalSinceNow < 300 {
            return try await refreshToken(for: accountId)
        }
        
        return credentials
    }
    
    /// Revoke credentials and remove from Keychain
    func revokeCredentials(for accountId: String) async throws {
        guard let credentials = try KeychainManager.shared.fetchCredentials(forAccount: accountId) else {
            return
        }
        
        // Try to revoke on server (best effort)
        if let config = providerConfigs[credentials.provider],
           let revokeURL = config.revokeURL {
            try? await revokeOnServer(credentials: credentials, revokeURL: revokeURL)
        }
        
        // Remove from Keychain
        try KeychainManager.shared.deleteCredentials(forAccount: accountId)
    }
    
    // MARK: - Private Methods
    
    /// Get authorization code via web authentication
    private func getAuthorizationCode(config: OAuthConfig, provider: CloudProvider) async throws -> String {
        // Build authorization URL
        var components = URLComponents(string: config.authURL)!
        
        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"), // For refresh tokens
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        // Provider-specific parameters
        switch provider {
        case .dropbox:
            components.queryItems?.append(URLQueryItem(name: "token_access_type", value: "offline"))
        case .googleDrive:
            components.queryItems?.append(URLQueryItem(name: "include_granted_scopes", value: "true"))
        default:
            break
        }
        
        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }
        
        // Start web authentication
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: config.redirectURI.components(separatedBy: "://").first,
                    completionHandler: { callbackURL, error in
                        if let error = error {
                            continuation.resume(throwing: OAuthError.authenticationFailed(error))
                            return
                        }
                        
                        guard let callbackURL = callbackURL,
                              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                            continuation.resume(throwing: OAuthError.noAuthorizationCode)
                            return
                        }
                        
                        // Store code verifier for token exchange
                        UserDefaults.standard.set(codeVerifier, forKey: "oauth_code_verifier")
                        
                        continuation.resume(returning: code)
                    }
                )
                
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                
                if !session.start() {
                    continuation.resume(throwing: OAuthError.failedToStartSession)
                }
                
                self.currentSession = session
            }
        }
    }
    
    /// Exchange authorization code for access token
    private func exchangeCodeForTokens(code: String, config: OAuthConfig) async throws -> TokenResponse {
        guard let tokenURL = URL(string: config.tokenURL) else {
            throw OAuthError.invalidURL
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Get stored code verifier
        let codeVerifier = UserDefaults.standard.string(forKey: "oauth_code_verifier") ?? ""
        UserDefaults.standard.removeObject(forKey: "oauth_code_verifier")
        
        let bodyParams = [
            "code": code,
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OAuthError.tokenExchangeFailed
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }
    
    /// Refresh access token using refresh token
    private func refreshAccessToken(refreshToken: String, config: OAuthConfig) async throws -> TokenResponse {
        guard let tokenURL = URL(string: config.tokenURL) else {
            throw OAuthError.invalidURL
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "refresh_token": refreshToken,
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OAuthError.tokenRefreshFailed
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }
    
    /// Revoke credentials on server
    private func revokeOnServer(credentials: CloudCredentials, revokeURL: String) async throws {
        guard let url = URL(string: revokeURL), let token = credentials.accessToken else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(token)".data(using: .utf8)
        
        _ = try await URLSession.shared.data(for: request)
    }
    
    // MARK: - PKCE Helpers
    
    /// Generate code verifier for PKCE
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// Generate code challenge from verifier
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - ASWeb AuthenticationPresentationContextProviding

extension OAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Supporting Types

struct OAuthConfig {
    let clientId: String
    let clientSecret: String
    let authURL: String
    let tokenURL: String
    let redirectURI: String
    let scope: String
    var revokeURL: String?
}

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
}

struct OAuthResult {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
}

// MARK: - OAuth Errors

enum OAuthError: Error, LocalizedError {
    case unsupportedProvider
    case invalidURL
    case authenticationFailed(Error)
    case noAuthorizationCode
    case failedToStartSession
    case tokenExchangeFailed
    case tokenRefreshFailed
    case credentialsNotFound
    case noRefreshToken
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "This cloud provider is not supported"
        case .invalidURL:
            return "Invalid OAuth URL"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .noAuthorizationCode:
            return "No authorization code received"
        case .failedToStartSession:
            return "Failed to start authentication session"
        case .tokenExchangeFailed:
            return "Failed to exchange code for tokens"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .credentialsNotFound:
            return "Credentials not found in Keychain"
        case .noRefreshToken:
            return "No refresh token available"
        }
    }
}

// SHA256 is already available from Crypto Kit - no extension needed
