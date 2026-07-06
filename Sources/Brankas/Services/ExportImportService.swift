import CryptoKit
import Foundation
import CommonCrypto

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

    func encryptExport(_ entries: [ExportEntry], password: String) throws -> Data {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(entries)

        // Generate random salt
        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }

        // Derive key with PBKDF2
        guard let key = deriveKey(password: password, salt: salt) else {
            throw ExportError.encryptionFailed
        }

        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealedBox.combined else {
            throw ExportError.encryptionFailed
        }

        // Prepend salt to encrypted data
        var exportData = salt
        exportData.append(combined)
        return exportData
    }

    func decryptExport(_ data: Data, password: String) throws -> [ExportEntry] {
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
        return try decoder.decode([ExportEntry].self, from: decryptedData)
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

    func unencryptedExport(_ entries: [ExportEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    func importUnencrypted(_ data: Data) throws -> [ExportEntry] {
        let decoder = JSONDecoder()
        return try decoder.decode([ExportEntry].self, from: data)
    }
}
