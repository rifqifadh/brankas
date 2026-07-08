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
    @State private var selectedService: Service?
    @State private var hasExpiry = false
    @State private var expiresAt = Date().addingTimeInterval(86400 * 90)
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var isValueRevealed = false
    @State private var hasTOTP = false
    @State private var totpInput = ""
    @State private var parsedConfig: TOTPConfiguration?
    @State private var showingServicePicker = false
    @State private var errorMessage: String?

    private var title: String {
        existingAccount != nil ? "Edit Account" : "New Account"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    Button {
                        showingServicePicker = true
                    } label: {
                        HStack {
                            if let service = selectedService {
                                Label(service.name, systemImage: service.icon)
                            } else {
                                Text("Select a service...")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $showingServicePicker) {
                    ServicePickerView(services: services, selectedService: $selectedService)
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
                selectedService = preselectedService
                if let account = existingAccount {
                    identifier = account.identifier
                    notes = account.notes
                    isFavorite = account.isFavorite
                    selectedService = account.service
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
        guard let service = selectedService else {
            errorMessage = "Select a service"
            return
        }

        do {
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
