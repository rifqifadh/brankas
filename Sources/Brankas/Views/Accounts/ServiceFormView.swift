import SwiftUI
import SwiftData

struct ServiceFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingService: Service?

    @State private var name = ""
    @State private var url = ""
    @State private var selectedIcon = "globe"
    @State private var errorMessage: String?
    @State private var showIconPicker = false

    private var isEditing: Bool { existingService != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service Name") {
                    TextField("Name", text: $name)
                }

                Section("URL") {
                    TextField("https://example.com", text: $url)
                }

                Section("Icon") {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Image(systemName: selectedIcon)
                                .font(.title2)
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.tint)
                            Text(selectedIcon)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
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
            .navigationTitle(isEditing ? "Edit Service" : "New Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.return)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 380, height: 350)
        .sheet(isPresented: $showIconPicker) {
            SFSymbolPicker(selectedIcon: $selectedIcon)
        }
        .onAppear {
            if let service = existingService {
                name = service.name
                url = service.url ?? ""
                selectedIcon = service.icon
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            let data = ServiceData(
                id: existingService?.id ?? UUID(),
                name: trimmedName,
                url: url.trimmingCharacters(in: .whitespaces).isEmpty ? nil : url,
                icon: selectedIcon
            )
            if isEditing {
                try VaultService.updateService(data: data, context: modelContext)
            } else {
                try VaultService.createService(data: data, context: modelContext)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ServiceFormView()
        .modelContainer(for: [Service.self], inMemory: true)
}
