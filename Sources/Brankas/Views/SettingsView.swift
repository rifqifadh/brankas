import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalAuthentication

struct SettingsView: View {
    @Environment(ClipboardService.self) private var clipboardService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("biometricUnlock") private var biometricUnlock = false
    @Query private var allSecrets: [SecretItem]

    @State private var exportPassword = ""
    @State private var importPassword = ""
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportData: Data?
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var showingBackupPicker = false
    @State private var backups: [VaultBackup] = []
    @State private var selectedBackup: VaultBackup?
    @State private var showingRestoreConfirm = false
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
                    backups = VaultBackupService.listBackups()
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
        .navigationTitle("Restore Backup")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showingBackupPicker = false }
            }
        }
        .alert("Restore Backup?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                performRestore()
            }
        } message: {
            Text("This will replace the entire vault with the backup from \(selectedBackup?.formattedDate ?? ""). All current secrets, accounts, services, and metadata will be replaced. A restart is required.")
        }
        .frame(width: 360, height: 300)
    }

    private func performRestore() {
        guard let backup = selectedBackup else { return }
        do {
            try VaultBackupService.restore(from: backup)
            alertMessage = "Backup restored. Please restart Brankas for the changes to take effect."
        } catch {
            alertMessage = "Restore failed: \(error.localizedDescription)"
        }
        showingAlert = true
        showingBackupPicker = false
    }

    private func performExport() {
        let entries: [ExportEntry] = allSecrets.compactMap { item in
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

        do {
            exportData = try exportService.encryptExport(entries, password: exportPassword)
            showingExporter = true
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
                let entries = try exportService.decryptExport(data, password: importPassword)
                try importEntries(entries)
                alertMessage = "Imported \(entries.count) secrets"
            } catch {
                alertMessage = "Import failed: \(error.localizedDescription)"
            }
            showingAlert = true

        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func importEntries(_ entries: [ExportEntry]) throws {
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

#Preview {
    SettingsView()
        .environment(ClipboardService())
        .modelContainer(for: [SecretItem.self], inMemory: true)
}
