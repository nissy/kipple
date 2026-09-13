import Foundation
import Darwin

/// Bounded length-prefixed messages over a same-user Unix socket.
enum LocalMCPTransport {
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw MCPFailure.unavailable
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    static func withAddress<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>) -> T) -> T {
        withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1, body)
        }
    }

    static func configure(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK) }
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    static func readFrame(_ descriptor: Int32) throws -> Data {
        let header = try readExactly(descriptor, count: 4)
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= MCPProtocolConfig.maxFrameBytes else { throw MCPFailure.tooLarge }
        return try readExactly(descriptor, count: Int(size))
    }

    static func writeFrame(_ data: Data, to descriptor: Int32) throws {
        guard data.count <= MCPProtocolConfig.maxFrameBytes else { throw MCPFailure.tooLarge }
        var size = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(data)
        try frame.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw MCPFailure.invalidInput }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw MCPFailure.unavailable }
                offset += written
            }
        }
    }

    private static func readExactly(_ descriptor: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { throw MCPFailure.invalidInput }
            var offset = 0
            while offset < count {
                let received = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if received < 0 && errno == EINTR { continue }
                guard received > 0 else { throw MCPFailure.unavailable }
                offset += received
            }
        }
        return data
    }

    static func request(_ data: Data, path: String) throws -> Data {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MCPFailure.unavailable }
        defer { close(descriptor) }
        configure(descriptor)
        var endpoint = try address(path)
        let connected = withAddress(&endpoint) {
            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
        guard connected == 0 else { throw MCPFailure.unavailable }
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid() else {
            throw MCPFailure.unavailable
        }
        try writeFrame(data, to: descriptor)
        return try readFrame(descriptor)
    }
}
