import SwiftUI
import SwiftData

struct ServicePickerView: View {
    let services: [Service]
    @Binding var selectedService: Service?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var filtered: [Service] {
        guard !searchText.isEmpty else { return services }
        return services.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { service in
                Button {
                    selectedService = service
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: service.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 20)
                        Text(service.name)
                        Spacer()
                        if selectedService?.id == service.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search services...")
            .navigationTitle("Select Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 320, height: 400)
    }
}

#Preview {
    ServicePickerView(
        services: [
            Service(name: "GitHub", url: "https://github.com", icon: "globe"),
            Service(name: "Google", url: "https://google.com", icon: "network")
        ],
        selectedService: .constant(nil)
    )
}
