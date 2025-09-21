import SwiftUI

// MARK: - Animation Extensions

extension Animation {
    // Standard animations for the app
    static let kippleSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let kippleFade = Animation.easeInOut(duration: 0.2)
    static let kippleQuick = Animation.easeOut(duration: 0.15)
    static let kippleBounce = Animation.interpolatingSpring(stiffness: 300, damping: 20)
}

// MARK: - View Modifiers for Performance

struct LazyLoadModifier: ViewModifier {
    @State private var hasAppeared = false
    let delay: Double

    func body(content: Content) -> some View {
        Group {
            if hasAppeared {
                content
            } else {
                Color.clear
                    .onAppear {
                        withAnimation(.kippleFade.delay(delay)) {
                            hasAppeared = true
                        }
                    }
            }
        }
    }
}

struct OptimizedTransition: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1.0 : 0.95)
            .opacity(isActive ? 1.0 : 0)
            .animation(.kippleSpring, value: isActive)
    }
}

struct SmoothListTransition: ViewModifier {
    func body(content: Content) -> some View {
        content
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )
    }
}

// MARK: - View Extensions

extension View {
    func lazyLoad(delay: Double = 0) -> some View {
        modifier(LazyLoadModifier(delay: delay))
    }

    func optimizedTransition(isActive: Bool) -> some View {
        modifier(OptimizedTransition(isActive: isActive))
    }

    func smoothListTransition() -> some View {
        modifier(SmoothListTransition())
    }

    func kippleAnimation<V: Equatable>(_ value: V) -> some View {
        animation(.kippleSpring, value: value)
    }
}

// MARK: - Namespace Extensions for Smooth Transitions

struct NamespaceEnvironmentKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var animationNamespace: Namespace.ID? {
        get { self[NamespaceEnvironmentKey.self] }
        set { self[NamespaceEnvironmentKey.self] = newValue }
    }
}

// MARK: - Performance Optimized List

struct OptimizedList<Content: View>: View {
    let content: Content
    let spacing: CGFloat

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: spacing) {
                content
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Smooth Appear/Disappear Effects

struct SmoothAppear: ViewModifier {
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.8)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.kippleSpring) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func smoothAppear() -> some View {
        modifier(SmoothAppear())
    }
}

// MARK: - Debounced Updates

class DebouncedState<Value>: ObservableObject {
    @Published var value: Value
    @Published var debouncedValue: Value

    private var debounceTimer: Timer?
    private let delay: TimeInterval

    init(initialValue: Value, delay: TimeInterval = 0.3) {
        self.value = initialValue
        self.debouncedValue = initialValue
        self.delay = delay
    }

    func update(_ newValue: Value) {
        value = newValue

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            DispatchQueue.main.async {
                self.debouncedValue = newValue
            }
        }
    }
}

// MARK: - Conditional Animation

struct ConditionalAnimation: ViewModifier {
    let condition: Bool
    let animation: Animation

    func body(content: Content) -> some View {
        if condition {
            content.animation(animation, value: condition)
        } else {
            content.animation(nil, value: condition)
        }
    }
}

extension View {
    func animation(when condition: Bool, animation: Animation = .kippleSpring) -> some View {
        modifier(ConditionalAnimation(condition: condition, animation: animation))
    }
}
