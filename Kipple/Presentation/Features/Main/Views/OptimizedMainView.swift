import SwiftUI

struct OptimizedMainView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var selectedHistoryItem: ClipItem?
    @State private var isShowingCopiedNotification = false
    @State private var currentNotificationType: CopiedNotificationView.NotificationType = .copied
    @State private var isAlwaysOnTop = false
    @AppStorage("editorSectionHeight") private var editorSectionHeight: Double = 250
    @AppStorage("historySectionHeight") private var historySectionHeight: Double = 300
    @ObservedObject private var appSettings = AppSettings.shared

    // Performance optimization
    @State private var searchText = ""
    @Namespace private var mainNamespace

    let onClose: (() -> Void)?
    let onAlwaysOnTopChanged: ((Bool) -> Void)?
    let onOpenSettings: (() -> Void)?

    init(
        onClose: (() -> Void)? = nil,
        onAlwaysOnTopChanged: ((Bool) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onAlwaysOnTopChanged = onAlwaysOnTopChanged
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            titleBar
                .smoothAppear()

            // Control Section
            controlSection
                .padding(.horizontal)
                .padding(.vertical, 8)
                .animation(.kippleQuick, value: viewModel.searchText)

            Divider()

            // Main Content with optimized layout
            GeometryReader { _ in
                VStack(spacing: 0) {
                    // History Section with lazy loading
                    historySection
                        .frame(height: historySectionHeight)
                        .animation(.kippleSpring, value: historySectionHeight)

                    // Resizable divider
                    Divider()
                        .background(Color.gray.opacity(0.3))
                        .frame(height: 1)

                    // Editor Section with animation
                    editorSection
                        .frame(maxHeight: .infinity)
                        .animation(.kippleSpring, value: editorSectionHeight)
                }
            }

            // Status Bar
            statusBar
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
        }
        .frame(width: appSettings.windowWidth, height: appSettings.windowHeight)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(notificationOverlay)
        .environment(\.animationNamespace, mainNamespace)
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Text("Kipple")
                .font(.headline)

            Spacer()

            HStack(spacing: 8) {
                // Pin toggle
                Button(action: { isAlwaysOnTop.toggle() }) {
                    Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                        .foregroundColor(isAlwaysOnTop ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .animation(.kippleBounce, value: isAlwaysOnTop)

                // Settings
                if let onOpenSettings = onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Close
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Control Section

    private var controlSection: some View {
        HStack(spacing: 12) {
            // Search field with debouncing
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
            )

            // Filter buttons
            filterButtons
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var filterButtons: some View {
        HStack(spacing: 4) {
            FilterButton(
                icon: "link",
                isActive: viewModel.showOnlyURLs
            ) { viewModel.showOnlyURLs.toggle() }

            FilterButton(
                icon: "pin",
                isActive: !viewModel.pinnedHistory.isEmpty
            ) { /* Toggle pinned view */ }
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Group {
            if viewModel.filteredHistory.isEmpty {
                EmptyHistoryView()
            } else {
                OptimizedHistoryList(
                    items: viewModel.filteredHistory,
                    selectedId: selectedHistoryItem?.id,
                    onSelect: handleItemSelection,
                    onCopy: handleCopy,
                    onTogglePin: handleTogglePin,
                    onDelete: handleDelete
                )
            }
        }
        .animation(.kippleSpring, value: viewModel.filteredHistory.count)
    }

    // MARK: - Editor Section

    private var editorSection: some View {
        VStack(spacing: 0) {
            // Editor header
            HStack {
                Label("Editor", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !viewModel.editorText.isEmpty {
                    HStack(spacing: 4) {
                        Button("Copy", action: copyEditor)
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.accentColor)

                        Button("Clear") { viewModel.clearEditor() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Editor content
            TextEditor(text: $viewModel.editorText)
                .font(.system(size: 13, design: .monospaced))
                .padding(4)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(4)
                .animation(.kippleQuick, value: viewModel.editorText)
        }
        .padding(8)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("\(viewModel.filteredHistory.count) items")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            if !viewModel.pinnedHistory.isEmpty {
                Label("\(viewModel.pinnedHistory.count) pinned", systemImage: "pin")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Notification Overlay

    private var notificationOverlay: some View {
        VStack {
            if isShowingCopiedNotification {
                CopiedNotificationView(
                    showNotification: $isShowingCopiedNotification,
                    notificationType: currentNotificationType
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.kippleBounce)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.kippleFade) {
                            isShowingCopiedNotification = false
                        }
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func handleItemSelection(_ item: ClipItem) {
        withAnimation(.kippleQuick) {
            selectedHistoryItem = item
        }

        if viewModel.isEditorInsertEnabled() && viewModel.shouldInsertToEditor() {
            viewModel.insertToEditor(content: item.content)
        } else {
            handleCopy(item)
        }
    }

    private func handleCopy(_ item: ClipItem) {
        viewModel.copyToClipboard(item)
        showNotification(type: .copied)
    }

    private func handleTogglePin(_ item: ClipItem) {
        Task {
            await viewModel.togglePin(for: item)
        }
    }

    private func handleDelete(_ item: ClipItem) {
        Task {
            await viewModel.deleteItem(item)
        }
    }

    private func copyEditor() {
        viewModel.copyEditor()
        showNotification(type: .copied)
    }

    private func showNotification(type: CopiedNotificationView.NotificationType) {
        currentNotificationType = type
        withAnimation(.kippleBounce) {
            isShowingCopiedNotification = true
        }
    }
}

// MARK: - Filter Button Component

struct FilterButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(isActive ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.accentColor : Color.gray.opacity(0.2))
                )
        }
        .buttonStyle(.plain)
        .animation(.kippleSpring, value: isActive)
    }
}

// MARK: - NSCursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
