import Foundation
import Security

public protocol ProfileStoring: Sendable {
    func save(_ profile: Profile) throws
    func load() throws -> Profile?
    func clear() throws
}

/// 個資存放於 iOS/macOS Keychain。
/// - kSecAttrAccessibleWhenUnlockedThisDeviceOnly：解鎖後可存取、且**不隨 iCloud/備份轉移**。
/// - kSecAttrSynchronizable = false：不同步到 iCloud Keychain。
public struct KeychainStore: ProfileStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.megshao.exerciserewards.profile", account: String = "primary") {
        self.service = service
        self.account = account
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    public func save(_ profile: Profile) throws {
        let data = try JSONEncoder().encode(profile)
        try clear()
        var q = baseQuery()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func load() throws -> Profile? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else {
            throw KeychainError.unhandled(status)
        }
        return try JSONDecoder().decode(Profile.self, from: data)
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

public enum KeychainError: Error, Equatable, Sendable {
    case unhandled(OSStatus)
}
