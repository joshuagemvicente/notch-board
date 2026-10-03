import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain error (\(status)): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }
}

/// Keychain wrapper. Prefers the data-protection keychain (no legacy “Always Allow”
/// ACL dialog). Ad-hoc / unsigned builds lack the required entitlement (−34018), so
/// those fall back to the login keychain automatically.
struct KeychainService: TokenStore {
    func save(_ token: String, service: ServiceKind, accountID: UUID) throws {
        try save(token, serviceName: keychainService(service), account: accountID.uuidString)
    }

    func load(service: ServiceKind, accountID: UUID) throws -> String? {
        try load(serviceName: keychainService(service), account: accountID.uuidString)
    }

    func delete(service: ServiceKind, accountID: UUID) throws {
        try delete(serviceName: keychainService(service), account: accountID.uuidString)
    }

    // MARK: - Generic items (non-board secrets, e.g. AI usage admin keys)

    func save(_ token: String, serviceName: String, account: String) throws {
        // Clear any prior copies so reconnects don't leave stale items.
        deleteQuietly(serviceName: serviceName, account: account, dataProtection: true)
        deleteQuietly(serviceName: serviceName, account: account, dataProtection: false)

        let data = Data(token.utf8)
        let modernStatus = add(data, serviceName: serviceName, account: account, dataProtection: true)
        if modernStatus == errSecSuccess { return }

        // −34018 errSecMissingEntitlement: data-protection keychain needs a real
        // code signature / team. Open-source ad-hoc builds hit this path.
        if modernStatus == errSecMissingEntitlement {
            let legacyStatus = add(data, serviceName: serviceName, account: account, dataProtection: false)
            guard legacyStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(legacyStatus)
            }
            return
        }

        throw KeychainError.unexpectedStatus(modernStatus)
    }

    func load(serviceName: String, account: String) throws -> String? {
        if let modern = try load(serviceName: serviceName, account: account, dataProtection: true) {
            return modern
        }
        // Migrate items saved before data-protection (or via the ad-hoc fallback).
        guard let legacy = try load(serviceName: serviceName, account: account, dataProtection: false) else {
            return nil
        }
        // Best-effort upgrade when the entitlement becomes available (signed builds).
        try? save(legacy, serviceName: serviceName, account: account)
        return legacy
    }

    func delete(serviceName: String, account: String) throws {
        let modern = deleteStatus(serviceName: serviceName, account: account, dataProtection: true)
        let legacy = deleteStatus(serviceName: serviceName, account: account, dataProtection: false)
        let ok: Set<OSStatus> = [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement]
        guard ok.contains(modern), ok.contains(legacy) else {
            let bad = ok.contains(modern) ? legacy : modern
            throw KeychainError.unexpectedStatus(bad)
        }
    }

    // MARK: - Internals

    private func add(
        _ data: Data,
        serviceName: String,
        account: String,
        dataProtection: Bool
    ) -> OSStatus {
        var query = baseQuery(serviceName: serviceName, account: account, dataProtection: dataProtection)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil)
    }

    private func load(serviceName: String, account: String, dataProtection: Bool) throws -> String? {
        var query = baseQuery(serviceName: serviceName, account: account, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteQuietly(serviceName: String, account: String, dataProtection: Bool) {
        _ = deleteStatus(serviceName: serviceName, account: account, dataProtection: dataProtection)
    }

    private func deleteStatus(
        serviceName: String,
        account: String,
        dataProtection: Bool
    ) -> OSStatus {
        SecItemDelete(baseQuery(serviceName: serviceName, account: account, dataProtection: dataProtection) as CFDictionary)
    }

    private func baseQuery(serviceName: String, account: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func keychainService(_ service: ServiceKind) -> String {
        "notchboard.\(service.rawValue)"
    }
}
