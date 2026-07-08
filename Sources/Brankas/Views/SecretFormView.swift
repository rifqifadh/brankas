import SwiftUI
import SwiftData

enum SecretFormMode: Identifiable {
    case add
    case edit(SecretItem)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let item): item.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add: "New Secret"
        case .edit: "Edit Secret"
        }
    }
}

struct SecretFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    let mode: SecretFormMode

    @State private var name = ""
    @State private var selectedType: SecretType = .token
    @State private var value = ""
    @State private var selectedCategoryId: UUID?
    @State private var tagSearch = ""
    @State private var selectedTags: [Tag] = []
    @State private var url = ""
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var isValueRevealed = false
    @State private var hasExpiry = false
    @State private var expiresAt: Date = Date().addingTimeInterval(86400 * 90)
    @State private var hasTOTP = false
    @State private var totpInput = ""
    @State private var parsedConfig: TOTPConfiguration?
    @State private var errorMessage: String?

    private var matchingTags: [Tag] {
        guard !tagSearch.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let search = tagSearch.lowercased()
        return allTags.filter { tag in
            tag.name.lowercased().contains(search) && !selectedTags.contains(where: { $0.id == tag.id })
        }
    }

    var body: some View {
        Form {
            Section("Basic Information") {
                TextField("Name", text: $name)
                    .lineLimit(1)

                Picker("Type", selection: $selectedType) {
                    ForEach(SecretType.allCases) { type in
                        Label(type.displayName, systemImage: type.iconName)
                            .tag(type)
                    }
                }

                Picker("Category", selection: $selectedCategoryId) {
                    Text("None").tag(nil as UUID?)
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.icon)
                            .tag(category.id as UUID?)
                    }
                }
            }

            Section("Secret Value") {
                HStack {
                    Group {
                        if isValueRevealed {
                            TextField("Value", text: $value)
                        } else {
                            SecureField("Value", text: $value)
                        }
                    }
                    .font(.body.monospaced())

                    Button(isValueRevealed ? "Hide" : "Show", systemImage: isValueRevealed ? "eye.slash" : "eye") {
                        isValueRevealed.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help(isValueRevealed ? "Hide value" : "Reveal value")
                }
            }

            Section("Tags") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        TextField("Search or create tag...", text: $tagSearch)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .onSubmit {
                                createAndAddTag()
                            }

                        Button("Add", systemImage: "plus.circle.fill") {
                            createAndAddTag()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .disabled(tagSearch.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(.rect(cornerRadius: 6))

                    if !matchingTags.isEmpty {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(matchingTags) { tag in
                                    Button {
                                        selectedTags.append(tag)
                                        tagSearch = ""
                                        errorMessage = nil
                                    } label: {
                                        Label(tag.name, systemImage: "tag")
                                            .font(.callout)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                        .background(.quaternary.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 6))
                    }

                    if !selectedTags.isEmpty {
                        TagView(tags: selectedTags, removable: true) { tag in
                            selectedTags.removeAll { $0.id == tag.id }
                        }
                    }

                    if !tagSearch.isEmpty && matchingTags.isEmpty {
                        Text("Press Enter to create \"\(tagSearch)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Additional") {
                TextField("URL (optional)", text: $url)
                    .lineLimit(1)

                Toggle("Favorite", isOn: $isFavorite)

                Picker("Expiry", selection: $hasExpiry) {
                    Text("No Expiration").tag(false)
                    Text("Expires On").tag(true)
                }
                .pickerStyle(.menu)

                if hasExpiry {
                    DatePicker("Date", selection: $expiresAt, displayedComponents: .date)
                }
            }

            Section("Two-Factor Authentication") {
                Toggle("Enable TOTP", isOn: $hasTOTP)
                if hasTOTP {
                    TextField("Paste otpauth:// URL or base32 secret", text: $totpInput)
                        .font(.body.monospaced())
                        .disableAutocorrection(true)
                    if parsedConfig != nil {
                        HStack(spacing: 4) {
                            if let issuer = parsedConfig?.issuer {
                                Text(issuer).font(.caption).foregroundStyle(.secondary)
                            }
                            if let account = parsedConfig?.account {
                                Text("•").font(.caption).foregroundStyle(.tertiary)
                                Text(account).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !totpInput.isEmpty {
                        if let config = parsedConfig, let code = TOTPService.generate(config: config) {
                            HStack(spacing: 8) {
                                Text(code)
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .tracking(4)
                                Text("\(TOTPService.remainingSeconds(config: config))s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } else {
                            Text("Invalid secret")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 550)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return)
            }
        }
        .onChange(of: totpInput) { _, newValue in
            parsedConfig = TOTPService.parseURL(newValue)
        }
        .onAppear {
            if case .edit(let item) = mode {
                name = item.name
                selectedType = item.type
                selectedCategoryId = item.categoryId
                selectedTags = item.tags
                url = item.url ?? ""
                notes = item.notes
                isFavorite = item.isFavorite
                if let expiry = item.expiresAt {
                    hasExpiry = true
                    expiresAt = expiry
                }
                hasTOTP = item.hasTOTP
                if item.hasTOTP {
                    let saved = (try? VaultService.read(for: "totp-\(item.id.uuidString)")) ?? ""
                    totpInput = saved
                    parsedConfig = TOTPService.parseURL(saved)
                }
                value = (try? VaultService.read(for: item.id.uuidString)) ?? ""
            }
        }
    }

    private func createAndAddTag() {
        let trimmed = tagSearch.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let existing = allTags.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            if !selectedTags.contains(where: { $0.id == existing.id }) {
                selectedTags.append(existing)
            }
        } else {
            if let newTag = try? VaultService.createTag(data: TagData(id: UUID(), name: trimmed), context: modelContext) {
                selectedTags.append(newTag)
            }
        }
        tagSearch = ""
        errorMessage = nil
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            return
        }
        guard !value.isEmpty else {
            errorMessage = "Secret value is required"
            return
        }

        do {
            let totpValue = parsedConfig?.secret ?? totpInput

            switch mode {
            case .add:
                let id = UUID()
                let data = SecretItemData(
                    id: id,
                    name: trimmedName,
                    typeRawValue: selectedType.rawValue,
                    categoryId: selectedCategoryId,
                    tagIds: selectedTags.map(\.id),
                    notes: notes,
                    url: url.isEmpty ? nil : url,
                    expiresAt: hasExpiry ? expiresAt : nil,
                    hasTOTP: hasTOTP,
                    isFavorite: isFavorite,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try VaultService.createItem(data: data, secret: value, context: modelContext)
                if hasTOTP {
                    try VaultService.save(secret: totpValue, for: "totp-\(id.uuidString)")
                }

            case .edit(let item):
                let data = SecretItemData(
                    id: item.id,
                    name: trimmedName,
                    typeRawValue: selectedType.rawValue,
                    categoryId: selectedCategoryId,
                    tagIds: selectedTags.map(\.id),
                    notes: notes,
                    url: url.isEmpty ? nil : url,
                    expiresAt: hasExpiry ? expiresAt : nil,
                    hasTOTP: hasTOTP,
                    isFavorite: isFavorite,
                    createdAt: item.createdAt,
                    updatedAt: Date()
                )
                try VaultService.updateItem(data: data, secret: value, context: modelContext)
                if hasTOTP {
                    try VaultService.save(secret: totpValue, for: "totp-\(item.id.uuidString)")
                } else {
                    try? VaultService.deleteSecret(for: "totp-\(item.id.uuidString)")
                }
            }

            dismiss()

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SecretFormView(mode: .add)
        .modelContainer(for: [SecretItem.self, Category.self, Tag.self], inMemory: true)
}
