import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClipboardService.self) private var clipboardService
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(sort: \SecretItem.updatedAt, order: .reverse) private var allSecrets: [SecretItem]

    @State private var selectedTab: Tab = .vault
    @State private var filterCategory: Category?
    @State private var filterTag: Tag?
    @State private var selectedSecret: SecretItem?
    @State private var selectedAccount: Account?
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingCategoryManager = false

    enum Tab: Hashable {
        case vault
        case accounts
    }

    private var filteredSecrets: [SecretItem] {
        var result = allSecrets

        if let cat = filterCategory {
            result = result.filter { $0.categoryId == cat.id }
        }
        if let tag = filterTag {
            result = result.filter { $0.tags.contains { $0.id == tag.id } }
        }

        guard !searchText.isEmpty else { return result }
        return result.filter { item in
            item.name.localizedStandardContains(searchText)
                || item.tags.contains { $0.name.localizedStandardContains(searchText) }
                || item.notes.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if selectedTab == .vault {
                vaultListContent
            } else {
                AccountContentView(selectedAccount: $selectedAccount)
            }
        } detail: {
            detailContent
        }
        .sheet(isPresented: $showingAddSheet) {
            SecretFormView(mode: .add)
        }
        .sheet(isPresented: $showingCategoryManager) {
            CategoryManagerView()
        }
    }

    private var sidebar: some View {
        List {
            Section {
                Button {
                    selectedTab = .vault
                } label: {
                    Label("Vault", systemImage: "key.fill")
                        .foregroundStyle(selectedTab == .vault ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Button {
                    selectedTab = .accounts
                } label: {
                    Label("Accounts", systemImage: "person.crop.circle")
                        .foregroundStyle(selectedTab == .accounts ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 170)
    }

    @ViewBuilder
    private var detailContent: some View {
        if selectedTab == .vault {
            if let secret = selectedSecret {
                SecretDetailView(secret: secret, onDelete: { selectedSecret = nil })
            } else {
                ContentUnavailableView(
                    "Select a Secret",
                    systemImage: "key.slash",
                    description: Text("Choose an item from the list to view its details.")
                )
            }
        } else {
            if let account = selectedAccount {
                AccountDetailView(account: account, onDelete: { selectedAccount = nil })
            } else {
                ContentUnavailableView(
                    "Select an Account",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Choose an account from the list to view its details.")
                )
            }
        }
    }

    private var vaultListContent: some View {
        VStack(spacing: 0) {
            filtersRow
                .padding(.horizontal)
                .padding(.vertical, 6)
                .layoutPriority(1)

            if filteredSecrets.isEmpty && filterCategory == nil && filterTag == nil && searchText.isEmpty {
                ContentUnavailableView(
                    "No Secrets",
                    systemImage: "key.slash",
                    description: Text("Add a token or password to get started.")
                )
                .frame(maxHeight: .infinity)
            } else if filteredSecrets.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try adjusting your filters or search.")
                )
                .frame(maxHeight: .infinity)
            } else {
                    List(selection: $selectedSecret) {
                        ForEach(filteredSecrets) { item in
                            TokenRowView(item: item, onCopy: { copySecret(item) }, onDelete: { confirmDelete(item) })
                                .tag(item)
                                .padding(.vertical, 2)
                        }
                        .onDelete(perform: deleteSecrets)
                    }
                    .searchable(text: $searchText, prompt: "Search by name, tag, or notes")
                    .frame(maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Add Secret", systemImage: "plus") {
                    showingAddSheet = true
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("n")

                Button("Manage Categories", systemImage: "folder.badge.gearshape") {
                    showingCategoryManager = true
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private var filtersRow: some View {
        HStack(spacing: 8) {
            Picker("Category", selection: $filterCategory) {
                Text("All Categories").tag(nil as Category?)
                ForEach(categories) { cat in
                    HStack(spacing: 4) {
                        Image(systemName: cat.icon)
                        Text(cat.name)
                    }
                    .tag(cat as Category?)
                }
            }
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)

            Picker("Tag", selection: $filterTag) {
                Text("All Tags").tag(nil as Tag?)
                ForEach(allTags) { tag in
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                        Text(tag.name)
                    }
                    .tag(tag as Tag?)
                }
            }
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)

            if filterCategory != nil || filterTag != nil {
                Button("Clear") {
                    filterCategory = nil
                    filterTag = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            }

            Spacer()
        }
    }

    private func copySecret(_ item: SecretItem) {
        guard let value = try? VaultService.read(for: item.id.uuidString) else { return }
        clipboardService.copy(value)
    }

    private func confirmDelete(_ item: SecretItem) {
        if selectedSecret?.id == item.id { selectedSecret = nil }
        try? VaultService.deleteItem(id: item.id, context: modelContext)
    }

    private func deleteSecrets(_ indexSet: IndexSet) {
        for index in indexSet {
            confirmDelete(filteredSecrets[index])
        }
    }
}

#Preview {
    ContentView()
        .environment(ClipboardService())
        .modelContainer(for: [SecretItem.self, Category.self, Tag.self, Account.self, Service.self], inMemory: true)
}
