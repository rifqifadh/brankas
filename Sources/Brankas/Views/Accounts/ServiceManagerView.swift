import SwiftUI
import SwiftData

struct ServiceManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Service.name) private var services: [Service]

    @State private var editingService: Service?

    var body: some View {
        NavigationStack {
            List {
                if services.isEmpty {
                    ContentUnavailableView(
                        "No Services",
                        systemImage: "globe",
                        description: Text("Add a service to get started.")
                    )
                } else {
                    ForEach(services) { service in
                        HStack(spacing: 10) {
                            Image(systemName: service.icon)
                                .foregroundStyle(.tint)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.body)
                                if let url = service.url, !url.isEmpty {
                                    Text(url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text("\(service.accounts.count) accounts")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Edit", systemImage: "pencil") {
                                editingService = service
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Edit this service")
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteServices)
                }
            }
            .listStyle(.inset)
            .navigationTitle("Manage Services")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 380, height: 350)
        .sheet(item: $editingService) { service in
            ServiceFormView(existingService: service)
        }
    }

    private func deleteServices(_ indexSet: IndexSet) {
        for index in indexSet {
            try? VaultService.deleteService(id: services[index].id, context: modelContext)
        }
    }
}

#Preview {
    ServiceManagerView()
        .modelContainer(for: [Service.self], inMemory: true)
}
