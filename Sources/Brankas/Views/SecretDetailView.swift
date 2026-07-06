import SwiftUI
import SwiftData

struct SecretDetailView: View {
    @Environment(ClipboardService.self) private var clipboardService
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [Category]

    let secret: SecretItem
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

                valueSection

                Divider()

                metadataSection

                if !secret.notes.isEmpty {
                    Divider()
                    notesSection
                }

                if !secret.tags.isEmpty {
                    Divider()
                    tagsSection
                }

                if secret.hasTOTP {
                    Divider()
                    totpSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingEditSheet) {
            SecretFormView(mode: .edit(secret))
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
                .keyboardShortcut("e")

                Button("Delete", systemImage: "trash") {
                    showingDeleteAlert = true
                }
                .foregroundStyle(.red)
            }
        }
        .alert("Delete Secret?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteSecret() }
        } message: {
            Text("\"\(secret.name)\" will be permanently deleted. The secret value and any associated TOTP will also be removed.")
        }
        .onAppear {
            loadTOTP()
        }
        .onChange(of: secret.hasTOTP) { _, _ in
            loadTOTP()
        }

    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: secret.type.iconName)
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(secret.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text(secret.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let category = categories.first(where: { $0.id == secret.categoryId }) {
                        Label(category.name, systemImage: category.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if secret.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Spacer()
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
                .help(isValueRevealed ? "Hide value" : "Reveal value")

                Button("Copy", systemImage: "doc.on.doc") {
                    copyValue()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Copy to clipboard")
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
                    Text("Created")
                        .foregroundStyle(.secondary)
                    Text(secret.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                GridRow {
                    Text("Updated")
                        .foregroundStyle(.secondary)
                    Text(secret.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let expiry = secret.expiresAt {
                    GridRow {
                        Text("Expires")
                            .foregroundStyle(.secondary)
                        expiryBadge(expiry)
                    }
                }

                if let urlString = secret.url, !urlString.isEmpty, let validURL = URL(string: urlString) {
                    GridRow {
                        Text("URL")
                            .foregroundStyle(.secondary)
                        Link(urlString, destination: validURL)
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

            Text(secret.notes)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(.rect(cornerRadius: 8))
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tags", systemImage: "tag")
                .font(.headline)
                .foregroundStyle(.secondary)

            TagView(tags: secret.tags)
        }
    }

    @ViewBuilder
    private var totpSection: some View {
        if let config = totpConfig {
            TOTPView(config: config)
        }
    }

    private func lazyLoad() {
        guard secretValue == nil else { return }
        secretValue = try? VaultService.read(for: secret.id.uuidString)
    }

    private func copyValue() {
        lazyLoad()
        guard let value = secretValue else { return }
        clipboardService.copy(value)
    }

    private func deleteSecret() {
        try? VaultService.deleteItem(id: secret.id, context: modelContext)
        onDelete?()
    }

    private func loadTOTP() {
        guard secret.hasTOTP else { return }
        let raw = try? VaultService.read(for: "totp-\(secret.id.uuidString)")
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

        let label: String
        let color: Color

        if isExpired {
            label = "Expired \(abs(daysUntil))d ago"
            color = .red
        } else if isSoon {
            label = "\(daysUntil) days"
            color = .orange
        } else {
            label = "\(daysUntil) days"
            color = .green
        }

        return Label(label, systemImage: isExpired ? "xmark.circle.fill" : "clock")
            .foregroundStyle(color)
            .font(.callout)
    }
}
