import AppKit
import SwiftUI

struct CategoryFilterControl: View {
    @Binding var selection: CategoryFilter
    let onOpenManager: (() -> Void)?
    @ObservedObject private var store = UserCategoryStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.categoryPopoverChanged) private var presentationChanged
    @State private var isPresented = false
    @State private var reorder: FilterReorder?

    private static let rowStride = MainViewMetrics.HistoryRows.height + MainViewMetrics.HistoryRows.spacing

    private var choices: [UserCategory] {
        store.orderedForFiltering().filter { store.isFilterEnabled($0) || selection.ids.contains($0.id) }
    }

    var body: some View {
        let choices = self.choices
        let visibleIDs = choices.map(\.id)

        VStack(spacing: 0) {
            if !choices.isEmpty {
                Divider()
                    .padding(.horizontal, 4)
                    .frame(height: MainViewMetrics.HistoryColumns.toolbarBottomPadding
                           + MainViewMetrics.HistoryRows.verticalPadding)

                ScrollView {
                    LazyVStack(spacing: MainViewMetrics.HistoryRows.spacing) {
                        ForEach(Array(choices.enumerated()), id: \.element.id) { index, category in
                            categoryButton(category, index: index, visibleIDs: visibleIDs)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .popover(isPresented: $isPresented, attachmentAnchor: .point(.topTrailing), arrowEdge: .trailing) {
            advancedFilters
        }
        .onChange(of: isPresented) { _, presented in if !presented { presentationChanged(nil, false) } }
        .onDisappear {
            reorder = nil
            if isPresented { presentationChanged(nil, false) }
        }
        .onChange(of: visibleIDs) { _, _ in reorder = nil }
        .onChange(of: store.categories) { _, _ in
            selection.ids.formIntersection(Set(store.all().map(\.id)))
        }
    }

    private func categoryButton(_ category: UserCategory, index: Int, visibleIDs: [UUID]) -> some View {
        let isMoving = reorder?.source == index
        let select = { selection.toggleSingleSelection(category.id) }

        return HistoryFilterButton(
            systemName: store.iconName(for: category),
            label: categoryLabel(category),
            isActive: selection.ids.contains(category.id),
            action: select
        )
        .overlay {
            if visibleIDs.count > 1 {
                FilterReorderInput(onClick: select) { translation in
                    reorder = FilterReorder(source: index, translation: translation, count: visibleIDs.count,
                                            stride: Self.rowStride)
                } onFinish: { translation in
                    reorder = nil
                    guard let translation, choices.map(\.id) == visibleIDs else { return }
                    let move = FilterReorder(source: index, translation: translation, count: visibleIDs.count,
                                             stride: Self.rowStride)
                    store.moveFilter(category.id, to: visibleIDs[move.target], among: visibleIDs)
                }
            }
        }
        .opacity(isMoving ? 0.75 : 1)
        .offset(y: reorder?.offset(at: index, stride: Self.rowStride) ?? 0)
        .zIndex(isMoving ? 1 : 0)
        .contextMenu {
            Button("Filter by categories", action: openAdvancedFilters)
        }
        .accessibilityAction(named: Text("Filter by categories"), openAdvancedFilters)
    }

    private struct FilterReorder {
        let source: Int
        let target: Int
        let translation: CGFloat

        init(source: Int, translation: CGFloat, count: Int, stride: CGFloat) {
            self.source = source
            let lowerBound = -CGFloat(source) * stride
            let upperBound = CGFloat(count - 1 - source) * stride
            self.translation = min(max(translation, lowerBound), upperBound)
            target = source + Int((self.translation / stride).rounded())
        }

        func offset(at index: Int, stride: CGFloat) -> CGFloat {
            if index == source { return translation }
            if source < index && index <= target { return -stride }
            if target <= index && index < source { return stride }
            return 0
        }
    }

    private func categoryLabel(_ category: UserCategory) -> Text {
        if store.isBuiltIn(category.id) { return Text(LocalizedStringKey(category.name)) }
        return Text(verbatim: category.name)
    }

    private func openAdvancedFilters() {
        presentationChanged(nil, true)
        isPresented = true
    }

    private var advancedFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filter by categories").font(.headline)
                Spacer()
                Button("Clear") { selection.select(nil) }.disabled(selection.ids.isEmpty)
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
                        )) {
                            Label {
                                categoryLabel(category)
                            } icon: {
                                Image(systemName: store.iconName(for: category))
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }.frame(maxHeight: 280)
            Text("Search and pinned filters apply together.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Manage Categories…") { onOpenManager?(); isPresented = false }
        }.padding(16).frame(width: 300)
    }
}

private struct FilterReorderInput: NSViewRepresentable {
    let onClick: () -> Void
    let onMove: (CGFloat) -> Void
    let onFinish: (CGFloat?) -> Void

    func makeNSView(context: Context) -> FilterReorderView {
        FilterReorderView()
    }

    func updateNSView(_ view: FilterReorderView, context: Context) {
        view.input = self
    }

    static func dismantleNSView(_ view: FilterReorderView, coordinator: ()) {
        view.stopTracking()
    }
}

private final class FilterReorderView: NSView {
    private static let dragThreshold: CGFloat = 6

    var input: FilterReorderInput?
    private var startLocation: NSPoint?
    private var isReordering = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
              !event.modifierFlags.contains(.control) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        startLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation else { return }
        let location = event.locationInWindow
        let translationY = startLocation.y - location.y
        let distance = max(abs(translationY), abs(location.x - startLocation.x))
        guard isReordering || distance >= Self.dragThreshold else { return }
        isReordering = true
        input?.onMove(translationY)
    }

    override func mouseUp(with event: NSEvent) {
        guard let startLocation else { return }
        let wasReordering = isReordering
        stopTracking()
        if wasReordering {
            input?.onFinish(startLocation.y - event.locationInWindow.y)
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            input?.onClick()
        }
    }

    override func mouseCancelled(with event: NSEvent) {
        stopTracking()
        input?.onFinish(nil)
    }

    func stopTracking() {
        startLocation = nil
        isReordering = false
    }
}

struct HistoryFilterButton: View {
    let systemName: String
    let label: Text
    let isActive: Bool
    var iconFont = MainViewMetrics.HistoryFilterSidebar.iconFont
    var rotation: Angle = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(iconFont)
                .foregroundStyle(KippleButtonAppearance.foreground(isActive: isActive))
                .rotationEffect(rotation)
                .frame(width: MainViewMetrics.HistoryFilterSidebar.width,
                       height: MainViewMetrics.HistoryFilterSidebar.width)
                .background(KippleButtonAppearance.compactFill(isActive: isActive), in: Circle())
                .frame(height: MainViewMetrics.HistoryRows.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
