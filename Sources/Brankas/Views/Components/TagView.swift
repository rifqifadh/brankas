import SwiftUI

struct TagView: View {
    let tags: [Tag]
    var removable: Bool = false
    var onRemove: ((Tag) -> Void)?

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.id) { tag in
                        tagPill(tag)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tagPill(_ tag: Tag) -> some View {
        HStack(spacing: 3) {
            Text(tag.name)
                .font(.caption)
                .lineLimit(1)
            if removable {
                Button("Remove", systemImage: "xmark") {
                    onRemove?(tag)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .imageScale(.small)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.tint.opacity(0.15))
        .foregroundStyle(.tint)
        .clipShape(.rect(cornerRadius: 4))
    }
}
