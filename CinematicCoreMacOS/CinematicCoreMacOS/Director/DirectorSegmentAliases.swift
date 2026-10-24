import CryptoKit
import Foundation

/// Stable opaque segment aliases without retaining every segment seen during
/// a show. The private session key is neither persisted nor exported.
final class DirectorSegmentAliases {
    private var key = SymmetricKey(size: .bits256)

    func renew() { key = SymmetricKey(size: .bits256) }

    func token(for segment: UUID) -> UUID {
        let message = Data(("alfie.director.segment.alias.v1:" + segment.uuidString).utf8)
        let bytes = Array(HMAC<SHA256>.authenticationCode(for: message, using: key).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
