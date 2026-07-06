import Foundation
import SwiftData

@Model
final class Account: Identifiable {
    @Attribute(.unique) var id: UUID
    var identifier: String
    var notes: String
    var expiresAt: Date?
    var hasTOTP: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var service: Service

    init(
        id: UUID = UUID(),
        identifier: String,
        notes: String = "",
        expiresAt: Date? = nil,
        hasTOTP: Bool = false,
        isFavorite: Bool = false,
        service: Service
    ) {
        self.id = id
        self.identifier = identifier
        self.notes = notes
        self.expiresAt = expiresAt
        self.hasTOTP = hasTOTP
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
        self.service = service
    }
}
