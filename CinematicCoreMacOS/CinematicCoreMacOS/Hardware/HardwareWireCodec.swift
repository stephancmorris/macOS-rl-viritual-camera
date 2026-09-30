import Foundation

nonisolated enum HardwareRecordType: String, Codable, Sendable {
    case ping, heartbeat, disarm, stop, estop, resetEstop, arm, motion, quit
}
/// Flat strict command envelope. Times are seconds in the negotiated DEVICE clock.
/// Velocity is a reserved normalized [-1, 1] value, not a vendor motor unit.
nonisolated struct HardwareWireRecord: Codable, Equatable, Sendable {
    let v: Int
    let boot: String
    let session: String
    let seq: UInt64
    let type: HardwareRecordType
    let expiresDeviceTime: TimeInterval
    var velocity: Double? = nil
    var lease: TimeInterval? = nil
}

/// Bounded stream framing; JSON syntax/schema and duplicate-key checks precede effects.
/// Sequence/identity checks belong to the device so a batch is checked at effect time.
nonisolated struct HardwareWireCodec {
    let maximumBytes: Int
    static let maximumChunkBytes = 65_536
    static let maximumRecordsPerChunk = 64
    private var partial = Data()
    private var discarding = false
    var bufferedBytes: Int { partial.count }

    init(maximumBytes: Int = 1024) {
        self.maximumBytes = maximumBytes
    }
    mutating func reset() { partial.removeAll(keepingCapacity: false); discarding = false }
    func encode(_ record: HardwareWireRecord) throws -> Data {
        var data = try JSONEncoder().encode(record)
        data.append(0x0A)
        guard data.count <= maximumBytes else { throw HardwareRejection.oversize }
        return data
    }
    mutating func feed(_ data: Data) -> [Result<HardwareInboundRecord, HardwareRejection>] {
        guard (128...4096).contains(maximumBytes), data.count <= Self.maximumChunkBytes,
              data.reduce(0, { $0 + ($1 == 0x0A ? 1 : 0) }) <= Self.maximumRecordsPerChunk else {
            reset(); discarding = true
            return [.failure(.oversize)]
        }
        var results: [Result<HardwareInboundRecord, HardwareRejection>] = []
        for byte in data {
            if discarding {
                if byte == 0x0A { discarding = false }
                continue
            }
            if byte == 0x0A {
                results.append(decodeLine(partial))
                partial.removeAll(keepingCapacity: true)
            } else if partial.count >= maximumBytes - 1 {
                partial.removeAll(keepingCapacity: true); discarding = true
                results.append(.failure(.oversize))
            } else { partial.append(byte) }
        }
        return results
    }
    private func decodeLine(_ data: Data) -> Result<HardwareInboundRecord, HardwareRejection> {
        guard let keys = flatObjectKeys(data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawType = object["type"] as? String else { return .failure(.malformed) }
        if rawType == "hello" {
            guard keys == ["v", "type", "nonce"],
                  let hello = try? JSONDecoder().decode(HardwareHelloRequest.self, from: data),
                  hello.v > 0, UUID(uuidString: hello.nonce) != nil else { return .failure(.malformed) }
            return .success(.hello(hello))
        }
        guard let type = HardwareRecordType(rawValue: rawType) else { return .failure(.unknownType) }
        var expected: Set<String> = ["v", "boot", "session", "seq", "type", "expiresDeviceTime"]
        if type == .motion { expected.formUnion(["velocity", "lease"]) }
        guard keys == expected else { return .failure(.malformed) }
        guard let record = try? JSONDecoder().decode(HardwareWireRecord.self, from: data) else {
            return .failure(.invalidRange)
        }
        guard record.v > 0, UUID(uuidString: record.boot) != nil,
              UUID(uuidString: record.session) != nil, record.seq > 0,
              record.expiresDeviceTime.isFinite, record.expiresDeviceTime >= 0 else {
            return .failure(.invalidRange)
        }
        if type == .motion {
            guard let velocity = record.velocity, let lease = record.lease,
                  velocity.isFinite, abs(velocity) <= 1, lease.isFinite, lease > 0 else {
                return .failure(.invalidRange)
            }
        }
        return .success(.command(record))
    }

    /// Only flat JSON primitives are permitted. Decode escaped keys before uniqueness
    /// comparison ("v" and "\u0076" must not coexist). JSONDecoder checks value syntax.
    private func flatObjectKeys(_ data: Data) -> Set<String>? {
        let bytes = Array(data); var index = 0; var keys = Set<String>()
        func whitespace() {
            while index < bytes.count && [9, 13, 32].contains(bytes[index]) { index += 1 }
        }
        func stringToken() -> Data? {
            guard index < bytes.count, bytes[index] == 34 else { return nil }
            let start = index; index += 1
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 34 { return Data(bytes[start..<index]) }
                if byte == 92 { index += 1 }
            }
            return nil
        }
        whitespace()
        guard index < bytes.count, bytes[index] == 123 else { return nil }
        index += 1; whitespace()
        while index < bytes.count && bytes[index] != 125 {
            guard let token = stringToken(), let key = try? JSONDecoder().decode(String.self, from: token),
                  keys.insert(key).inserted else { return nil }
            whitespace()
            guard index < bytes.count, bytes[index] == 58 else { return nil }
            index += 1; whitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == 34 {
                guard let token = stringToken(), (try? JSONDecoder().decode(String.self, from: token)) != nil else { return nil }
            } else {
                let start = index
                while index < bytes.count && bytes[index] != 44 && bytes[index] != 125 {
                    if [34, 91, 93, 123, 58].contains(bytes[index]) { return nil }
                    index += 1
                }
                guard index > start else { return nil }
            }
            whitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == 125 { break }
            guard bytes[index] == 44 else { return nil }
            index += 1; whitespace()
            guard index < bytes.count, bytes[index] != 125 else { return nil }
        }
        guard index < bytes.count, bytes[index] == 125 else { return nil }
        index += 1; whitespace()
        return index == bytes.count ? keys : nil
    }
}
