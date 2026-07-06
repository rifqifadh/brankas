import Foundation
import SwiftData

struct VaultSyncService {
    static func syncAll(context: ModelContext) {
        let data = VaultService.currentVaultData

        for item in (try? context.fetch(FetchDescriptor<SecretItem>())) ?? [] { context.delete(item) }
        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] { context.delete(account) }
        for service in (try? context.fetch(FetchDescriptor<Service>())) ?? [] { context.delete(service) }
        for category in (try? context.fetch(FetchDescriptor<Category>())) ?? [] { context.delete(category) }
        for tag in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] { context.delete(tag) }
        try? context.save()

        for tagData in data.tags {
            let tag = Tag(name: tagData.name)
            tag.id = tagData.id
            context.insert(tag)
        }
        try? context.save()

        for catData in data.categories {
            let cat = Category(id: catData.id, name: catData.name, icon: catData.icon, colorHex: catData.colorHex, sortOrder: catData.sortOrder)
            context.insert(cat)
        }
        try? context.save()

        for svcData in data.services {
            let svc = Service(name: svcData.name, url: svcData.url, icon: svcData.icon)
            svc.id = svcData.id
            context.insert(svc)
        }
        try? context.save()

        for itemData in data.items {
            let item = SecretItem(
                id: itemData.id,
                name: itemData.name,
                type: SecretType(rawValue: itemData.typeRawValue) ?? .token,
                categoryId: itemData.categoryId,
                tags: itemData.tagIds.compactMap { tid in
                    try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.id == tid })).first
                },
                notes: itemData.notes,
                url: itemData.url,
                expiresAt: itemData.expiresAt,
                hasTOTP: itemData.hasTOTP,
                isFavorite: itemData.isFavorite
            )
            item.createdAt = itemData.createdAt
            item.updatedAt = itemData.updatedAt
            context.insert(item)
        }
        try? context.save()

        for acctData in data.accounts {
            guard let svc = try? context.fetch(FetchDescriptor<Service>(predicate: #Predicate { $0.id == acctData.serviceId })).first else { continue }
            let account = Account(
                id: acctData.id,
                identifier: acctData.identifier,
                notes: acctData.notes,
                expiresAt: acctData.expiresAt,
                hasTOTP: acctData.hasTOTP,
                isFavorite: acctData.isFavorite,
                service: svc
            )
            account.createdAt = acctData.createdAt
            account.updatedAt = acctData.updatedAt
            context.insert(account)
        }
        try? context.save()
    }
}
