import SwiftUI
import SwiftData

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showingAddCategory = false
    @State private var editingCategory: Category?

    var body: some View {
        NavigationStack {
            List {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "folder",
                        description: Text("Add categories to organize your secrets.")
                    )
                } else {
                    ForEach(categories) { category in
                        HStack(spacing: 10) {
                            Image(systemName: category.icon)
                                .foregroundStyle(Color(hex: category.colorHex))
                                .frame(width: 20)

                            Text(category.name)
                                .font(.body)

                            Spacer()

                            Button("Edit", systemImage: "pencil") {
                                editingCategory = category
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteCategories)
                }
            }
            .listStyle(.inset)
            .navigationTitle("Manage Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") {
                        showingAddCategory = true
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                CategoryFormView()
            }
            .sheet(item: $editingCategory) { category in
                CategoryFormView(category: category)
            }
        }
        .frame(width: 400, height: 350)
    }

    private func deleteCategories(_ indexSet: IndexSet) {
        for index in indexSet {
            try? VaultService.deleteCategory(id: categories[index].id, context: modelContext)
        }
    }
}

struct CategoryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var category: Category?

    @State private var name = ""
    @State private var selectedIcon = "folder"
    @State private var selectedColorHex = "#007AFF"

    private let iconOptions = ["folder", "star", "heart", "bolt", "globe", "network",
                               "person", "building", "gear", "lock", "cloud", "externaldrive"]
    private let colorOptions = ["#007AFF", "#34C759", "#FF9500", "#FF3B30",
                                "#AF52DE", "#5856D6", "#FF2D55", "#00C7BE"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Name", text: $name)
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

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 8), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColorHex == hex ? Color.primary : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { selectedColorHex = hex }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(category != nil ? "Edit Category" : "New Category")
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
            .onAppear {
                if let category {
                    name = category.name
                    selectedIcon = category.icon
                    selectedColorHex = category.colorHex
                }
            }
        }
        .frame(width: 380, height: 400)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        do {
            if let existing = category {
                let data = CategoryData(id: existing.id, name: trimmedName, icon: selectedIcon, colorHex: selectedColorHex, sortOrder: existing.sortOrder)
                try VaultService.updateCategory(data: data, context: modelContext)
            } else {
                let maxOrder = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])))?.first?.sortOrder ?? 0
                let data = CategoryData(id: UUID(), name: trimmedName, icon: selectedIcon, colorHex: selectedColorHex, sortOrder: maxOrder + 1)
                try VaultService.createCategory(data: data, context: modelContext)
            }
            dismiss()
        } catch {
            // silently fail
        }
    }
}
