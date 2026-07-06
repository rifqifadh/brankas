import Foundation

struct VaultBackup: Identifiable {
    let id: UUID
    let url: URL
    let date: Date
    let size: Int

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct VaultBackupService {
    private static var backupDir: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Brankas Backups", isDirectory: true)
    }

    private static var lastBackupKey: String {
        #if DEBUG
        "lastVaultBackupDate-debug"
        #else
        "lastVaultBackupDate"
        #endif
    }

    static func createBackup(force: Bool = false) {
        let vaultURL = VaultService.storeURL
        guard FileManager.default.fileExists(atPath: vaultURL.path) else { return }

        if !force {
            let today = Calendar.current.startOfDay(for: Date())
            let lastBackup = UserDefaults.standard.object(forKey: lastBackupKey) as? Date ?? .distantPast
            guard Calendar.current.startOfDay(for: lastBackup) != today else { return }
        }

        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupURL = backupDir.appendingPathComponent("brankas-vault-\(timestamp).enc")

        try? FileManager.default.copyItem(at: vaultURL, to: backupURL)

        // Also backup salt file (PBKDF2 salt, required for decryption)
        let saltURL = VaultService.storeURL.deletingPathExtension().appendingPathExtension("salt")
        if FileManager.default.fileExists(atPath: saltURL.path) {
            let saltBackupURL = backupDir.appendingPathComponent("brankas-vault-\(timestamp).salt")
            try? FileManager.default.copyItem(at: saltURL, to: saltBackupURL)
        }

        UserDefaults.standard.set(Date(), forKey: lastBackupKey)

        pruneOldBackups()
    }

    static func listBackups() -> [VaultBackup] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return []
        }

        return files
            .filter { $0.lastPathComponent.hasPrefix("brankas-vault-") && $0.pathExtension == "enc" }
            .compactMap { url in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let date = attrs[.modificationDate] as? Date,
                      let size = attrs[.size] as? Int else { return nil }
                return VaultBackup(id: UUID(), url: url, date: date, size: size)
            }
            .sorted { $0.date > $1.date }
    }

    static func restore(from backup: VaultBackup) throws {
        let vaultURL = VaultService.storeURL
        try FileManager.default.removeItem(at: vaultURL)
        try FileManager.default.copyItem(at: backup.url, to: vaultURL)

        // Restore salt file if it exists alongside backup
        let saltBackupURL = backup.url.deletingPathExtension().appendingPathExtension("salt")
        let saltURL = VaultService.storeURL.deletingPathExtension().appendingPathExtension("salt")
        if FileManager.default.fileExists(atPath: saltBackupURL.path) {
            try? FileManager.default.removeItem(at: saltURL)
            try? FileManager.default.copyItem(at: saltBackupURL, to: saltURL)
        }
    }

    private static func pruneOldBackups() {
        let backups = listBackups()
        guard backups.count > 30 else { return }
        for backup in backups.dropFirst(30) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }
}
