import AppKit

@MainActor
final class ApplicationTerminationController {
    enum Failure: Error {
        case saveFailed
        case timedOut
    }

    private let save: @MainActor () async throws -> Void
    private let reply: (Bool) -> Void
    private let onFailure: (Failure) -> Void
    private let timeout: Duration
    private var attempt: UUID?
    private var savingID: UUID?
    private var saveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        timeout: Duration = .seconds(10),
        save: @escaping @MainActor () async throws -> Void,
        reply: @escaping (Bool) -> Void,
        onFailure: @escaping (Failure) -> Void
    ) {
        self.timeout = timeout
        self.save = save
        self.reply = reply
        self.onFailure = onFailure
    }

    func requestTermination() -> NSApplication.TerminateReply {
        guard attempt == nil else { return .terminateLater }
        // A timed-out save may still be unwinding. Do not start another save over it.
        guard savingID == nil else { return .terminateCancel }
        let id = UUID()
        attempt = id
        savingID = id
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if savingID == id { savingID = nil; saveTask = nil }
            }
            do {
                try await save()
                finish(id, failure: nil)
            } catch {
                SystemDiagnostics.failure("saveBeforeTermination", error: error)
                finish(id, failure: .saveFailed)
            }
        }
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, attempt == id else { return }
            saveTask?.cancel()
            finish(id, failure: .timedOut)
        }
        return .terminateLater
    }

    private func finish(_ id: UUID, failure: Failure?) {
        guard attempt == id else { return }
        attempt = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        reply(failure == nil)
        if let failure { onFailure(failure) }
    }
}
