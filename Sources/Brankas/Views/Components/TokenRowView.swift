import SwiftUI

struct TokenRowView: View {
    let item: SecretItem
    var showTypeIcon: Bool = true
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(spacing: 10) {
            if showTypeIcon {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }

                    if let firstTag = item.tags.first {
                        Text(firstTag.name)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(.rect(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            if let onCopy {
                Button("Copy", systemImage: "doc.on.doc") {
                    onCopy()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy to clipboard")
            }

            if onDelete != nil {
                Button("Delete", systemImage: "trash") {
                    showingDeleteAlert = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete this item")
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .alert("Delete \"\(item.name)\"?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete?() }
        } message: {
            Text("This will permanently delete the item and its secret value.")
        }
    }
}

#Preview {
    TokenRowView(
        item: SecretItem(name: "API Key", type: .token, isFavorite: true),
        onCopy: {},
        onDelete: {}
    )
    .padding()
}
