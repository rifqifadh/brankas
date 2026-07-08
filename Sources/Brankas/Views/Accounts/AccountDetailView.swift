import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Environment(ClipboardService.self) private var clipboardService
    @Environment(\.modelContext) private var modelContext

    let account: Account
    var onDelete: (() -> Void)?

    @State private var isValueRevealed = false
    @State private var secretValue: String?
    @State private var totpConfig: TOTPConfiguration?
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Divider()

                usernameSection

                Divider()

                valueSection

                Divider()

                metadataSection

                if !account.notes.isEmpty {
                    Divider()
                    notesSection
                }

                if account.hasTOTP {
                    Divider()
                    totpSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingEditSheet) {
            AccountFormView(existingAccount: account)
        }
        .alert("Delete Account?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("Account \"\(account.identifier)\" for \(account.service.name) will be permanently deleted. The secret value and any associated TOTP will also be removed.")
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Copy", systemImage: "doc.on.doc") {
                    copyValue()
                }
                .keyboardShortcut("c")

                Button("Edit", systemImage: "pencil") {
                    showingEditSheet = true
                }
                .labelStyle(.titleOnly)
                .keyboardShortcut("e")

                Button("Delete", systemImage: "trash") {
                    showingDeleteAlert = true
                }
                .foregroundStyle(.red)
            }
        }
        .onAppear {
            loadTOTP()
        }
        .onChange(of: account.hasTOTP) { _, _ in
            loadTOTP()
        }

    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: account.service.icon)
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.identifier)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text(account.service.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let url = account.service.url, let validURL = URL(string: url) {
                        Link(url, destination: validURL)
                            .font(.caption)
                    }

                    if account.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Spacer()
        }
    }

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Username", systemImage: "person.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(account.identifier)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(.rect(cornerRadius: 8))

                Button("Copy", systemImage: "doc.on.doc") {
                    clipboardService.copy(account.identifier)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Copy username")
            }
        }
    }

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Secret Value", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Group {
                    if isValueRevealed, let value = secretValue {
                        Text(value)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "•", count: min(secretValue?.count ?? 20, 40)))
                            .font(.body.monospaced())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(.rect(cornerRadius: 8))

                Button(isValueRevealed ? "Hide" : "Show", systemImage: isValueRevealed ? "eye.slash" : "eye") {
                    lazyLoad()
                    withAnimation { isValueRevealed.toggle() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)

                Button("Copy", systemImage: "doc.on.doc") {
                    copyValue()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Details", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Service")
                        .foregroundStyle(.secondary)
                    Text(account.service.name)
                }
                GridRow {
                    Text("Created")
                        .foregroundStyle(.secondary)
                    Text(account.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                GridRow {
                    Text("Updated")
                        .foregroundStyle(.secondary)
                    Text(account.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let expiry = account.expiresAt {
                    GridRow {
                        Text("Expires")
                            .foregroundStyle(.secondary)
                        expiryBadge(expiry)
                    }
                }
                if let url = account.service.url, !url.isEmpty, let validURL = URL(string: url) {
                    GridRow {
                        Text("URL")
                            .foregroundStyle(.secondary)
                        Link(url, destination: validURL)
                    }
                }
            }
            .font(.callout)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(account.notes)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(.rect(cornerRadius: 8))
        }
    }

    private func copyValue() {
        lazyLoad()
        guard let value = secretValue else { return }
        clipboardService.copy(value)
    }

    private func lazyLoad() {
        guard secretValue == nil else { return }
        secretValue = try? VaultService.read(for: account.id.uuidString)
    }

    @ViewBuilder
    private var totpSection: some View {
        if let config = totpConfig {
            TOTPView(config: config)
        }
    }

    private func delete() {
        try? VaultService.deleteAccount(id: account.id, context: modelContext)
        onDelete?()
    }

    private func loadTOTP() {
        guard account.hasTOTP else { return }
        let raw = try? VaultService.read(for: "totp-\(account.id.uuidString)")
        if let raw {
            totpConfig = TOTPService.parseURL(raw)
            Task { await TimeSyncService.sync() }
        } else {
            totpConfig = nil
        }
    }

    private func expiryBadge(_ date: Date) -> some View {
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        let isExpired = daysUntil <= 0
        let isSoon = daysUntil <= 30

        let label = isExpired ? "Expired \(abs(daysUntil))d ago" : "\(daysUntil) days"
        let color: Color = isExpired ? .red : isSoon ? .orange : .green

        return Label(label, systemImage: isExpired ? "xmark.circle.fill" : "clock")
            .foregroundStyle(color)
            .font(.callout)
    }
}

#Preview {
    let service = Service(name: "GitHub", url: "https://github.com", icon: "globe")
    let account = Account(identifier: "user@example.com", notes: "Main account", isFavorite: true, service: service)
    return AccountDetailView(account: account)
        .environment(ClipboardService())
        .modelContainer(for: [Account.self, Service.self], inMemory: true)
        .frame(width: 400, height: 500)
}
