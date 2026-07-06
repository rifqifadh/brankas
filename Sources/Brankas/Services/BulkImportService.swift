import Foundation
import SwiftData

struct BulkImportResult {
    let importedAccounts: Int
    let importedItems: Int
    let skipped: Int
    let errors: [String]

    var summary: String {
        var parts: [String] = []
        if importedAccounts > 0 { parts.append("\(importedAccounts) accounts") }
        if importedItems > 0 { parts.append("\(importedItems) items") }
        let main = parts.isEmpty ? "0 items" : parts.joined(separator: ", ")
        if skipped > 0 {
            return "Imported \(main). Skipped \(skipped) duplicate(s)."
        }
        if !errors.isEmpty {
            return "Imported \(main). \(errors.count) error(s): \(errors.first!)"
        }
        return "Imported \(main)."
    }
}

struct BulkImportEntry {
    var serviceName: String
    var serviceUrl: String?
    var username: String
    var password: String
    var notes: String
}

struct BulkImportItemEntry {
    var name: String
    var typeRawValue: String
    var value: String
    var url: String?
    var notes: String
}

struct BulkImportService {
    static func parseAndImport(url: URL, context: ModelContext) -> BulkImportResult {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv":
            return importCSV(url: url, context: context)
        case "json":
            return importJSON(url: url, context: context)
        default:
            return BulkImportResult(importedAccounts: 0, importedItems: 0, skipped: 0, errors: ["Unsupported file format: .\(ext). Use .csv or .json"])
        }
    }

    // MARK: - CSV

    private static func importCSV(url: URL, context: ModelContext) -> BulkImportResult {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return BulkImportResult(importedAccounts: 0, importedItems: 0, skipped: 0, errors: ["Failed to read file"])
        }

        let rows = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard rows.count >= 2 else {
            return BulkImportResult(importedAccounts: 0, importedItems: 0, skipped: 0, errors: ["File must have a header row and at least one data row"])
        }

        let headers = parseCSVRow(rows[0]).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !headers.isEmpty else {
            return BulkImportResult(importedAccounts: 0, importedItems: 0, skipped: 0, errors: ["Invalid header row"])
        }

        var imported = 0
        var skipped = 0
        var errors: [String] = []

        for i in 1..<rows.count {
            let cols = parseCSVRow(rows[i])
            let entry = mapColumns(cols, headers: headers)

            guard !entry.username.isEmpty && !entry.password.isEmpty else {
                skipped += 1
                continue
            }

            do {
                try importAccount(entry, context: context)
                imported += 1
            } catch {
                errors.append("Row \(i+1): \(error.localizedDescription)")
            }
        }

        return BulkImportResult(importedAccounts: imported, importedItems: 0, skipped: skipped, errors: errors)
    }

    private static func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    private static func mapColumns(_ cols: [String], headers: [String]) -> BulkImportEntry {
        var entry = BulkImportEntry(serviceName: "", username: "", password: "", notes: "")

        for (i, header) in headers.enumerated() {
            guard i < cols.count else { continue }
            let val = cols[i].trimmingCharacters(in: .whitespaces)
            switch header {
            case "service", "service name": entry.serviceName = val
            case "url", "website": entry.serviceUrl = val.isEmpty ? nil : val
            case "username", "email", "user", "account": entry.username = val
            case "password", "pass", "secret": entry.password = val
            case "notes", "note", "description": entry.notes = val
            default: break
            }
        }

        return entry
    }

    // MARK: - JSON

    private static func importJSON(url: URL, context: ModelContext) -> BulkImportResult {
        guard let data = try? Data(contentsOf: url) else {
            return BulkImportResult(importedAccounts: 0, importedItems: 0, skipped: 0, errors: ["Failed to read file"])
        }

        struct BulkJSON: Codable {
            var accounts: [BulkJSONAccount]?
            var items: [BulkJSONItem]?
        }
        struct BulkJSONAccount: Codable {
            var service: String
            var url: String?
            var username: String
            var password: String
            var notes: String?
        }
        struct BulkJSONItem: Codable {
            var name: String
            var type: String?
            var value: String
            var url: String?
            var notes: String?
        }

        guard let payload = try? JSONDecoder().decode(BulkJSON.self, from: data) else {
            return BulkImportResult(importedAccounts: 0, importedItems: 0, skipped: 0, errors: ["Invalid JSON format"])
        }

        var importedAccounts = 0
        var importedItems = 0
        var skipped = 0
        var errors: [String] = []

        for acct in payload.accounts ?? [] {
            guard !acct.username.isEmpty && !acct.password.isEmpty else {
                skipped += 1
                continue
            }
            let entry = BulkImportEntry(
                serviceName: acct.service,
                serviceUrl: acct.url,
                username: acct.username,
                password: acct.password,
                notes: acct.notes ?? ""
            )
            do {
                try importAccount(entry, context: context)
                importedAccounts += 1
            } catch {
                errors.append("Account '\(acct.username)': \(error.localizedDescription)")
            }
        }

        for item in payload.items ?? [] {
            guard !item.name.isEmpty && !item.value.isEmpty else {
                skipped += 1
                continue
            }
            let itemEntry = BulkImportItemEntry(
                name: item.name,
                typeRawValue: item.type ?? "password",
                value: item.value,
                url: item.url,
                notes: item.notes ?? ""
            )
            do {
                try importItem(itemEntry, context: context)
                importedItems += 1
            } catch {
                errors.append("Item '\(item.name)': \(error.localizedDescription)")
            }
        }

        return BulkImportResult(importedAccounts: importedAccounts, importedItems: importedItems, skipped: skipped, errors: errors)
    }

    // MARK: - Import Logic

    private static func importAccount(_ entry: BulkImportEntry, context: ModelContext) throws {
        let svcName = entry.serviceName.trimmingCharacters(in: .whitespaces)
        guard !svcName.isEmpty else { throw BulkError.missingServiceName }

        let svcId = findOrCreateService(name: svcName, url: entry.serviceUrl, context: context)

        let existingAccounts = VaultService.currentVaultData.accounts.filter { $0.serviceId == svcId && $0.identifier == entry.username }
        guard existingAccounts.isEmpty else {
            throw BulkError.duplicate("Account '\(entry.username)' already exists for service '\(svcName)'")
        }

        let id = UUID()
        let data = AccountData(
            id: id,
            identifier: entry.username,
            notes: entry.notes,
            expiresAt: nil,
            hasTOTP: false,
            isFavorite: false,
            createdAt: Date(),
            updatedAt: Date(),
            serviceId: svcId
        )
        try VaultService.createAccount(data: data, secret: entry.password, context: context)
    }

    private static func importItem(_ entry: BulkImportItemEntry, context: ModelContext) throws {
        let id = UUID()
        let data = SecretItemData(
            id: id,
            name: entry.name,
            typeRawValue: entry.typeRawValue,
            categoryId: nil,
            tagIds: [],
            notes: entry.notes,
            url: entry.url,
            expiresAt: nil,
            hasTOTP: false,
            isFavorite: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        do {
            try VaultService.createItem(data: data, secret: entry.value, context: context)
        } catch {
            throw BulkError.importFailed("Failed to import item '\(entry.name)': \(error.localizedDescription)")
        }
    }

    private static func findOrCreateService(name: String, url: String?, context: ModelContext) -> UUID {
        let existing = VaultService.currentVaultData.services.first { $0.name.lowercased() == name.lowercased() }
        if let existing { return existing.id }

        let id = UUID()
        let data = ServiceData(id: id, name: name, url: url, icon: "globe")
        try? VaultService.createService(data: data, context: context)
        return id
    }
}

enum BulkError: LocalizedError {
    case missingServiceName
    case duplicate(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingServiceName: "Service name is required"
        case .duplicate(let msg): msg
        case .importFailed(let msg): msg
        }
    }
}
