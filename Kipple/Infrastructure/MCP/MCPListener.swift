import Foundation
import Darwin

final class MCPListener: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var generation = UUID()
    private let queue = DispatchQueue(label: "com.nissy.Kipple.mcp-listener", qos: .utility)

    func start(path: String, handler: @escaping @Sendable (Data) async -> Data) throws {
        stop()
        var address = try LocalMCPTransport.address(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MCPFailure.unavailable }
        unlink(path)
        let bound = LocalMCPTransport.withAddress(&address) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 8) == 0,
              fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            close(descriptor)
            throw MCPFailure.unavailable
        }
        lock.lock()
        listener = descriptor
        let session = generation
        lock.unlock()
        queue.async { [weak self] in self?.acceptRequests(descriptor, session: session, handler: handler) }
    }

    func stop() {
        lock.lock()
        let descriptor = listener
        listener = -1
        generation = UUID()
        lock.unlock()
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
        }
    }

    private func isActive(_ session: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == session && listener >= 0
    }

    private func waitForClient(_ descriptor: Int32, session: UUID) -> Int32 {
        // Closing a descriptor while another thread enters accept can reuse its fd.
        // Keep ownership on this queue and bound the wait so stop always completes.
        while isActive(session) {
            var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&event, 1, 250)
            guard isActive(session) else { return -1 }
            if ready < 0 && errno != EINTR { return -1 }
            if ready <= 0 { continue }
            let client = accept(descriptor, nil, nil)
            if client < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            return client
        }
        return -1
    }

    private func acceptRequests(
        _ descriptor: Int32,
        session: UUID,
        handler: @escaping @Sendable (Data) async -> Data
    ) {
        defer { close(descriptor) }
        while isActive(session) {
            let client = waitForClient(descriptor, session: session)
            guard client >= 0 else { return }
            LocalMCPTransport.configure(client)
            var uid = uid_t(0)
            var gid = gid_t(0)
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }
            do {
                let data = try LocalMCPTransport.readFrame(client)
                guard isActive(session) else { close(client); return }
                let completion = DispatchSemaphore(value: 0)
                Task {
                    let response = await handler(data)
                    try? LocalMCPTransport.writeFrame(response, to: client)
                    close(client)
                    completion.signal()
                }
                completion.wait()
            } catch {
                close(client)
            }
        }
    }
}
