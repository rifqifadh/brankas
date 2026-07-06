import Foundation
import SwiftData

@Model
final class Tag: Identifiable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String

    @Relationship(inverse: \SecretItem.tags) var secrets: [SecretItem]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.secrets = []
    }
}
