// LoopFollow
// PlateScanCredentials.swift

import Foundation
import Security

enum PlateScanCredentials {
    private static let service = "LoopFollow.optionalPlateScanner"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "accessToken", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ token: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "accessToken"]
        if token.isEmpty { let status = SecItemDelete(query as CFDictionary); return status == errSecSuccess || status == errSecItemNotFound }
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { return SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess }
        return status == errSecSuccess
    }
}
