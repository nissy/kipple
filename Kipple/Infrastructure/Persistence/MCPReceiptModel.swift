import Foundation
import SwiftData

struct MCPStoredReceipt: Codable, Sendable {
    let key: String
    let digest: Data
    let receivedAt: Date
    var result: MCPReceipt

    func replay(digest: Data) -> MCPReceipt {
        guard self.digest == digest else { return .failure(result.requestId, code: "REQUEST_ID_CONFLICT") }
        var replay = result
        replay.replayed = true
        return replay
    }
}

@Model
final class MCPReceiptModel {
    @Attribute(.unique) var key: String
    var receivedAt: Date
    var data: Data

    init(record: MCPStoredReceipt) throws {
        key = record.key
        receivedAt = record.receivedAt
        data = try JSONEncoder().encode(record)
    }
}
