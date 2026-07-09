import Foundation
import CryptoKit
import SwiftData
import CommonCrypto

enum VaultError: LocalizedError {
    case notLoaded
    case encodingFailed
    case encryptionFailed
    case decryptionFailed
    case invalidPassword
    case saveFailed(String)
    case keyNotFound
    case migrateFromOld

    var errorDescription: String? {
        switch self {
        case .notLoaded: "Vault not loaded"
        case .encodingFailed: "Failed to encode data"
        case .encryptionFailed: "Failed to encrypt vault"
        case .decryptionFailed: "Failed to decrypt vault"
        case .invalidPassword: "Invalid master password"
        case .saveFailed(let msg): "Save failed: \(msg)"
        case .keyNotFound: "Key not found"
        case .migrateFromOld: "Migrating from old format"
        }
    }
}

struct VaultService {
    private static var vaultData: VaultData = .empty()
    private static var isLoaded = false
    private(set) static var password: String = ""

    private static let pbkdf2Iterations: UInt32 = 100_000
    private static let keyLength = 32  // AES-256

    static var storeURL: URL {
        #if DEBUG
        URL.applicationSupportDirectory.appendingPathComponent("brankas-vault-debug.enc")
        #else
        URL.applicationSupportDirectory.appendingPathComponent("brankas-vault.enc")
        #endif
    }

    private static var saltURL: URL {
        storeURL.deletingPathExtension().appendingPathExtension("salt")
    }

    static func isFirstLaunch() -> Bool {
        !FileManager.default.fileExists(atPath: storeURL.path)
    }

    // MARK: - Key Derivation

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey? {
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

    private static func generateSalt() -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 16, buffer.baseAddress!)
        }
        return salt
    }

    private static func loadSalt() -> Data? {
        guard let salt = try? Data(contentsOf: saltURL), salt.count == 16 else { return nil }
        return salt
    }

    private static func ensureSalt() -> Data {
        if let salt = loadSalt() { return salt }
        let salt = generateSalt()
        try? salt.write(to: saltURL, options: .atomic)
        return salt
    }

    // MARK: - Load

    static func load(password: String) throws {
        let url = storeURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // First launch — create empty vault with PBKDF2
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.password = password
            vaultData = .empty()
            isLoaded = true
            _ = ensureSalt()  // generate salt before first persist
            try persist()
            return
        }

        guard let encryptedData = try? Data(contentsOf: url) else {
            throw VaultError.decryptionFailed
        }

        // Try PBKDF2 (new format)
        if let salt = loadSalt(),
           let key = deriveKey(password: password, salt: salt),
           let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData) {

            if let decryptedData = try? AES.GCM.open(sealedBox, using: key),
               let vault = try? decoder.decode(VaultData.self, from: decryptedData) {
                self.password = password
                vaultData = vault
                isLoaded = true
                return
            }

            // Try legacy flat dict format
            if let decryptedData = try? AES.GCM.open(sealedBox, using: key),
               let oldDict = try? decoder.decode([String: String].self, from: decryptedData) {
                self.password = password
                vaultData = .empty()
                vaultData.secrets = oldDict
                isLoaded = true
                try persist()
                return
            }
        }

        // Try SHA256 (legacy format) — migration path
        let legacyKey = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        if let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
           let decryptedData = try? AES.GCM.open(sealedBox, using: legacyKey) {

            // Legacy decryption succeeded — migrate to PBKDF2
            self.password = password
            _ = ensureSalt()  // generate salt for migration

            if let vault = try? decoder.decode(VaultData.self, from: decryptedData) {
                vaultData = vault
            } else if let oldDict = try? decoder.decode([String: String].self, from: decryptedData) {
                vaultData = .empty()
                vaultData.secrets = oldDict
            } else {
                throw VaultError.decryptionFailed
            }

            isLoaded = true
            try persist()  // re-encrypt with PBKDF2
            return
        }

        throw VaultError.invalidPassword
    }

    // MARK: - Persist

    static func persist() throws {
        guard isLoaded else { throw VaultError.notLoaded }
        vaultData.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(vaultData) else {
            throw VaultError.encodingFailed
        }

        let salt = ensureSalt()
        guard let key = deriveKey(password: password, salt: salt) else {
            throw VaultError.encryptionFailed
        }

        guard let sealedBox = try? AES.GCM.seal(jsonData, using: key),
              let combined = sealedBox.combined else {
            throw VaultError.encryptionFailed
        }

        try combined.write(to: storeURL, options: .atomic)
    }

    // MARK: - Lock / Reset

    static func lock() {
        password = ""
        isLoaded = false
        vaultData = .empty()
    }

    static func reset(context: ModelContext) {
        vaultData = .empty()
        isLoaded = false
        password = ""
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: saltURL)

        for item in (try? context.fetch(FetchDescriptor<SecretItem>())) ?? [] { context.delete(item) }
        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] { context.delete(account) }
        for service in (try? context.fetch(FetchDescriptor<Service>())) ?? [] { context.delete(service) }
        for category in (try? context.fetch(FetchDescriptor<Category>())) ?? [] { context.delete(category) }
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] { context.delete(tag) }
        try? context.save()
    }

    // MARK: - Secrets

    static func read(for key: String) throws -> String {
        guard isLoaded else { throw VaultError.notLoaded }
        guard let value = vaultData.secrets[key] else { throw VaultError.keyNotFound }
        return value
    }

    static func save(secret: String, for key: String) throws {
        guard isLoaded else { throw VaultError.notLoaded }
        vaultData.secrets[key] = secret
        try persist()
    }

    static func deleteSecret(for key: String) throws {
        guard isLoaded else { throw VaultError.notLoaded }
        vaultData.secrets.removeValue(forKey: key)
        try persist()
    }

    static func hasKey(_ key: String) -> Bool {
        guard isLoaded else { return false }
        return vaultData.secrets[key] != nil
    }

    // MARK: - Items (SecretItem)
    @discardableResult
    static func createItem(data: SecretItemData, secret: String, context: ModelContext) throws -> SecretItem {
        guard isLoaded else { throw VaultError.notLoaded }
        vaultData.items.append(data)
        vaultData.secrets[data.id.uuidString] = secret
        try persist()
        return syncItem(data, context: context)
    }

    static func updateItem(data: SecretItemData, secret: String, context: ModelContext) throws {
        guard isLoaded else { throw VaultError.notLoaded }
        if let idx = vaultData.items.firstIndex(where: { $0.id == data.id }) {
            vaultData.items[idx] = data
        }
        vaultData.secrets[data.id.uuidString] = secret
        try persist()
        syncItem(data, context: context)
    }

    static func deleteItem(id: UUID, context: ModelContext) throws {
        guard isLoaded else { throw VaultError.notLoaded }
        vaultData.items.removeAll { $0.id == id }
        vaultData.secrets.removeValue(forKey: id.uuidString)
        vaultData.secrets.removeValue(forKey: "totp-\(id.uuidString)")
        try persist()

        if let item = try? context.fetch(FetchDescriptor<SecretItem>(predicate: #Predicate { $0.id == id })).first {
            context.delete(item)
            try? context.save()
        }
    }

    @discardableResult
    private static func syncItem(_ data: SecretItemData, context: ModelContext) -> SecretItem {
        if let existing = try? context.fetch(FetchDescriptor<SecretItem>(predicate: #Predicate { $0.id == data.id })).first {
            existing.name = data.name
            existing.typeRawValue = data.typeRawValue
            existing.categoryId = data.categoryId
            existing.notes = data.notes
            existing.url = data.url
            existing.expiresAt = data.expiresAt
            existing.hasTOTP = data.hasTOTP
            existing.isFavorite = data.isFavorite
            existing.updatedAt = data.updatedAt
            let tags = data.tagIds.compactMap { tid in
                try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.id == tid })).first
            }
            existing.tags = tags
            try? context.save()
            return existing
        }

        let item = SecretItem(
            id: data.id,
            name: data.name,
            type: SecretType(rawValue: data.typeRawValue) ?? .token,
            categoryId: data.categoryId,
            tags: data.tagIds.compactMap { tid in
                try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.id == tid })).first
            },
            notes: data.notes,
            url: data.url,
            expiresAt: data.expiresAt,
            hasTOTP: data.hasTOTP,
            isFavorite: data.isFavorite
        )
        item.createdAt = data.createdAt
        item.updatedAt = data.updatedAt
        context.insert(item)
        try? context.save()
        return item
    }

    // MARK: - Accounts

    @discardableResult
    static func createAccount(data: AccountData, secret: String, context: ModelContext) throws -> Account {
        guard isLoaded else { throw VaultError.notLoaded }
        vaultData.accounts.append(data)
        vaultData.secrets[data.id.uuidString] = secret
        try persist()
        return syncAccount(data, context: context)
    }

    static func updateAccount(data: AccountData, secret: String, context: ModelContext) throws {
        guard isLoaded else { throw VaultError.notLoaded }
        if let idx = vaultData.accounts.firstIndex(where: { $0.id == data.id }) {
            vaultData.accounts[idx] = data
        }
        vaultData.secrets[data.id.uuidString] = secret
        try persist()
        syncAccount(data, context: context)
    }

    static func deleteAccount(id: UUID, context: ModelContext) throws {
        guard isLoaded else { throw VaultError.notLoaded }
        vaultData.accounts.removeAll { $0.id == id }
        vaultData.secrets.removeValue(forKey: id.uuidString)
        vaultData.secrets.removeValue(forKey: "totp-\(id.uuidString)")
        try persist()

        if let account = try? context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })).first {
            context.delete(account)
            try? context.save()
        }
    }

    @discardableResult
    private static func syncAccount(_ data: AccountData, context: ModelContext) -> Account {
        let service = try? context.fetch(FetchDescriptor<Service>(predicate: #Predicate { $0.id == data.serviceId })).first
        guard let svc = service else { fatalError("Service not found for account") }

        if let existing = try? context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == data.id })).first {
            existing.identifier = data.identifier
            existing.notes = data.notes
            existing.expiresAt = data.expiresAt
            existing.hasTOTP = data.hasTOTP
            existing.isFavorite = data.isFavorite
            existing.updatedAt = data.updatedAt
            existing.service = svc
            try? context.save()
            return existing
        }

        let account = Account(
            id: data.id,
            identifier: data.identifier,
            notes: data.notes,
            expiresAt: data.expiresAt,
            hasTOTP: data.hasTOTP,
            isFavorite: data.isFavorite,
            service: svc
        )
        account.createdAt = data.createdAt
        account.updatedAt = data.updatedAt
        context.insert(account)
        try? context.save()
        return account
    }

    // MARK: - Services
    @discardableResult
    static func createService(data: ServiceData, context: ModelContext) throws -> Service {
        vaultData.services.append(data)
        try persist()
        let svc = Service(name: data.name, url: data.url, icon: data.icon)
        svc.id = data.id
        context.insert(svc)
        try? context.save()
        return svc
    }

    static func updateService(data: ServiceData, context: ModelContext) throws {
        if let idx = vaultData.services.firstIndex(where: { $0.id == data.id }) {
            vaultData.services[idx] = data
        }
        try persist()
        if let svc = try? context.fetch(FetchDescriptor<Service>(predicate: #Predicate { $0.id == data.id })).first {
            svc.name = data.name
            svc.url = data.url
            svc.icon = data.icon
            try? context.save()
        }
    }

    static func deleteService(id: UUID, context: ModelContext) throws {
        vaultData.accounts.removeAll { $0.serviceId == id }
        vaultData.services.removeAll { $0.id == id }
        try persist()

        for account in (try? context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.service.id == id }))) ?? [] {
            vaultData.secrets.removeValue(forKey: account.id.uuidString)
            vaultData.secrets.removeValue(forKey: "totp-\(account.id.uuidString)")
            context.delete(account)
        }
        if let svc = try? context.fetch(FetchDescriptor<Service>(predicate: #Predicate { $0.id == id })).first {
            context.delete(svc)
        }
        try? context.save()
    }

    // MARK: - Categories
    @discardableResult
    static func createCategory(data: CategoryData, context: ModelContext) throws -> Category {
        vaultData.categories.append(data)
        try persist()
        let cat = Category(id: data.id, name: data.name, icon: data.icon, colorHex: data.colorHex, sortOrder: data.sortOrder)
        context.insert(cat)
        try? context.save()
        return cat
    }

    static func updateCategory(data: CategoryData, context: ModelContext) throws {
        if let idx = vaultData.categories.firstIndex(where: { $0.id == data.id }) {
            vaultData.categories[idx] = data
        }
        try persist()
        if let cat = try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == data.id })).first {
            cat.name = data.name
            cat.icon = data.icon
            cat.colorHex = data.colorHex
            cat.sortOrder = data.sortOrder
            try? context.save()
        }
    }

    static func deleteCategory(id: UUID, context: ModelContext) throws {
        vaultData.categories.removeAll { $0.id == id }
        try persist()
        if let cat = try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == id })).first {
            context.delete(cat)
            try? context.save()
        }
    }

    // MARK: - Tags

    static func createTag(data: TagData, context: ModelContext) throws -> Tag {
        vaultData.tags.append(data)
        try persist()
        let tag = Tag(name: data.name)
        tag.id = data.id
        context.insert(tag)
        try? context.save()
        return tag
    }

    static func deleteTag(id: UUID, context: ModelContext) throws {
        vaultData.tags.removeAll { $0.id == id }
        try persist()
        if let tag = try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })).first {
            context.delete(tag)
            try? context.save()
        }
    }

    // MARK: - Data Access for Sync

    static var currentVaultData: VaultData { vaultData }
}
