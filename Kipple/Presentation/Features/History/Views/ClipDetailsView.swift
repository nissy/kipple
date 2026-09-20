import SwiftUI

struct ClipDetailsView: View {
    let itemID: UUID
    @ObservedObject private var adapter = ModernClipboardServiceAdapter.shared
    @ObservedObject private var categoryStore = UserCategoryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var errorMessage = ""

    init(item: ClipItem) {
        itemID = item.id
        _title = State(initialValue: item.title ?? "")
    }

    private var currentItem: ClipItem? {
        adapter.history.first { $0.id == itemID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item details").font(.headline)
            if let item = currentItem {
                TextField("Title", text: $title)
                LabeledContent("Source", value: item.sourceApp ?? "Unknown")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Categories").font(.caption).foregroundStyle(.secondary)
                    let categories = categoryStore.categories(for: item)
                    CategoryLabelsView(categories: categories.isEmpty ? [categoryStore.noneCategory()] : categories)
                }
                if let createdAt = item.metadata?.createdAt {
                    LabeledContent("Registered") { Text(createdAt, format: .dateTime) }
                }
                ScrollView {
                    Text(verbatim: String(item.content.prefix(4000)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                if item.characterCount > 4000 {
                    Text("Preview limited to 4,000 characters").font(.caption)
                }
            } else {
                Text("Item unavailable")
            }
            if !errorMessage.isEmpty { Text(LocalizedStringKey(errorMessage)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentItem == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        Task {
            do {
                try await ModernClipboardService.shared.updateDetails(id: itemID, title: title)
                dismiss()
            } catch {
                errorMessage = "Could not save. Check the title."
            }
        }
    }
}
