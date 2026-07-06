import Foundation

struct SecretItemData: Codable, Identifiable {
    var id: UUID
    var name: String
    var typeRawValue: String
    var categoryId: UUID?
    var tagIds: [UUID]
    var notes: String
    var url: String?
    var expiresAt: Date?
    var hasTOTP: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct AccountData: Codable, Identifiable {
    var id: UUID
    var identifier: String
    var notes: String
    var expiresAt: Date?
    var hasTOTP: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var serviceId: UUID
}

struct ServiceData: Codable, Identifiable {
    var id: UUID
    var name: String
    var url: String?
    var icon: String
}

struct CategoryData: Codable, Identifiable {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var sortOrder: Int
}

struct TagData: Codable, Identifiable {
    var id: UUID
    var name: String
}

struct VaultData: Codable {
    var version: Int
    var createdAt: Date
    var updatedAt: Date
    var secrets: [String: String]
    var items: [SecretItemData]
    var accounts: [AccountData]
    var services: [ServiceData]
    var categories: [CategoryData]
    var tags: [TagData]

    static func empty() -> VaultData {
        VaultData(
            version: 2,
            createdAt: Date(),
            updatedAt: Date(),
            secrets: [:],
            items: [],
            accounts: [],
            services: [],
            categories: [],
            tags: []
        )
    }
}
