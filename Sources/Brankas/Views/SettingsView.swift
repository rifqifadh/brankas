import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalAuthentication

struct SettingsView: View {
    @Environment(ClipboardService.self) private var clipboardService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("biometricUnlock") private var biometricUnlock = false
    @Query private var allSecrets: [SecretItem]
    @Query(sort: \Account.updatedAt, order: .reverse) private var allAccounts: [Account]

    @State private var exportPassword = ""
    @State private var importPassword = ""
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportData: Data?
    @State private var showingUnencryptedExporter = false
    @State private var unencryptedExportData: Data?
    @State private var showingUnencryptedWarning = false
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var showingBackupPicker = false
    @State private var showingBulkImporter = false
    @State private var bulkImportResult = ""
    @State private var showingResetConfirm = false
    @State private var resetConfirmText = ""

    private let exportService = ExportImportService()
    private let clearDurations: [TimeInterval] = [10, 15, 30, 45, 60]

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            exportTab
                .tabItem {
                    Label("Export/Import", systemImage: "arrow.up.doc")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .scenePadding()
        .frame(width: 450, height: 300)
        .alert("Notice", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage ?? "")
        }
        .fileExporter(isPresented: $showingExporter, item: exportData, contentTypes: [UTType.json], defaultFilename: "brankas-export") { result in
            switch result {
            case .success: alertMessage = "Export successful"
            case .failure(let error): alertMessage = "Export failed: \(error.localizedDescription)"
            }
            if alertMessage != nil { showingAlert = true }
        }
        .fileExporter(isPresented: $showingUnencryptedExporter, item: unencryptedExportData, contentTypes: [UTType.json], defaultFilename: "brankas-export-plaintext") { result in
            switch result {
            case .success: alertMessage = "Unencrypted export saved"
            case .failure(let error): alertMessage = "Export failed: \(error.localizedDescription)"
            }
            if alertMessage != nil { showingAlert = true }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fileImporter(isPresented: $showingBulkImporter, allowedContentTypes: [.commaSeparatedText, .json]) { result in
            handleBulkImport(result)
        }
    }

    private var generalTab: some View {
        Form {
            Section("Clipboard") {
                Picker("Auto-clear after", selection: Bindable(clipboardService).autoClearDuration) {
                    ForEach(clearDurations, id: \.self) { duration in
                        Text("\(Int(duration)) seconds").tag(duration)
                    }
                }
            }

            Section("Security") {
                Toggle("Unlock with Touch ID", isOn: $biometricUnlock)
                    .disabled(!LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))
                    .onChange(of: biometricUnlock) { _, newValue in
                        if newValue {
                            savePasswordToKeychain()
                        } else {
                            KeychainService.deleteVaultPassword()
                        }
                    }
            }

            Section("Database") {
                Button("Reset All Data", role: .destructive) {
                    showingResetConfirm = true
                }
                .alert("Reset All Data?", isPresented: $showingResetConfirm) {
                    TextField("Type \"reset\" to confirm", text: $resetConfirmText)
                    Button("Cancel", role: .cancel) {
                        resetConfirmText = ""
                    }
                    Button("Reset", role: .destructive) {
                        guard resetConfirmText == "reset" else { return }
                        resetAllData()
                        resetConfirmText = ""
                    }
                    .disabled(resetConfirmText != "reset")
                } message: {
                    Text("This will permanently delete all secrets, accounts, services, categories, tags, and the vault file. This action cannot be undone.")
                }
            }

            Section("Backups") {
                Button("Create Backup Now", systemImage: "clock.arrow.circlepath") {
                    VaultBackupService.createBackup(force: true)
                    alertMessage = "Backup created successfully"
                    showingAlert = true
                }

                Button("View Backups") {
                    showingBackupPicker = true
                }
                .sheet(isPresented: $showingBackupPicker) {
                    backupListView
                }
            }
        }
        .formStyle(.grouped)
    }

    private var exportTab: some View {
        Form {
            Section("Password-Protected Export") {
                SecureField("Export password", text: $exportPassword)

                Button("Export All Secrets") {
                    performExport()
                }
                .disabled(exportPassword.isEmpty || allSecrets.isEmpty)
            }

            Section("Unencrypted Export") {
                Button("Export Unencrypted (JSON)", role: .destructive) {
                    showingUnencryptedWarning = true
                }
                .disabled(allSecrets.isEmpty)
                .alert("Export Unencrypted?", isPresented: $showingUnencryptedWarning) {
                    Button("Cancel", role: .cancel) { }
                    Button("Export", role: .destructive) {
                        performUnencryptedExport()
                    }
                } message: {
                    Text("The exported JSON file will contain ALL secrets in plaintext. Anyone who has access to the file can read your passwords. Only use this for manual migration to other tools.")
                }
            }

            Section("Import") {
                SecureField("Import password", text: $importPassword)

                Button("Import from File") {
                    showingImporter = true
                }
                .disabled(importPassword.isEmpty)
            }

            Section("Bulk Import (CSV / JSON)") {
                DisclosureGroup("Show expected format") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CSV").font(.caption).fontWeight(.semibold)
                        Text("service,url,username,password,notes\nGitHub,https://github.com,user@x.com,mypass,notes")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Divider()

                        Text("JSON").font(.caption).fontWeight(.semibold)
                        Text("""
                        {
                          "accounts": [
                            {
                              "service": "GitHub",
                              "url": "https://github.com",
                              "username": "user@x.com",
                              "password": "mypass"
                            }
                          ],
                          "items": [
                            {
                              "name": "API Key",
                              "type": "token",
                              "value": "sk-xxx"
                            }
                          ]
                        }
                        """)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                }

                Button("Import Accounts from File...") {
                    showingBulkImporter = true
                }

                if !bulkImportResult.isEmpty {
                    Text(bulkImportResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
      ScrollView {
        VStack(spacing: 16) {
          Image(systemName: "key.fill")
            .font(.system(size: 40))
            .foregroundStyle(.tint)
          
          Text("Brankas")
            .font(.title2)
            .fontWeight(.semibold)
          
          Text("Version 1.0")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          
          Divider()
          
          VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Author", value: "Rifqi Fadhlillah")
            LabeledContent("License", value: "MIT")
            LabeledContent("macOS", value: "14.0+")
          }
          .font(.callout)
          .frame(maxWidth: 260)
          
          Divider()
          
          Button("View on GitHub", systemImage: "arrow.up.forward.app") {
            if let url = URL(string: "https://github.com/rifqifadhlillah/brankas") {
              NSWorkspace.shared.open(url)
            }
          }
          .buttonStyle(.plain)
          .font(.callout)
          
          Text("No cloud, no telemetry, no network access.")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backupListView: some View {
        BackupListView(
            onRestore: { backup in
                do {
                    try VaultBackupService.restore(from: backup)
                    alertMessage = "Backup restored. Please restart Brankas for the changes to take effect."
                } catch {
                    alertMessage = "Restore failed: \(error.localizedDescription)"
                }
                showingAlert = true
                showingBackupPicker = false
            },
            onDismiss: { showingBackupPicker = false }
        )
    }

    private func buildExportItems() -> [ExportEntry] {
        allSecrets.compactMap { item in
            guard let value = try? VaultService.read(for: item.id.uuidString) else { return nil }
            return ExportEntry(
                id: item.id,
                name: item.name,
                type: item.typeRawValue,
                value: value,
                categoryId: item.categoryId,
                tags: item.tags.map(\.name),
                notes: item.notes,
                url: item.url
            )
        }
    }

    private func buildExportAccounts() -> [AccountExportEntry] {
        allAccounts.compactMap { account in
            guard let value = try? VaultService.read(for: account.id.uuidString) else { return nil }
            let totpSecret = account.hasTOTP ? (try? VaultService.read(for: "totp-\(account.id.uuidString)")) : nil
            return AccountExportEntry(
                id: account.id,
                serviceName: account.service.name,
                serviceUrl: account.service.url,
                serviceIcon: account.service.icon,
                identifier: account.identifier,
                value: value,
                notes: account.notes,
                expiresAt: account.expiresAt,
                hasTOTP: account.hasTOTP,
                totpSecret: totpSecret,
                isFavorite: account.isFavorite
            )
        }
    }

    private func performExport() {
        let items = buildExportItems()
        let accounts = buildExportAccounts()

        do {
            exportData = try exportService.encryptExport(items: items, accounts: accounts, password: exportPassword)
            showingExporter = true
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func performUnencryptedExport() {
        let items = buildExportItems()
        let accounts = buildExportAccounts()

        do {
            unencryptedExportData = try exportService.unencryptedExport(items: items, accounts: accounts)
            showingUnencryptedExporter = true
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Permission denied"
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let container = try exportService.decryptExport(data, password: importPassword)
                var importedItems = 0
                var importedAccounts = 0
                try importEntries(container.items, &importedItems)
                try importAccountEntries(container.accounts, &importedAccounts)
                let total = importedItems + importedAccounts
                let parts = [
                    importedItems > 0 ? "\(importedItems) secrets" : "",
                    importedAccounts > 0 ? "\(importedAccounts) accounts" : "",
                ].filter { !$0.isEmpty }.joined(separator: ", ")
                alertMessage = "Imported \(parts)"
            } catch {
                alertMessage = "Import failed: \(error.localizedDescription)"
            }
            showingAlert = true

        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func importEntries(_ entries: [ExportEntry], _ count: inout Int) throws {
        for entry in entries {
            let tagIds: [UUID] = entry.tags.map { name in
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if let existing = try? modelContext.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.name == trimmed })).first {
                    return existing.id
                }
                let data = TagData(id: UUID(), name: trimmed)
                let tag = (try? VaultService.createTag(data: data, context: modelContext)) ?? Tag(name: trimmed)
                return tag.id
            }
            let data = SecretItemData(
                id: entry.id,
                name: entry.name,
                typeRawValue: entry.type,
                categoryId: entry.categoryId,
                tagIds: tagIds,
                notes: entry.notes,
                url: entry.url,
                expiresAt: nil,
                hasTOTP: false,
                isFavorite: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            try VaultService.createItem(data: data, secret: entry.value, context: modelContext)
            count += 1
        }
    }

    private func importAccountEntries(_ entries: [AccountExportEntry], _ count: inout Int) throws {
        for entry in entries {
            let svcId: UUID
            if let existing = VaultService.currentVaultData.services.first(where: { $0.name.lowercased() == entry.serviceName.lowercased() }) {
                svcId = existing.id
            } else {
                svcId = UUID()
                let svcData = ServiceData(id: svcId, name: entry.serviceName, url: entry.serviceUrl, icon: entry.serviceIcon)
                try VaultService.createService(data: svcData, context: modelContext)
            }

            let data = AccountData(
                id: entry.id,
                identifier: entry.identifier,
                notes: entry.notes,
                expiresAt: entry.expiresAt,
                hasTOTP: entry.hasTOTP || entry.totpSecret != nil,
                isFavorite: entry.isFavorite,
                createdAt: Date(),
                updatedAt: Date(),
                serviceId: svcId
            )
            try VaultService.createAccount(data: data, secret: entry.value, context: modelContext)

            if let totp = entry.totpSecret, !totp.isEmpty {
                try VaultService.save(secret: totp, for: "totp-\(entry.id.uuidString)")
            }
            count += 1
        }
    }

    private func handleBulkImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Permission denied"
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let importResult = BulkImportService.parseAndImport(url: url, context: modelContext)
            bulkImportResult = importResult.summary
            alertMessage = importResult.summary
            showingAlert = true

        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func savePasswordToKeychain() {
        let pw = VaultService.password
        guard !pw.isEmpty else {
            biometricUnlock = false
            alertMessage = "Vault not loaded. Please restart and unlock first."
            showingAlert = true
            return
        }
        do {
            try KeychainService.saveVaultPassword(pw)
        } catch {
            biometricUnlock = false
            alertMessage = "Failed to enable biometric unlock: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func resetAllData() {
        VaultService.reset(context: modelContext)
        alertMessage = "All data has been reset"
        showingAlert = true
    }
}

// MARK: - Backup List Sheet

private struct BackupListView: View {
    let onRestore: (VaultBackup) -> Void
    let onDismiss: () -> Void

    @State private var backups: [VaultBackup] = []
    @State private var selectedBackup: VaultBackup?
    @State private var showingRestoreConfirm = false

    var body: some View {
        NavigationStack {
            if backups.isEmpty {
                ContentUnavailableView(
                    "No Backups",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("A backup is created automatically once per day after unlocking.")
                )
            } else {
                List(backups) { backup in
                    Button {
                        selectedBackup = backup
                        showingRestoreConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.formattedDate)
                                    .font(.body)
                                Text(backup.formattedSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button("Show in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([backup.url])
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Show in Finder")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            backups = VaultBackupService.listBackups()
        }
        .navigationTitle("Restore Backup")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onDismiss)
            }
        }
        .alert("Restore Backup?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup { onRestore(backup) }
            }
        } message: {
            Text("This will replace the entire vault with the backup from \(selectedBackup?.formattedDate ?? ""). All current secrets, accounts, services, and metadata will be replaced. A restart is required.")
        }
        .frame(width: 360, height: 300)
    }
}

#Preview {
    SettingsView()
        .environment(ClipboardService())
        .modelContainer(for: [SecretItem.self], inMemory: true)
}
