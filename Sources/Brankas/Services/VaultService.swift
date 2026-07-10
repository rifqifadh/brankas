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

    // MARK: - Seed Data

    #if DEBUG
    static func seed() {
        vaultData = .empty()
        vaultData.createdAt = Date()
        let now = Date()

        // Categories
        let catWork = CategoryData(id: UUID(), name: "Work", icon: "briefcase", colorHex: "#007AFF", sortOrder: 0)
        let catPersonal = CategoryData(id: UUID(), name: "Personal", icon: "person", colorHex: "#34C759", sortOrder: 1)
        let catFinance = CategoryData(id: UUID(), name: "Finance", icon: "dollarsign.circle", colorHex: "#FF9500", sortOrder: 2)
        let catDev = CategoryData(id: UUID(), name: "Development", icon: "hammer", colorHex: "#AF52DE", sortOrder: 3)
        vaultData.categories = [catWork, catPersonal, catFinance, catDev]

        // Tags
        let tagImportant = TagData(id: UUID(), name: "important")
        let tagWork = TagData(id: UUID(), name: "work")
        let tagPersonal = TagData(id: UUID(), name: "personal")
        let tag2FA = TagData(id: UUID(), name: "2FA")
        let tagLegacy = TagData(id: UUID(), name: "legacy")
        let tagCrypto = TagData(id: UUID(), name: "crypto")
        vaultData.tags = [tagImportant, tagWork, tagPersonal, tag2FA, tagLegacy, tagCrypto]

        // Services
        let svcGoogle = ServiceData(id: UUID(), name: "Google", url: "https://google.com", icon: "mail")
        let svcGithub = ServiceData(id: UUID(), name: "GitHub", url: "https://github.com", icon: "chevron.left.forwardslash.chevron.right")
        let svcAWS = ServiceData(id: UUID(), name: "AWS", url: "https://aws.amazon.com", icon: "cloud")
        let svcNetflix = ServiceData(id: UUID(), name: "Netflix", url: "https://netflix.com", icon: "tv")
        let svcSlack = ServiceData(id: UUID(), name: "Slack", url: "https://slack.com", icon: "message")
        let svcApple = ServiceData(id: UUID(), name: "Apple ID", url: "https://appleid.apple.com", icon: "apple.logo")
        vaultData.services = [svcGoogle, svcGithub, svcAWS, svcNetflix, svcSlack, svcApple]

        // Accounts
        let acctGmail = AccountData(id: UUID(), identifier: "rifqi.fadhlillah@gmail.com", notes: "Primary Gmail", expiresAt: nil, hasTOTP: true, isFavorite: true, createdAt: now, updatedAt: now, serviceId: svcGoogle.id)
        let acctGoogleAdmin = AccountData(id: UUID(), identifier: "admin@rifqi.dev", notes: "Google Workspace admin", expiresAt: Calendar.current.date(byAdding: .day, value: 45, to: now), hasTOTP: true, isFavorite: true, createdAt: now, updatedAt: now, serviceId: svcGoogle.id)
        let acctGithub = AccountData(id: UUID(), identifier: "rifqifadhlillah", notes: "Personal GitHub account", expiresAt: nil, hasTOTP: true, isFavorite: false, createdAt: now, updatedAt: now, serviceId: svcGithub.id)
        let acctGithubOrg = AccountData(id: UUID(), identifier: "rifqi@company.io", notes: "Work GitHub Enterprise", expiresAt: Calendar.current.date(byAdding: .day, value: 90, to: now), hasTOTP: true, isFavorite: false, createdAt: now, updatedAt: now, serviceId: svcGithub.id)
        let acctAWSRoot = AccountData(id: UUID(), identifier: "rifqi@aws.rifqi.dev", notes: "AWS root account. Keep safe!", expiresAt: nil, hasTOTP: true, isFavorite: true, createdAt: now, updatedAt: now, serviceId: svcAWS.id)
        let acctAWSDev = AccountData(id: UUID(), identifier: "dev-admin", notes: "Dev environment admin", expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: now), hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now, serviceId: svcAWS.id)
        let acctNetflix = AccountData(id: UUID(), identifier: "rifqi.fadhlillah@gmail.com", notes: "Shared family plan", expiresAt: Calendar.current.date(byAdding: .month, value: 2, to: now), hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now, serviceId: svcNetflix.id)
        let acctSlack = AccountData(id: UUID(), identifier: "rifqi@company.io", notes: "Company Slack (all channels)", expiresAt: nil, hasTOTP: true, isFavorite: false, createdAt: now, updatedAt: now, serviceId: svcSlack.id)
        let acctApple = AccountData(id: UUID(), identifier: "rifqi.fadhlillah@icloud.com", notes: "iCloud & App Store purchases", expiresAt: nil, hasTOTP: true, isFavorite: true, createdAt: now, updatedAt: now, serviceId: svcApple.id)
        let acctAppleDev = AccountData(id: UUID(), identifier: "rifqi.fadhlillah@icloud.com", notes: "Apple Developer Program ($99/yr)", expiresAt: Calendar.current.date(byAdding: .day, value: 120, to: now), hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now, serviceId: svcApple.id)
        vaultData.accounts = [acctGmail, acctGoogleAdmin, acctGithub, acctGithubOrg, acctAWSRoot, acctAWSDev, acctNetflix, acctSlack, acctApple, acctAppleDev]

        // Passwords (stored in secrets dict)
        vaultData.secrets[acctGmail.id.uuidString] = "secure-gmail-pw-2026!"
        vaultData.secrets[acctGoogleAdmin.id.uuidString] = "ws-admin@Rifqi2026!"
        vaultData.secrets[acctGithub.id.uuidString] = "gh_pat_rifqi_abc123def456"
        vaultData.secrets[acctGithubOrg.id.uuidString] = "gh-enterprise-token-xyz789"
        vaultData.secrets[acctAWSRoot.id.uuidString] = "AWS!Root@2026#SecretKey"
        vaultData.secrets[acctAWSDev.id.uuidString] = "dev-env-pass-123"
        vaultData.secrets[acctNetflix.id.uuidString] = "netflix-family-2026!"
        vaultData.secrets[acctSlack.id.uuidString] = "slack-token-xoxb-123456789"
        vaultData.secrets[acctApple.id.uuidString] = "ic1Oud-St0r3-P@ss!"
        vaultData.secrets[acctAppleDev.id.uuidString] = "dev-program-2026!"

        // TOTP secrets
        vaultData.secrets["totp-\(acctGmail.id.uuidString)"] = "otpauth://totp/Google:rifqi.fadhlillah@gmail.com?secret=JBSWY3DPEHPK3PXP&issuer=Google"
        vaultData.secrets["totp-\(acctGoogleAdmin.id.uuidString)"] = "otpauth://totp/Google:admin@rifqi.dev?secret=K5XW4ZDPF5LVKVKV&issuer=Google"
        vaultData.secrets["totp-\(acctGithub.id.uuidString)"] = "otpauth://totp/GitHub:rifqifadhlillah?secret=MZXW6YTBOJXW64QQ&issuer=GitHub"
        vaultData.secrets["totp-\(acctGithubOrg.id.uuidString)"] = "otpauth://totp/GitHub:rifqi@company.io?secret=GNRW4ZBON5WU2YRR&issuer=GitHub"
        vaultData.secrets["totp-\(acctAWSRoot.id.uuidString)"] = "otpauth://totp/AWS:rifqi@aws.rifqi.dev?secret=KN2XEZDPJR2XQ3YQ&issuer=AWS"
        vaultData.secrets["totp-\(acctSlack.id.uuidString)"] = "otpauth://totp/Slack:rifqi@company.io?secret=FZ2D4B3VMF2W4Z2U&issuer=Slack"
        vaultData.secrets["totp-\(acctApple.id.uuidString)"] = "otpauth://totp/Apple:rifqi@icloud.com?secret=LZK4WDRUK5MV6SSU&issuer=Apple"

        // Secret Items (tokens/passwords/keys stored in vault)
        let item1 = SecretItemData(id: UUID(), name: "GitHub Personal Access Token", typeRawValue: SecretType.token.rawValue, categoryId: catDev.id, tagIds: [tagImportant.id, tagWork.id, tagPersonal.id], notes: "Full repo access. Rotate every 90 days.", url: "https://github.com/settings/tokens", expiresAt: Calendar.current.date(byAdding: .day, value: 60, to: now), hasTOTP: false, isFavorite: true, createdAt: now, updatedAt: now)
        let item2 = SecretItemData(id: UUID(), name: "WiFi Router Admin", typeRawValue: SecretType.password.rawValue, categoryId: catPersonal.id, tagIds: [tagPersonal.id], notes: "TP-Link Archer AX73 admin password", url: "http://192.168.1.1", expiresAt: nil, hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now)
        let item3 = SecretItemData(id: UUID(), name: "Production SSH Key", typeRawValue: SecretType.sshKey.rawValue, categoryId: catDev.id, tagIds: [tagImportant.id, tagWork.id], notes: "Deploy key for production servers. Do NOT share.", url: nil, expiresAt: Calendar.current.date(byAdding: .month, value: 6, to: now), hasTOTP: false, isFavorite: true, createdAt: now, updatedAt: now)
        let item4 = SecretItemData(id: UUID(), name: "Let's Encrypt SSL Cert", typeRawValue: SecretType.certificate.rawValue, categoryId: catDev.id, tagIds: [tagWork.id], notes: "Wildcard cert for *.rifqi.dev. Auto-renew via certbot.", url: "https://rifqi.dev", expiresAt: Calendar.current.date(byAdding: .day, value: 25, to: now), hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now)
        let item5 = SecretItemData(id: UUID(), name: "Bank Transfer PIN", typeRawValue: SecretType.note.rawValue, categoryId: catFinance.id, tagIds: [tagImportant.id, tagPersonal.id], notes: "BCA mobile PIN reminder: mother's birth year + postal code", url: nil, expiresAt: nil, hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now)
        let item6 = SecretItemData(id: UUID(), name: "Twitter/X API Bearer Token", typeRawValue: SecretType.token.rawValue, categoryId: catWork.id, tagIds: [tagWork.id], notes: "Used by analytics pipeline. Rate limit: 500 req/15min.", url: "https://developer.twitter.com", expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: now), hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now)
        let item7 = SecretItemData(id: UUID(), name: "Recovery Codes Backup", typeRawValue: SecretType.note.rawValue, categoryId: catPersonal.id, tagIds: [tagImportant.id, tagPersonal.id], notes: "Google/GitHub/AWS recovery codes — stored offline too", url: nil, expiresAt: nil, hasTOTP: false, isFavorite: true, createdAt: now, updatedAt: now)
        let item8 = SecretItemData(id: UUID(), name: "VPN Certificate", typeRawValue: SecretType.certificate.rawValue, categoryId: catWork.id, tagIds: [tagWork.id], notes: "WireGuard client cert for remote access", url: nil, expiresAt: Calendar.current.date(byAdding: .day, value: 200, to: now), hasTOTP: false, isFavorite: false, createdAt: now, updatedAt: now)
        vaultData.items = [item1, item2, item3, item4, item5, item6, item7, item8]

        // Secrets for items
        vaultData.secrets[item1.id.uuidString] = "ghp_abc123def456ghi789jkl012mno345pqr678stu"
        vaultData.secrets[item2.id.uuidString] = "admin:TPLink@2026!"
        vaultData.secrets[item3.id.uuidString] = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn\nNhAAAAAwEAAQAAAQEA8v7jQp2L3gX5f6H8zJ1kR2v3cV4b5n6m7k8l9K0j1h2f3g4h5j6\n-----END OPENSSH PRIVATE KEY-----"
        vaultData.secrets[item4.id.uuidString] = "-----BEGIN CERTIFICATE-----\nMIIFazCCA1OgAwIBAgISAx9uJ3V0bHj4x8u2c5f6g7h8\n-----END CERTIFICATE-----"
        vaultData.secrets[item5.id.uuidString] = "PIN: 270890 (mom's birth year) + 55123 (postal code)"
        vaultData.secrets[item6.id.uuidString] = "AAAAAAAAAAAAAAAAAAAAAABC123def456ghi789jkl0"
        vaultData.secrets[item7.id.uuidString] = "Google: xxxx-xxxx-xxxx-xxxx\nGitHub: 1234-5678-9012-3456\nAWS: abcd-efgh-ijkl-mnop"
        vaultData.secrets[item8.id.uuidString] = "-----BEGIN CERTIFICATE-----\nMIIB9TCCAV6gAwIBAgITMwA7gK6V5b3J3m4z\n-----END CERTIFICATE-----"

        try? persist()
    }
    #endif

    // MARK: - Data Access for Sync

    static var currentVaultData: VaultData { vaultData }
}
