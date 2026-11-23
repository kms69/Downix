//
//  KeychainManager.swift
//  Download Manager for Mac - Secure Credential Storage
//
//  Created on February 16, 2026
//

import Foundation
import Security

/// Manages secure storage of credentials in macOS Keychain
class KeychainManager {
    
    static let shared = KeychainManager()
    
    private let serviceName = "com.rapiddownload.manager"
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Save credentials to Keychain
    func saveCredentials(_ credentials: CloudCredentials) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        
        // Check if item already exists
        if try fetchCredentials(forAccount: credentials.accountId) != nil {
            // Update existing item
            try updateCredentials(credentials)
        } else {
            // Add new item
            try addCredentials(data, accountId: credentials.accountId)
        }
    }
    
    /// Fetch credentials from Keychain
    func fetchCredentials(forAccount accountId: String) throws -> CloudCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: accountId,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status != errSecItemNotFound else {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(CloudCredentials.self, from: data)
    }
    
    /// Delete credentials from Keychain
    func deleteCredentials(forAccount accountId: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: accountId
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Update existing credentials in Keychain
    private func updateCredentials(_ credentials: CloudCredentials) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: credentials.accountId
        ]
        
        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// Add new credentials to Keychain
    private func addCredentials(_ data: Data, accountId: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: accountId,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    /// List all stored account IDs
    func listStoredAccounts() throws -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status != errSecItemNotFound else {
            return []
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let items = result as? [[CFString: Any]] else {
            return []
        }
        
        return items.compactMap { $0[kSecAttrAccount] as? String }
    }
    
    /// Clear all credentials (for testing/reset)
    func clearAllCredentials() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case unhandledError(status: OSStatus)
    case unexpectedData
    case itemNotFound
    
    var errorDescription: String? {
        switch self {
        case .unhandledError(let status):
            if let errorMessage = SecCopyErrorMessageString(status, nil) {
                return "Keychain error: \(errorMessage)"
            }
            return "Keychain error: \(status)"
        case .unexpectedData:
            return "Unexpected data format in Keychain"
        case .itemNotFound:
            return "Credentials not found in Keychain"
        }
    }
}
