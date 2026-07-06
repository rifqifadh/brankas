import Foundation
import SwiftData

@Model
final class SecretItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRawValue: String
    var categoryId: UUID?
    var tags: [Tag]
    var notes: String
    var url: String?
    var expiresAt: Date?
    var hasTOTP: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    var type: SecretType {
        get { SecretType(rawValue: typeRawValue) ?? .token }
        set { typeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: SecretType = .token,
        categoryId: UUID? = nil,
        tags: [Tag] = [],
        notes: String = "",
        url: String? = nil,
        expiresAt: Date? = nil,
        hasTOTP: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.typeRawValue = type.rawValue
        self.categoryId = categoryId
        self.tags = tags
        self.notes = notes
        self.url = url
        self.expiresAt = expiresAt
        self.hasTOTP = hasTOTP
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
