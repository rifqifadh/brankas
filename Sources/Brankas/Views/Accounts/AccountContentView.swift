import SwiftUI
import SwiftData

struct AccountContentView: View {
    @Binding var selectedAccount: Account?

    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardService.self) private var clipboardService
    @Query(sort: \Service.name) private var services: [Service]
    @Query(sort: \Account.updatedAt, order: .reverse) private var allAccounts: [Account]

    @State private var searchText = ""
    @State private var expandedServices: Set<UUID> = []
    @State private var showingAddService = false
    @State private var showingAddAccount = false
    @State private var showingManageServices = false

    private var filteredServices: [Service] {
        guard !searchText.isEmpty else { return services }
        return services.filter { svc in
            svc.name.localizedStandardContains(searchText)
                || svc.accounts.contains { acct in
                    acct.identifier.localizedStandardContains(searchText)
                        || acct.notes.localizedStandardContains(searchText)
                }
        }
    }

    private func accounts(for service: Service) -> [Account] {
        let result = allAccounts.filter { $0.service.id == service.id }
        guard !searchText.isEmpty else { return result }
        if service.name.localizedStandardContains(searchText) {
            return result
        }
        return result.filter { acct in
            acct.identifier.localizedStandardContains(searchText)
                || acct.notes.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        Group {
            if services.isEmpty {
                ContentUnavailableView(
                    "No Services",
                    systemImage: "globe",
                    description: Text("Add a service to start storing accounts.")
                )
            } else {
                List(selection: $selectedAccount) {
                    ForEach(filteredServices) { service in
                        let accts = accounts(for: service)
                        Section {
                            DisclosureGroup(isExpanded: expandedBinding(for: service.id)) {
                                ForEach(accts) { account in
                                    AccountRowView(account: account, onCopyUsername: { copyUsername(account) }, onCopy: { copyAccount(account) }, onDelete: { confirmDeleteAccount(account) })
                                        .tag(account)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: service.icon)
                                        .foregroundStyle(.tint)
                                        .frame(width: 20)
                                    Text(service.name)
                                        .font(.headline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(accts.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary.opacity(0.5))
                                        .clipShape(.rect(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search services or accounts...")
                .onChange(of: searchText) { _, newValue in
                    if !newValue.isEmpty {
                        expandedServices = Set(services.map(\.id))
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Add Account", systemImage: "plus") {
                    showingAddAccount = true
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("n")
                .help("Add Account")

                Button("Add Service", systemImage: "folder.badge.plus") {
                    showingAddService = true
                }
                .labelStyle(.iconOnly)
                .help("Add Service")

                Button("Manage Services", systemImage: "gearshape") {
                    showingManageServices = true
                }
                .labelStyle(.iconOnly)
                .help("Manage Services")
            }
        }
        .sheet(isPresented: $showingAddService) {
            ServiceFormView()
        }
        .sheet(isPresented: $showingManageServices) {
            ServiceManagerView()
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountFormView()
        }
    }

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedServices.contains(id) },
            set: { expanded in
                if expanded { expandedServices.insert(id) }
                else { expandedServices.remove(id) }
            }
        )
    }

    private func copyUsername(_ account: Account) {
        clipboardService.copy(account.identifier)
    }

    private func copyAccount(_ account: Account) {
        guard let value = try? VaultService.read(for: account.id.uuidString) else { return }
        clipboardService.copy(value)
    }

    private func confirmDeleteAccount(_ account: Account) {
        if selectedAccount?.id == account.id { selectedAccount = nil }
        try? VaultService.deleteAccount(id: account.id, context: modelContext)
    }
}

struct AccountRowView: View {
    let account: Account
    var onCopyUsername: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle")
                .foregroundStyle(.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.identifier)
                    .font(.body)
                    .lineLimit(1)

                if let expiry = account.expiresAt {
                    expiryLabel(expiry)
                }
            }

            Spacer()

            if account.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            Button("Copy Username", systemImage: "person.circle") {
                onCopyUsername?()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy username")

            Button("Copy Password", systemImage: "doc.on.doc") {
                onCopy?()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy password")

            if onDelete != nil {
                Button("Delete", systemImage: "trash") {
                    showingDeleteAlert = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete this account")
            }
        }
        .padding(.vertical, 2)
        .alert("Delete \"\(account.identifier)\"?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete?() }
        } message: {
            Text("This will permanently delete the account and its secret value.")
        }
    }

    private func expiryLabel(_ date: Date) -> some View {
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        let isExpired = daysUntil <= 0
        return Label(
            isExpired ? "Expired \(abs(daysUntil))d ago" : "\(daysUntil)d",
            systemImage: isExpired ? "xmark.circle.fill" : "clock"
        )
        .font(.caption2)
        .foregroundStyle(isExpired ? .red : .orange)
    }
}
