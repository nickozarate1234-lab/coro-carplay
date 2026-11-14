import Foundation
import Security

struct SpotifyCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum KeychainStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Coro.Spotify",
         kSecAttrAccount as String: "oauth"]
    }
    static func load() -> SpotifyCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyCredentials.self, from: data)
    }
    static func save(_ credentials: SpotifyCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data,
                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            update.forEach { add[$0.key] = $0.value }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw CoroError.message("No se pudo guardar el acceso de Spotify en este iPhone.") }
        } else if status != errSecSuccess {
            throw CoroError.message("No se pudo actualizar el acceso guardado de Spotify.")
        }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
