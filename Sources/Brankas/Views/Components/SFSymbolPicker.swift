import SwiftUI

struct SFSymbolPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String

    @State private var searchText = ""

    private let icons = SFSymbolPicker.iconList

    private var filteredIcons: [String] {
        guard !searchText.isEmpty else { return icons }
        return icons.filter { $0.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7), spacing: 12) {
                    ForEach(filteredIcons, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : .clear)
                            .clipShape(.rect(cornerRadius: 8))
                            .onTapGesture {
                                selectedIcon = icon
                                dismiss()
                            }
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search symbols...")
            .navigationTitle("Choose Icon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 400, height: 500)
    }

    private static let iconList: [String] = [
        // Communication
        "message", "mail", "phone", "envelope", "bubble.left", "bubble.right",
        "ellipsis.bubble", "quote.bubble", "exclamationmark.bubble",
        // Social / People
        "person", "person.2", "person.3", "person.crop.circle", "person.circle",
        "person.text.rectangle", "shareplay",
        // Tech - Devices
        "display", "laptopcomputer", "macmini", "macpro.gen3", "server.rack",
        "externaldrive", "network", "wifi", "antenna.radiowaves.left.and.right",
        "printer", "scanner", "keyboard", "magicmouse.fill",
        // Tech - Code / Dev
        "chevron.left.forwardslash.chevron.right", "terminal", "applescript",
        "apple.terminal", "gearshape.2", "memorychip", "cpu",
        // Cloud
        "cloud", "cloud.fill", "icloud", "icloud.fill",
        // Media
        "tv", "tv.fill", "play.display", "music.note", "music.note.list",
        "film", "video", "video.fill", "mic", "mic.fill", "speaker.wave.2",
        // Finance
        "dollarsign.circle", "dollarsign.circle.fill", "creditcard",
        "banknote", "chart.pie", "chart.bar", "chart.line.uptrend.xyaxis",
        "centsign.circle",
        // Shopping
        "cart", "bag", "basket", "storefront", "giftcard",
        // Travel / Location
        "airplane", "car", "bus", "tram", "map", "map.fill", "location",
        "location.fill", "mappin",
        // Home / Building
        "house", "house.fill", "building", "building.fill",
        "building.columns", "building.columns.fill", "door.left.hand.open",
        // Security
        "lock", "lock.fill", "lock.shield", "lock.shield.fill", "shield",
        "shield.fill", "key", "key.fill", "touchid", "eye",
        // Tools
        "hammer", "hammer.fill", "wrench", "wrench.fill", "screwdriver",
        "gearshape", "gearshape.fill", "slider.horizontal.3",
        // Office / Work
        "briefcase", "briefcase.fill", "folder", "folder.fill",
        "doc", "doc.fill", "doc.text", "doc.text.fill",
        "bookmark", "bookmark.fill", "link", "link.circle",
        // Education
        "book", "book.fill", "books.vertical.fill", "graduationcap",
        "pencil", "pencil.and.outline", "magazine",
        // Health
        "heart", "heart.fill", "medical.thermometer", "cross.case",
        "pill", "bandage",
        // Food / Drink
        "cup.and.saucer", "fork.knife", "takeoutbag.and.cup.and.straw",
        "mug", "carrot",
        // Energy
        "bolt", "bolt.fill", "bolt.circle", "powerplug", "powerplug.fill",
        "sparkles",
        // Misc
        "globe", "globe.americas", "globe.europe.africa", "globe.asia.australia",
        "clock", "clock.fill", "calendar", "calendar.badge.clock",
        "star", "star.fill", "flag", "flag.fill",
        "bell", "bell.fill", "bell.badge",
        "tag", "tag.fill", "camera", "camera.fill",
        "photo", "photo.on.rectangle", "rectangle.inset.filled.and.person.filled",
        "square.and.arrow.down", "square.and.arrow.up", "square.and.pencil",
        "tray", "tray.full", "archivebox", "trash",
        "magnifyingglass", "plus.magnifyingglass", "minus.magnifyingglass",
        "list.bullet", "list.clipboard", "checklist",
        "square.grid.3x3", "square.grid.3x3.fill.square",
        "app.connected.to.app.below.fill", "shared.with.you",
        // Apple / Brand
        "apple.logo", "applewatch", "appletv", "airpodspro",
        "ipad", "iphone", "ipodtouch",
        // Fun
        "gamecontroller", "puzzlepiece.extension", "puzzlepiece.extension.fill",
        "leaf", "leaf.fill", "flame", "flame.fill", "drop", "drop.fill",
    ]
}

#Preview {
    SFSymbolPicker(selectedIcon: .constant("globe"))
}
