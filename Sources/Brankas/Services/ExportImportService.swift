import CryptoKit
import Foundation
import CommonCrypto

// MARK: - Export Models

struct ExportEntry: Codable {
    let id: UUID
    let name: String
    let type: String
    let value: String
    let categoryId: UUID?
    let tags: [String]
    let notes: String
    let url: String?
}

struct AccountExportEntry: Codable {
    let id: UUID
    let serviceName: String
    let serviceUrl: String?
    let serviceIcon: String
    let identifier: String
    let value: String
    let notes: String
    let expiresAt: Date?
    let hasTOTP: Bool
    let totpSecret: String?
    let isFavorite: Bool
}

struct ExportContainer: Codable {
    let version: Int
    let items: [ExportEntry]
    let accounts: [AccountExportEntry]
}

enum ExportError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: "Failed to encrypt export"
        case .decryptionFailed: "Failed to decrypt export"
        case .invalidPassword: "Invalid password or corrupted data"
        }
    }
}

struct ExportImportService {
    private let pbkdf2Iterations: UInt32 = 100_000
    private let keyLength = 32
    private let saltLength = 16

    func encryptExport(items: [ExportEntry], accounts: [AccountExportEntry], password: String) throws -> Data {
        let container = ExportContainer(version: 2, items: items, accounts: accounts)
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(container)

        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }

        guard let key = deriveKey(password: password, salt: salt) else {
            throw ExportError.encryptionFailed
        }

        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealedBox.combined else {
            throw ExportError.encryptionFailed
        }

        var exportData = salt
        exportData.append(combined)
        return exportData
    }

    func decryptExport(_ data: Data, password: String) throws -> ExportContainer {
        guard data.count > saltLength else { throw ExportError.invalidPassword }

        let salt = data[..<saltLength]
        let encryptedData = data[saltLength...]

        guard let key = deriveKey(password: password, salt: salt) else {
            throw ExportError.invalidPassword
        }

        guard let sealedBox = try? AES.GCM.SealedBox(combined: Data(encryptedData)) else {
            throw ExportError.invalidPassword
        }

        let decryptedData: Data
        do {
            decryptedData = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw ExportError.decryptionFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try new container format first
        if let container = try? decoder.decode(ExportContainer.self, from: decryptedData) {
            return container
        }

        // Fallback: old format (array of ExportEntry, pre-v2)
        if let legacyItems = try? decoder.decode([ExportEntry].self, from: decryptedData) {
            return ExportContainer(version: 1, items: legacyItems, accounts: [])
        }

        throw ExportError.decryptionFailed
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey? {
        let passwordData = Data(password.utf8)
        var derivedKey = [UInt8](repeating: 0, count: keyLength)

        let status = passwordData.withUnsafeBytes { pwBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdf2Iterations,
                    &derivedKey,
                    derivedKey.count
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: Data(derivedKey))
    }

    func unencryptedExport(items: [ExportEntry], accounts: [AccountExportEntry]) throws -> Data {
        let container = ExportContainer(version: 2, items: items, accounts: accounts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(container)
    }

    func importUnencrypted(_ data: Data) throws -> ExportContainer {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let container = try? decoder.decode(ExportContainer.self, from: data) {
            return container
        }
        if let legacyItems = try? decoder.decode([ExportEntry].self, from: data) {
            return ExportContainer(version: 1, items: legacyItems, accounts: [])
        }
        throw ExportError.decryptionFailed
    }
}
