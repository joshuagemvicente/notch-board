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
        // Clear any prior copies so reconnects don't leave stale items.
        deleteQuietly(service: service, accountID: accountID, dataProtection: true)
        deleteQuietly(service: service, accountID: accountID, dataProtection: false)

        let data = Data(token.utf8)
        let modernStatus = add(data, service: service, accountID: accountID, dataProtection: true)
        if modernStatus == errSecSuccess { return }

        // −34018 errSecMissingEntitlement: data-protection keychain needs a real
        // code signature / team. Open-source ad-hoc builds hit this path.
        if modernStatus == errSecMissingEntitlement {
            let legacyStatus = add(data, service: service, accountID: accountID, dataProtection: false)
            guard legacyStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(legacyStatus)
            }
            return
        }

        throw KeychainError.unexpectedStatus(modernStatus)
    }

    func load(service: ServiceKind, accountID: UUID) throws -> String? {
        if let modern = try load(service: service, accountID: accountID, dataProtection: true) {
            return modern
        }
        // Migrate items saved before data-protection (or via the ad-hoc fallback).
        guard let legacy = try load(service: service, accountID: accountID, dataProtection: false) else {
            return nil
        }
        // Best-effort upgrade when the entitlement becomes available (signed builds).
        try? save(legacy, service: service, accountID: accountID)
        return legacy
    }

    func delete(service: ServiceKind, accountID: UUID) throws {
        let modern = deleteStatus(service: service, accountID: accountID, dataProtection: true)
        let legacy = deleteStatus(service: service, accountID: accountID, dataProtection: false)
        let ok: Set<OSStatus> = [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement]
        guard ok.contains(modern), ok.contains(legacy) else {
            let bad = ok.contains(modern) ? legacy : modern
            throw KeychainError.unexpectedStatus(bad)
        }
    }

    // MARK: - Internals

    private func add(
        _ data: Data,
        service: ServiceKind,
        accountID: UUID,
        dataProtection: Bool
    ) -> OSStatus {
        var query = baseQuery(service: service, accountID: accountID, dataProtection: dataProtection)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil)
    }

    private func load(service: ServiceKind, accountID: UUID, dataProtection: Bool) throws -> String? {
        var query = baseQuery(service: service, accountID: accountID, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteQuietly(service: ServiceKind, accountID: UUID, dataProtection: Bool) {
        _ = deleteStatus(service: service, accountID: accountID, dataProtection: dataProtection)
    }

    private func deleteStatus(
        service: ServiceKind,
        accountID: UUID,
        dataProtection: Bool
    ) -> OSStatus {
        SecItemDelete(baseQuery(service: service, accountID: accountID, dataProtection: dataProtection) as CFDictionary)
    }

    private func baseQuery(service: ServiceKind, accountID: UUID, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService(service),
            kSecAttrAccount as String: accountID.uuidString,
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
