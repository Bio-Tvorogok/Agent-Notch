import Foundation
import Security

/// Where a service's `secret` fields live. The app uses the Keychain; checks and snapshots use memory.
public protocol ServiceSecretStore: AnyObject {
    func read(_ service: String, _ key: String) -> String?
    /// Whether a value is stored, without reading it.
    func contains(_ service: String, _ key: String) -> Bool
    /// nil or empty deletes.
    func write(_ value: String?, _ service: String, _ key: String) throws
}

public extension ServiceSecretStore {
    /// Every stored secret of a service, by field key.
    func all(_ manifest: ServiceManifest) -> [String: String] {
        var secrets: [String: String] = [:]
        for field in manifest.fields where field.kind == .secret { secrets[field.key] = read(manifest.id, field.key) }
        return secrets
    }

    func removeAll(_ service: String, keys: [String]) {
        for key in keys { try? write(nil, service, key) }
    }
}

public final class MemorySecretStore: ServiceSecretStore {
    private var values: [String: String] = [:]
    public init() {}
    public func read(_ service: String, _ key: String) -> String? { values[service + "\n" + key] }
    public func contains(_ service: String, _ key: String) -> Bool { read(service, key) != nil }
    public func write(_ value: String?, _ service: String, _ key: String) throws {
        values[service + "\n" + key] = value?.isEmpty == false ? value : nil
    }
}

/// Generic passwords in the login keychain: service `com.forichok.agents-notch.service.<id>`, account = field key.
public final class KeychainSecretStore: ServiceSecretStore {
    public struct Failure: LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? {
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return Loc.t("Keychain: ", "Связка ключей: ") + text
        }
    }

    public init() {}

    static func service(_ id: String) -> String { "com.forichok.agents-notch.service." + id }

    private func query(_ service: String, _ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service(service),
         kSecAttrAccount as String: key]
    }

    public func read(_ service: String, _ key: String) -> String? {
        var q = query(service, key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func contains(_ service: String, _ key: String) -> Bool {
        var q = query(service, key)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    public func write(_ value: String?, _ service: String, _ key: String) throws {
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query(service, key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
            return
        }
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(service, key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure(status: update) }
        var add = query(service, key)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Agent Notch: \(service) \(key)"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
