import SwiftUI

// MARK: - Optimized History List View

struct OptimizedHistoryList: View {
    let items: [ClipItem]
    let selectedId: UUID?
    let onSelect: (ClipItem) -> Void
    let onCopy: (ClipItem) -> Void
    let onTogglePin: (ClipItem) -> Void
    let onDelete: (ClipItem) -> Void

    @State private var visibleItems: Set<UUID> = []
    @Namespace private var listNamespace

    var body: some View {
        ScrollViewReader { proxy in
            OptimizedList(spacing: 8) {
                ForEach(items) { item in
                    OptimizedHistoryItem(
                        item: item,
                        isSelected: selectedId == item.id,
                        isVisible: visibleItems.contains(item.id),
                        namespace: listNamespace,
                        onSelect: { onSelect(item) },
                        onCopy: { onCopy(item) },
                        onTogglePin: { onTogglePin(item) },
                        onDelete: { onDelete(item) }
                    )
                    .id(item.id)
                    .onAppear {
                        visibleItems.insert(item.id)
                    }
                    .onDisappear {
                        visibleItems.remove(item.id)
                    }
                }
            }
            .onChange(of: selectedId) { newId in
                if let id = newId {
                    withAnimation(.kippleSpring) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Optimized History Item

struct OptimizedHistoryItem: View {
    let item: ClipItem
    let isSelected: Bool
    let isVisible: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isPressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Content preview
                Text(item.content)
                    .lineLimit(2)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Action buttons (only show on hover for performance)
                if isHovered {
                    HStack(spacing: 4) {
                        ActionButton(
                            icon: "doc.on.doc",
                            action: onCopy,
                            tint: .blue
                        )
                        .transition(.scale.combined(with: .opacity))

                        ActionButton(
                            icon: item.isPinned ? "pin.slash" : "pin",
                            action: onTogglePin,
                            tint: .orange
                        )
                        .transition(.scale.combined(with: .opacity))

                        ActionButton(
                            icon: "trash",
                            action: onDelete,
                            tint: .red
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // Metadata
            HStack(spacing: 8) {
                if let appName = item.sourceApp {
                    Label(appName, systemImage: "app")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Text(item.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundGradient)
                .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 4 : 2)
        )
        .scaleEffect(isPressing ? 0.98 : 1.0)
        .animation(.kippleQuick, value: isPressing)
        .animation(.kippleSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            withAnimation(.kippleQuick) {
                isPressing = true
            }
            onSelect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressing = false
            }
        }
        .optimizedTransition(isActive: isVisible)
    }

    private var backgroundGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    let icon: String
    let action: () -> Void
    let tint: Color

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.kippleQuick) {
                isPressed = true
            }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(tint.opacity(0.1))
                )
                .scaleEffect(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.kippleBounce, value: isPressed)
    }
}

// MARK: - Empty State View

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No clipboard history")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Copy something to get started")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .smoothAppear()
    }
}

// MARK: - Section Header

struct OptimizedSectionHeader: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            // Show count badge only if there are items
            if count > 0 { // swiftlint:disable:this empty_count
                Text("\(count)")
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .animation(.kippleSpring, value: isExpanded)
    }
}
