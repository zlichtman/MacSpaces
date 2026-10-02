import Foundation
import Darwin
import Security

/// Framed local-only sockets. Both peers authenticate the kernel audit token against
/// the expected signing requirement before either side reads application payloads.
enum LocalBridgeTransport {
    static func address(_ url: URL) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(url.path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw MacSpacesBridge.Failure("Bridge socket path is too long.") }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in destination.copyBytes(from: bytes) }
        return address
    }
    static func configure(_ fd: Int32) {
        var timeout = timeval(tv_sec: 5, tv_usec: 0), yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }
    static func authenticate(_ fd: Int32, requirement text: String) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { throw MacSpacesBridge.Failure("Bridge peer belongs to another user.") }
        var token = audit_token_t(), size = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
              size == MemoryLayout<audit_token_t>.size else { throw MacSpacesBridge.Failure("Cannot verify bridge peer identity.") }
        let data = withUnsafeBytes(of: token) { Data($0) }
        var code: SecCode?, requirement: SecRequirement?
        let flags = SecCSFlags(rawValue: 0)
        guard SecRequirementCreateWithString(text as CFString, flags, &requirement) == errSecSuccess,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit as String: data] as CFDictionary, flags, &code) == errSecSuccess,
              let code, let requirement,
              SecCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw MacSpacesBridge.Failure("The other app's signing identity could not be verified. Install a signed build of both apps.")
        }
    }
    static func exchange(_ data: Data, at url: URL = MacSpacesBridge.endpointURL) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MacSpacesBridge.Failure("Cannot open local bridge.") }
        defer { close(fd) }; configure(fd)
        var addr = try address(url)
        let result = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { throw MacSpacesBridge.Failure("Open an updated Tsukumo app, then connect again.") }
        try authenticate(fd, requirement: MacSpacesBridge.serverRequirement)
        try writeFrame(data, to: fd)
        return try readFrame(from: fd)
    }
    static func readFrame(from fd: Int32) throws -> Data {
        let header = try readExactly(4, from: fd)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count <= MacSpacesBridge.maxBytes else { throw MacSpacesBridge.Failure("Bridge message exceeds the size limit.", uncertain: true) }
        return try readExactly(count, from: fd)
    }
    static func writeFrame(_ data: Data, to fd: Int32) throws {
        guard data.count <= MacSpacesBridge.maxBytes else { throw MacSpacesBridge.Failure("Bridge message exceeds the size limit.") }
        let n = UInt32(data.count)
        var frame = Data([UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)])
        frame.append(data)
        try frame.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if sent < 0 && errno == EINTR { continue }
                guard sent > 0 else { throw MacSpacesBridge.Failure("Bridge disconnected. Check the conversation before sending again.", uncertain: true) }
                offset += sent
            }
        }
    }
    private static func readExactly(_ count: Int, from fd: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                let received = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
                if received < 0 && errno == EINTR { continue }
                guard received > 0 else { throw MacSpacesBridge.Failure("Bridge reply unavailable. Delivery may be uncertain; check the conversation before sending again.", uncertain: true) }
                offset += received
            }
        }
        return data
    }
}

final class LocalBridgeListener {
    /// Where a connection stopped before a reply was written. Carries no payload, path or
    /// identity details, so it is safe for diagnostics.
    enum FailureStage: String { case identity, request, reply, write }
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.bridge")
    private var source: DispatchSourceRead?
    private var endpoint: (url: URL, device: dev_t, inode: ino_t)?
    /// Called on the listener queue for each connection that ended without a reply.
    var onFailure: ((FailureStage) -> Void)?
    func start(at url: URL = MacSpacesBridge.endpointURL, handle: @escaping (Data, @escaping (Data) -> Void) -> Void) throws {
        guard source == nil else { return }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MacSpacesBridge.Failure("Cannot create bridge socket.") }
        do {
            // Existing endpoints are never removed: a second app instance must not steal an active listener.
            // A stale socket is detected by a failed connect, then replaced.
            if FileManager.default.fileExists(atPath: url.path) {
                let probe = socket(AF_UNIX, SOCK_STREAM, 0)
                var addr = try LocalBridgeTransport.address(url)
                let result = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
                let failure = errno; close(probe)
                guard result != 0 else { throw MacSpacesBridge.Failure("A bridge is already running.") }
                guard failure == ECONNREFUSED else { throw MacSpacesBridge.Failure("Unexpected bridge endpoint.") }
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_uid == geteuid(), (info.st_mode & S_IFMT) == S_IFSOCK else { throw MacSpacesBridge.Failure("Unexpected bridge endpoint.") }
                guard unlink(url.path) == 0 else { throw MacSpacesBridge.Failure("Cannot replace stale bridge endpoint.") }
            }
            var addr = try LocalBridgeTransport.address(url)
            let result = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard result == 0, chmod(url.path, 0o600) == 0, listen(fd, 8) == 0 else { throw MacSpacesBridge.Failure("Cannot listen for MacSpaces.") }
            var bound = stat()
            guard lstat(url.path, &bound) == 0 else { throw MacSpacesBridge.Failure("Cannot listen for MacSpaces.") }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK); _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            let failed = onFailure
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setCancelHandler { close(fd) }
            source.setEventHandler {
                let peer = accept(fd, nil, nil)
                guard peer >= 0 else { return }
                defer { close(peer) }
                // Accepted sockets inherit the listener's O_NONBLOCK on Darwin. Blocking mode makes
                // the 5-second SO_RCVTIMEO/SO_SNDTIMEO apply instead of failing with EAGAIN while the
                // client is still verifying this server's signature.
                _ = fcntl(peer, F_SETFL, fcntl(peer, F_GETFL) & ~O_NONBLOCK)
                LocalBridgeTransport.configure(peer)
                var stage = FailureStage.identity
                do {
                    try LocalBridgeTransport.authenticate(peer, requirement: MacSpacesBridge.clientRequirement)
                    stage = .request
                    let data = try LocalBridgeTransport.readFrame(from: peer)
                    stage = .reply
                    let waiter = DispatchSemaphore(value: 0)
                    let box = BridgeReplyBox()
                    handle(data) { box.set($0); waiter.signal() }
                    guard waiter.wait(timeout: .now() + 5) == .success, let reply = box.get() else { failed?(.reply); return }
                    stage = .write
                    try LocalBridgeTransport.writeFrame(reply, to: peer)
                } catch { failed?(stage) /* Close without reading further. */ }
            }
            endpoint = (url, bound.st_dev, bound.st_ino)
            self.source = source; source.resume()
        } catch { close(fd); throw error }
    }
    var isListening: Bool { source != nil }
    /// Stops accepting and removes the endpoint only if it is still the one this listener bound,
    /// so a leftover path never looks like a running bridge and another listener's is kept.
    func stop() {
        source?.cancel(); source = nil
        if let endpoint {
            var info = stat()
            if lstat(endpoint.url.path, &info) == 0, info.st_dev == endpoint.device, info.st_ino == endpoint.inode { unlink(endpoint.url.path) }
        }
        endpoint = nil
    }
    deinit { stop() }
}
private final class BridgeReplyBox {
    private let lock = NSLock()
    private var value: Data?
    func set(_ data: Data) { lock.lock(); defer { lock.unlock() }; value = data }
    func get() -> Data? { lock.lock(); defer { lock.unlock() }; return value }
}
