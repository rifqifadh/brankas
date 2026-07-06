import Foundation
import SwiftData

@Model
final class Service: Identifiable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var url: String?
    var icon: String

    var accounts: [Account]

    init(name: String, url: String? = nil, icon: String = "globe") {
        self.id = UUID()
        self.name = name
        self.url = url
        self.icon = icon
        self.accounts = []
    }
}
