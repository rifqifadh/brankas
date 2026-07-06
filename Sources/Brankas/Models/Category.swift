import Foundation
import SwiftData

@Model
final class Category: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder",
        colorHex: String = "#007AFF",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
}
