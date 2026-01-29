//
//  KeychainManager.swift
//  WarDragon
//
//  Secure storage for sensitive credentials (passwords, API keys)
//  Use this instead of UserDefaults for sensitive data
//

import Foundation
import Security

enum KeychainError: Error {
    case duplicateItem
    case itemNotFound
    case invalidData
    case unexpectedStatus(OSStatus)
}

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Save
    
    /// Save a string value to the Keychain
    func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        try save(data, forKey: key)
    }
    
    /// Save data to the Keychain
    func save(_ data: Data, forKey key: String) throws {
        // Check if item already exists
        if (try? load(key: key)) != nil {
            // Update existing item
            try update(data, forKey: key)
            return
        }
        
        // Add new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Load
    
    /// Load a string value from the Keychain
    func loadString(forKey key: String) throws -> String {
        let data = try load(key: key)
        
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return string
    }
    
    /// Load data from the Keychain
    func load(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
    
    // MARK: - Update
    
    /// Update an existing Keychain item
    private func update(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Delete
    
    /// Delete a Keychain item
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Check if an item exists in the Keychain
    func exists(key: String) -> Bool {
        return (try? load(key: key)) != nil
    }
    
    /// Get all keys stored in Keychain (for debugging)
    func allKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { item in
            item[kSecAttrAccount as String] as? String
        }
    }
    
    /// Delete all Keychain items (use with caution!)
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: - Usage Examples & Migration Helper

extension KeychainManager {
    /// Migrate sensitive data from UserDefaults to Keychain
    static func migrateSensitiveData() {
        let keysToMigrate = [
            "takP12Password",
            "webhookPassword",
            "mqttPassword",
            // Add other sensitive keys here
        ]
        
        for key in keysToMigrate {
            // Check if exists in UserDefaults
            if let value = UserDefaults.standard.string(forKey: key) {
                do {
                    // Save to Keychain
                    try shared.save(value, forKey: key)
                    
                    // Remove from UserDefaults
                    UserDefaults.standard.removeObject(forKey: key)
                    
                    print("Migrated \(key) to Keychain")
                } catch {
                    print("Failed to migrate \(key): \(error)")
                }
            }
        }
    }
}

// MARK: - Property Wrapper for Easy Access

@propertyWrapper
struct KeychainStorage {
    let key: String
    let defaultValue: String
    
    var wrappedValue: String {
        get {
            return (try? KeychainManager.shared.loadString(forKey: key)) ?? defaultValue
        }
        set {
            if newValue.isEmpty {
                try? KeychainManager.shared.delete(key: key)
            } else {
                try? KeychainManager.shared.save(newValue, forKey: key)
            }
        }
    }
}

// MARK: - Usage Example

/*
 Instead of:
 
 @AppStorage("takP12Password") var takP12Password: String = ""
 
 Use:
 
 @KeychainStorage(key: "takP12Password", defaultValue: "") 
 var takP12Password: String
 
 Or directly:
 
 // Save
 try KeychainManager.shared.save("mySecretPassword", forKey: "takP12Password")
 
 // Load
 let password = try KeychainManager.shared.loadString(forKey: "takP12Password")
 
 // Delete
 try KeychainManager.shared.delete(key: "takP12Password")
 
 // Check existence
 if KeychainManager.shared.exists(key: "takP12Password") {
     print("Password is stored")
 }
 */
