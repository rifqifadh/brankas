import Foundation
import Security
import LocalAuthentication

struct KeychainService {
    private static let serviceName = "com.rifqifadhlillah.brankas.vault"
    private static let accountName = "vault-password"

    static func saveVaultPassword(_ password: String) throws {
        guard let data = password.data(using: .utf8) else { throw KeychainError.encodingFailed }

        deleteVaultPassword()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    static func readVaultPassword() throws -> String {
        let context = LAContext()
        var authError: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)

        guard canEvaluate else {
            throw KeychainError.biometricsUnavailable(authError?.localizedDescription ?? "Biometrics not available")
        }

        var isAuthed = false
        var authErrorDescription: String?

        let semaphore = DispatchSemaphore(value: 0)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Brankas with Touch ID") { success, error in
            isAuthed = success
            if !success { authErrorDescription = error?.localizedDescription }
            semaphore.signal()
        }
        semaphore.wait()

        guard isAuthed else {
            throw KeychainError.authFailed(authErrorDescription ?? "Authentication cancelled")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.readFailed(status)
        }

        return password
    }

    static func deleteVaultPassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasSavedPassword: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case biometricsUnavailable(String)
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Failed to encode password"
        case .saveFailed(let status): "Keychain save failed: \(status)"
        case .readFailed(let status): "Keychain read failed: \(status)"
        case .biometricsUnavailable(let msg): msg
        case .authFailed(let msg): msg
        }
    }
}
