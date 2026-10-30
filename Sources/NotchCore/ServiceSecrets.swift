import Foundation
import Security

/// Where a service's `secret` fields live. The app uses the Keychain; checks and snapshots use memory.
/// `scope` is a service's `secretScope`: its id and its folder.
public protocol ServiceSecretStore: AnyObject {
    func read(_ scope: String, _ key: String) -> String?
    /// Whether a value is stored, without reading it.
    func contains(_ scope: String, _ key: String) -> Bool
    /// nil or empty deletes.
    func write(_ value: String?, _ scope: String, _ key: String) throws
    /// The keys stored under a scope, including ones the current manifest no longer has.
    func keys(_ scope: String) -> [String]
    /// Every secret of the scope.
    func removeAll(_ scope: String) throws
}

public extension ServiceSecretStore {
    /// Every stored secret of a service, by field key.
    func all(_ manifest: ServiceManifest) -> [String: String] {
        var secrets: [String: String] = [:]
        for field in manifest.fields where field.kind == .secret { secrets[field.key] = read(manifest.secretScope, field.key) }
        return secrets
    }
}

public final class MemorySecretStore: ServiceSecretStore {
    private var values: [String: String] = [:]
    public init() {}
    public func read(_ scope: String, _ key: String) -> String? { values[scope + "\n" + key] }
    public func contains(_ scope: String, _ key: String) -> Bool { read(scope, key) != nil }
    public func write(_ value: String?, _ scope: String, _ key: String) throws {
        values[scope + "\n" + key] = value?.isEmpty == false ? value : nil
    }
    public func keys(_ scope: String) -> [String] {
        values.keys.filter { $0.hasPrefix(scope + "\n") }.map { String($0.dropFirst(scope.count + 1)) }.sorted()
    }
    public func removeAll(_ scope: String) throws {
        values = values.filter { !$0.key.hasPrefix(scope + "\n") }
    }
}

/// Generic passwords in the login keychain: service `com.forichok.agents-notch.service.<id>.<folder hash>`, account = field key.
/// The item's access list names the app by its signature; an ad-hoc signed build is identified by its bundle id alone,
/// so this keeps secrets off disk and out of preferences, not away from other code running as the same user.
public final class KeychainSecretStore: ServiceSecretStore {
    public struct Failure: LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? {
            let text = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return Loc.t("Keychain: ", "Связка ключей: ") + text
        }
    }

    public init() {}

    static func service(_ scope: String) -> String { "com.forichok.agents-notch.service." + scope }

    private func query(_ scope: String, _ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service(scope),
         kSecAttrAccount as String: key]
    }

    public func keys(_ scope: String) -> [String] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service(scope),
                                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var items: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &items) == errSecSuccess, let list = items as? [[String: Any]] else { return [] }
        return list.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    public func removeAll(_ scope: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service(scope)] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
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

    /// Saving deletes and adds rather than updates: an item someone created in advance would keep its own access list.
    public func write(_ value: String?, _ scope: String, _ key: String) throws {
        let deleted = SecItemDelete(query(scope, key) as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw Failure(status: deleted) }
        guard let value, !value.isEmpty else { return }
        var add = query(scope, key)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrLabel as String] = "Agent Notch: \(scope) \(key)"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
