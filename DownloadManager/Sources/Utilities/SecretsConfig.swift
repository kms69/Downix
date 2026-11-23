//
//  SecretsConfig.swift
//  Download Manager for Mac - Secure Configuration
//
//  Created on February 17, 2026
//

import Foundation

/// Secure configuration manager for sensitive credentials
/// This loads OAuth secrets from environment variables or a local config file
struct SecretsConfig {
    
    /// OAuth configuration for a specific provider
    struct OAuthSecrets {
        let clientId: String
        let clientSecret: String
        
        var isConfigured: Bool {
            !clientId.isEmpty && !clientSecret.isEmpty && 
            !clientId.hasPrefix("YOUR_") && !clientSecret.hasPrefix("YOUR_")
        }
    }
    
    // MARK: - Environment Variable Keys
    
    private enum EnvKey {
        static let dropboxClientId = "DROPBOX_CLIENT_ID"
        static let dropboxClientSecret = "DROPBOX_CLIENT_SECRET"
        
        static let googleClientId = "GOOGLE_CLIENT_ID"
        static let googleClientSecret = "GOOGLE_CLIENT_SECRET"
        
        static let oneDriveClientId = "ONEDRIVE_CLIENT_ID"
        static let oneDriveClientSecret = "ONEDRIVE_CLIENT_SECRET"
        
        static let boxClientId = "BOX_CLIENT_ID"
        static let boxClientSecret = "BOX_CLIENT_SECRET"
    }
    
    // MARK: - Public Methods
    
    /// Get OAuth secrets for Dropbox
    static func dropboxSecrets() -> OAuthSecrets {
        OAuthSecrets(
            clientId: getEnvironmentVariable(EnvKey.dropboxClientId),
            clientSecret: getEnvironmentVariable(EnvKey.dropboxClientSecret)
        )
    }
    
    /// Get OAuth secrets for Google Drive
    static func googleDriveSecrets() -> OAuthSecrets {
        OAuthSecrets(
            clientId: getEnvironmentVariable(EnvKey.googleClientId),
            clientSecret: getEnvironmentVariable(EnvKey.googleClientSecret)
        )
    }
    
    /// Get OAuth secrets for OneDrive
    static func oneDriveSecrets() -> OAuthSecrets {
        OAuthSecrets(
            clientId: getEnvironmentVariable(EnvKey.oneDriveClientId),
            clientSecret: getEnvironmentVariable(EnvKey.oneDriveClientSecret)
        )
    }
    
    /// Get OAuth secrets for Box
    static func boxSecrets() -> OAuthSecrets {
        OAuthSecrets(
            clientId: getEnvironmentVariable(EnvKey.boxClientId),
            clientSecret: getEnvironmentVariable(EnvKey.boxClientSecret)
        )
    }
    
    // MARK: - Private Helpers
    
    /// Get value from environment variable or config file
    private static func getEnvironmentVariable(_ key: String) -> String {
        // 1. Try to get from environment variables
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        
        // 2. Try to load from local config file (Secrets.plist)
        if let value = loadFromConfigFile(key: key), !value.isEmpty {
            return value
        }
        
        // 3. Return empty string if not found
        return ""
    }
    
    /// Load secrets from local Secrets.plist file (not tracked in git)
    private static func loadFromConfigFile(key: String) -> String? {
        // Look for Secrets.plist in the app bundle or project directory
        let configFileName = "Secrets"
        
        // Try to find the file in various locations
        if let configURL = Bundle.main.url(forResource: configFileName, withExtension: "plist") {
            if let config = NSDictionary(contentsOf: configURL) as? [String: Any] {
                return config[key] as? String
            }
        }
        
        // Try in the DownloadManager Resources directory
        let resourcesPath = FileManager.default.currentDirectoryPath + "/DownloadManager/Resources/Secrets.plist"
        if let config = NSDictionary(contentsOfFile: resourcesPath) as? [String: Any] {
            return config[key] as? String
        }
        
        return nil
    }
}
