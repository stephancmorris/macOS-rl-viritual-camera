import Foundation

nonisolated struct HardwareWireRecord: Codable, Equatable, Sendable {
    let v: Int
    let session: String
    let seq: UInt64
    let type: String
    let payload: String?
}

/// One record per line, with a bound enforced before JSON decoding.
nonisolated struct HardwareWireCodec {
    let maximumBytes: Int
    let version: Int
    private(set) var session: String?
    private(set) var lastSequence: UInt64?

    mutating func begin(session: String) {
        self.session = session
        lastSequence = nil
    }
    func encode(_ record: HardwareWireRecord) throws -> Data {
        var data = try JSONEncoder().encode(record)
        guard data.count + 1 <= maximumBytes else { throw HardwareRejection.oversize }
        data.append(0x0A)
        return data
    }
    mutating func decode(_ data: Data) -> Result<HardwareWireRecord, HardwareRejection> {
        guard data.count <= maximumBytes else { return .failure(.oversize) }
        guard data.last == 0x0A, data.dropLast().allSatisfy({ $0 != 0x0A }) else {
            return .failure(.malformed)
        }
        guard let record = try? JSONDecoder().decode(HardwareWireRecord.self, from: data.dropLast()),
              !record.session.isEmpty, !record.type.isEmpty else { return .failure(.malformed) }
        guard record.v == version else { return .failure(.versionMismatch) }
        guard record.session == session else { return .failure(.late) }
        if let lastSequence {
            if record.seq == lastSequence { return .failure(.duplicate) }
            if record.seq < lastSequence { return .failure(.outOfOrder) }
        }
        lastSequence = record.seq
        return .success(record)
    }
}
