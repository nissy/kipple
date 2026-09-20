import SwiftUI

struct CategoryFilterControl: View {
    @Binding var selection: CategoryFilter
    let onOpenManager: (() -> Void)?
    @ObservedObject private var store = UserCategoryStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.categoryPopoverChanged) private var presentationChanged
    @State private var isPresented = false

    private var choices: [UserCategory] {
        store.all().filter { store.isFilterEnabled($0) || selection.ids.contains($0.id) }
    }

    private var selectedCategoryNames: String {
        let selected = choices.filter { selection.ids.contains($0.id) }
        return selected.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        Button {
            presentationChanged(nil, true)
            isPresented = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(MainViewMetrics.HistoryFilterIcon.categoryFont)
                .frame(
                    width: MainViewMetrics.HistoryColumns.controlColumnWidth,
                    height: MainViewMetrics.HistoryColumns.controlColumnWidth,
                    alignment: .center
                )
                .background(selection.ids.isEmpty ? Color.clear : Color.accentColor.opacity(0.15), in: Circle())
                .overlay(alignment: .bottomTrailing) {
                    if !selection.ids.isEmpty {
                        Text("\(selection.ids.count)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(2)
                            .background(.background, in: Circle())
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Filter by categories"))
        .accessibilityValue(Text(verbatim: selectedCategoryNames))
        .help(Text("Filter by categories"))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Filter by categories").font(.headline)
                    Spacer()
                    Button("Clear") { selection.ids = [] }.disabled(selection.ids.isEmpty)
                }
                if selection.ids.count > 1 {
                    Picker("Match", selection: $selection.match) {
                        Text("Match all").tag(CategoryFilter.Match.all)
                        Text("Match any").tag(CategoryFilter.Match.any)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(choices) { category in
                            Toggle(isOn: Binding(
                                get: { selection.ids.contains(category.id) },
                                set: { _ in selection.toggle(category.id) }
                            )) { Label(category.name, systemImage: store.iconName(for: category)) }
                                .toggleStyle(.checkbox)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
                }.frame(maxHeight: 280)
                Text("Search and pinned filters apply together.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Button("Manage Categories…") { onOpenManager?(); isPresented = false }
            }.padding(16).frame(width: 300)
        }
        .onChange(of: isPresented) { _, presented in if !presented { presentationChanged(nil, false) } }
        .onDisappear { if isPresented { presentationChanged(nil, false) } }
        .onChange(of: store.categories) { _, _ in
            selection.ids.formIntersection(Set(store.all().map(\.id)))
        }
    }
}
