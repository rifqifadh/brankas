import SwiftUI
import SwiftData

struct AccountFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Service.name) private var services: [Service]

    var existingAccount: Account?
    var preselectedService: Service?

    @State private var identifier = ""
    @State private var secretValue = ""
    @State private var serviceName = ""
    @State private var serviceIcon = "globe"
    @State private var hasExpiry = false
    @State private var expiresAt = Date().addingTimeInterval(86400 * 90)
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var isValueRevealed = false
    @State private var hasTOTP = false
    @State private var totpInput = ""
    @State private var parsedConfig: TOTPConfiguration?
    @State private var errorMessage: String?

    private let iconOptions = ["globe", "network", "cloud", "externaldrive", "server.rack",
                                "building", "house", "bolt", "lock", "person"]

    private var title: String {
        existingAccount != nil ? "Edit Account" : "New Account"
    }

    private var matchedService: Service? {
        guard !serviceName.isEmpty else { return nil }
        return services.first { $0.name.localizedCaseInsensitiveCompare(serviceName) == .orderedSame }
    }

    private var filteredServices: [Service] {
        guard !serviceName.isEmpty else { return [] }
        return services.filter { $0.name.localizedStandardContains(serviceName) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Service name", text: $serviceName)
                        .onChange(of: serviceName) { _, _ in
                            if let match = matchedService {
                                serviceIcon = match.icon
                            }
                        }

                    if !filteredServices.isEmpty {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(filteredServices) { svc in
                                    Button {
                                        serviceName = svc.name
                                        serviceIcon = svc.icon
                                    } label: {
                                        Label(svc.name, systemImage: svc.icon)
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
                        .frame(maxHeight: 100)
                        .background(.quaternary.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 6))
                    }

                    if !serviceName.isEmpty && matchedService == nil {
                        DisclosureGroup("Choose icon") {
                            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 12) {
                                ForEach(iconOptions, id: \.self) { icon in
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .frame(width: 36, height: 36)
                                        .background(serviceIcon == icon ? Color.accentColor.opacity(0.2) : .clear)
                                        .clipShape(.rect(cornerRadius: 8))
                                        .onTapGesture { serviceIcon = icon }
                                }
                            }
                        }
                    }
                }

                Section("Account") {
                    TextField("Email or username", text: $identifier)

                    HStack {
                        Group {
                            if isValueRevealed {
                                TextField("Secret value", text: $secretValue)
                            } else {
                                SecureField("Secret value", text: $secretValue)
                            }
                        }
                        .font(.body.monospaced())

                        Button(isValueRevealed ? "Hide" : "Show", systemImage: isValueRevealed ? "eye.slash" : "eye") {
                            isValueRevealed.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                    }
                }

                Section("Expiry") {
                    Picker("Expiry", selection: $hasExpiry) {
                        Text("No Expiration").tag(false)
                        Text("Expires On").tag(true)
                    }
                    .pickerStyle(.menu)

                    if hasExpiry {
                        DatePicker("Date", selection: $expiresAt, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("Favorite", isOn: $isFavorite)
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
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.return)
                }
            }
            .onChange(of: totpInput) { _, newValue in
                parsedConfig = TOTPService.parseURL(newValue)
            }
            .onAppear {
                if let account = existingAccount {
                    identifier = account.identifier
                    notes = account.notes
                    isFavorite = account.isFavorite
                    serviceName = account.service.name
                    serviceIcon = account.service.icon
                    secretValue = (try? VaultService.read(for: account.id.uuidString)) ?? ""
                    hasTOTP = account.hasTOTP
                    if account.hasTOTP {
                        let saved = (try? VaultService.read(for: "totp-\(account.id.uuidString)")) ?? ""
                        totpInput = saved
                        parsedConfig = TOTPService.parseURL(saved)
                    }
                    if let expiry = account.expiresAt {
                        hasExpiry = true
                        expiresAt = expiry
                    }
                } else if let service = preselectedService {
                    serviceName = service.name
                    serviceIcon = service.icon
                }
            }
        }
        .frame(width: 420, height: 480)
    }

    private func save() {
        let trimmedId = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmedId.isEmpty else {
            errorMessage = "Email or username is required"
            return
        }
        guard !secretValue.isEmpty else {
            errorMessage = "Secret value is required"
            return
        }

        let trimmedName = serviceName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Service name is required"
            return
        }

        do {
            let service: Service
            if let match = matchedService {
                service = match
            } else {
                let data = ServiceData(id: UUID(), name: trimmedName, icon: serviceIcon)
                service = try VaultService.createService(data: data, context: modelContext)
            }

            let totpValue = parsedConfig?.secret ?? totpInput

            if let account = existingAccount {
                let data = AccountData(
                    id: account.id,
                    identifier: trimmedId,
                    notes: notes,
                    expiresAt: hasExpiry ? expiresAt : nil,
                    hasTOTP: hasTOTP,
                    isFavorite: isFavorite,
                    createdAt: account.createdAt,
                    updatedAt: Date(),
                    serviceId: service.id
                )
                try VaultService.updateAccount(data: data, secret: secretValue, context: modelContext)
                if hasTOTP {
                    try VaultService.save(secret: totpValue, for: "totp-\(account.id.uuidString)")
                } else {
                    try? VaultService.deleteSecret(for: "totp-\(account.id.uuidString)")
                }
            } else {
                let id = UUID()
                let data = AccountData(
                    id: id,
                    identifier: trimmedId,
                    notes: notes,
                    expiresAt: hasExpiry ? expiresAt : nil,
                    hasTOTP: hasTOTP,
                    isFavorite: isFavorite,
                    createdAt: Date(),
                    updatedAt: Date(),
                    serviceId: service.id
                )
                try VaultService.createAccount(data: data, secret: secretValue, context: modelContext)
                if hasTOTP {
                    try VaultService.save(secret: totpValue, for: "totp-\(id.uuidString)")
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AccountFormView()
        .modelContainer(for: [Service.self, Account.self], inMemory: true)
}
