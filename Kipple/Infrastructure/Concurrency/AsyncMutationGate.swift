import Foundation

/// Explicitly serializes operations across actor suspension points.
final class AsyncMutationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if occupied {
                waiters.append(continuation)
                lock.unlock()
            } else {
                occupied = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()
        let next = waiters.isEmpty ? nil : waiters.removeFirst()
        if next == nil { occupied = false }
        lock.unlock()
        next?.resume()
    }
}
