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

    private let iconOptions = ["globe", "network", "cloud", "externaldrive", "server.rack",
                               "building", "house", "bolt", "lock", "person"]

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
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : .clear)
                                .clipShape(.rect(cornerRadius: 8))
                                .onTapGesture { selectedIcon = icon }
                        }
                    }
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
