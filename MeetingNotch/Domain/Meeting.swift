import Foundation

struct Meeting: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var meetingURL: URL?
    var calendarIdentifier: String?
    var externalIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        meetingURL: URL? = nil,
        calendarIdentifier: String? = nil,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.meetingURL = meetingURL
        self.calendarIdentifier = calendarIdentifier
        self.externalIdentifier = externalIdentifier
    }
}

enum MeetingStableIdentifier {
    static func uuid(for value: String) -> UUID {
        var high: UInt64 = 0xcbf29ce484222325
        var low: UInt64 = 0x84222325cbf29ce4
        for byte in value.utf8 {
            high ^= UInt64(byte)
            high &*= 0x100000001b3
            low ^= UInt64(byte) &+ 0x9e
            low &*= 0x100000001b3
        }

        var bytes = withUnsafeBytes(of: high.bigEndian, Array.init)
        bytes.append(contentsOf: withUnsafeBytes(of: low.bigEndian, Array.init))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
