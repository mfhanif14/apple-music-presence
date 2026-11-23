import Darwin
import Foundation

/// Minimal Discord RPC client over the local IPC socket ($TMPDIR/discord-ipc-N).
final class DiscordIPC {
    private let clientID: String
    private var fd: Int32 = -1

    var isConnected: Bool { fd >= 0 }

    init(clientID: String) {
        self.clientID = clientID
    }

    @discardableResult
    func connect() -> Bool {
        disconnect()
        let base = NSTemporaryDirectory() as NSString

        for index in 0..<10 {
            let path = base.appendingPathComponent("discord-ipc-\(index)")
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let sock = socket(AF_UNIX, SOCK_STREAM, 0)
            guard sock >= 0 else { continue }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(path.utf8) + [0]
            guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                Darwin.close(sock)
                continue
            }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else {
                Darwin.close(sock)
                continue
            }

            var one: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            fd = sock

            // Handshake: Discord answers with a READY frame (op 1), or CLOSE (op 2) if the client ID is wrong.
            if writeFrame(op: 0, json: ["v": 1, "client_id": clientID]),
               let reply = readFrame(), reply.op == 1 {
                return true
            }
            disconnect()
        }
        return false
    }

    func disconnect() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    /// Sends SET_ACTIVITY. Pass nil to clear the presence. Returns false if the connection was lost.
    func setActivity(_ activity: [String: Any]?) -> Bool {
        let activityValue: Any = activity.map { $0 as Any } ?? NSNull()
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": activityValue,
            ],
            "nonce": UUID().uuidString,
        ]
        guard writeFrame(op: 1, json: payload) else { return false }

        // Read the reply (answer pings if Discord sends any).
        for _ in 0..<3 {
            guard let reply = readFrame() else { return false }
            switch reply.op {
            case 1:
                if let event = reply.json?["evt"] as? String, event == "ERROR" {
                    print("Discord error:", reply.json?["data"] ?? "")
                }
                return true
            case 2:
                disconnect()
                return false
            case 3:
                _ = writeFrame(op: 4, json: reply.json ?? [:])
            default:
                continue
            }
        }
        return isConnected
    }

    // MARK: - Framing: [op: UInt32 LE][length: UInt32 LE][JSON]

    private func writeFrame(op: UInt32, json: Any) -> Bool {
        guard fd >= 0, let body = try? JSONSerialization.data(withJSONObject: json) else { return false }

        var frame = Data()
        withUnsafeBytes(of: op.littleEndian) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(body)

        let socketFD = fd
        let success = frame.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(socketFD, base + offset, buffer.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
        if !success { disconnect() }
        return success
    }

    private func readFrame() -> (op: UInt32, json: [String: Any]?)? {
        guard let header = readExactly(8) else {
            disconnect()
            return nil
        }
        let op = UInt32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) })
        let length = Int(UInt32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }))
        guard length < 1_000_000, let body = readExactly(length) else {
            disconnect()
            return nil
        }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        return (op, json)
    }

    private func readExactly(_ count: Int) -> Data? {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        let socketFD = fd
        let success = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < count {
                let received = Darwin.read(socketFD, base + offset, count - offset)
                if received <= 0 { return false }
                offset += received
            }
            return true
        }
        return success ? data : nil
    }
}
