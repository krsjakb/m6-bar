import Foundation

struct BatteryReading: Equatable, Sendable {
    let percent: Int
    let charging: Bool
    let dpi: Int?
    let pollingRate: Int?
}

enum M6Protocol {
    static let vendorID = 0x3434
    static let receiverPID = 0xD029
    static let mousePID = 0xD060

    /// IOHID includes the report ID; WebHID (the reference implementation) does not.
    static func payload(_ bytes: [UInt8], reportID: UInt32) -> [UInt8]? {
        let expected = reportID == 0xB4 ? 64 : reportID == 0xB6 ? 21 : 0
        guard expected > 0 else { return nil }
        if bytes.count == expected, bytes.first == UInt8(reportID) {
            return Array(bytes.dropFirst())
        }
        if bytes.count == expected - 1 { return bytes }
        return nil
    }

    static func battery(_ p: [UInt8], wireless: Bool) -> BatteryReading? {
        guard p.count == 63, p[0] == 6 else { return nil }
        let percent = Int(p[19] & 0x7F)
        guard percent <= 100 else { return nil }
        let stage = Int(p[wireless ? 3 : 2] & 0x0F)
        let count = Int(p[16])
        let dpi: Int? = stage < min(count, 5) ? Int(p[5 + stage * 2]) | Int(p[6 + stage * 2]) << 8 : nil
        let pollingStage = Int(p[wireless ? 3 : 2] >> 4)
        let rateIndex = pollingStage < 6 ? Int(p[43 + pollingStage]) : -1
        let rates = [125, 500, 1000] // Exact d060 model definition, not the M6 8K.
        return BatteryReading(percent: percent, charging: p[19] & 0x80 != 0,
                              dpi: dpi.flatMap { (1...26000).contains($0) ? $0 : nil },
                              pollingRate: rates.indices.contains(rateIndex) ? rates[rateIndex] : nil)
    }

    static func pairedMouse(_ p: [UInt8]) -> Bool? {
        guard p.count == 20, p[0] == 3, p[1] <= 3 else { return nil }
        for i in 0..<Int(p[1]) {
            let n = 2 + i * 5
            let vid = Int(p[n]) | Int(p[n + 1]) << 8
            let pid = Int(p[n + 2]) | Int(p[n + 3]) << 8
            if vid == vendorID && pid == mousePID { return p[n + 4] == 1 }
        }
        return false
    }

    static func firmware(_ p: [UInt8]) -> String? {
        guard p.count == 20, p[0] == 2,
              Int(p[3]) | Int(p[4]) << 8 == vendorID,
              Int(p[5]) | Int(p[6]) << 8 == mousePID else { return nil }
        return "\(p[8]).\(p[7] >> 4).\(p[7] & 15)"
    }
}

struct BatterySample: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let percent: Int
    let charging: Bool
    let session: UUID

    init(date: Date, percent: Int, charging: Bool, session: UUID) {
        self.id = UUID()
        self.date = date
        self.percent = percent
        self.charging = charging
        self.session = session
    }
}

enum RuntimeEstimate {
    /// Requires a continuous observed discharge, never a manufacturer's advertised runtime.
    static func hours(samples: [BatterySample], now: Date, latestObservation: Date? = nil) -> ClosedRange<Int>? {
        let observation = latestObservation ?? samples.last?.date ?? .distantPast
        guard let last = samples.last, !last.charging, last.percent > 0,
              now.timeIntervalSince(observation) >= 0, now.timeIntervalSince(observation) < 150,
              observation >= last.date, observation.timeIntervalSince(last.date) <= 360 else { return nil }
        let session = samples.filter { $0.session == last.session }
        guard session.count >= 20, let first = session.first,
              session.allSatisfy({ !$0.charging }), Set(session.map(\.percent)).count >= 4 else { return nil }
        for (a, b) in zip(session, session.dropFirst()) {
            guard b.date > a.date, b.date.timeIntervalSince(a.date) <= 360,
                  b.percent <= a.percent else { return nil }
        }
        let elapsed = last.date.timeIntervalSince(first.date) / 3600
        let drop = first.percent - last.percent
        guard elapsed >= 6, drop >= 8 else { return nil }
        let center = Double(last.percent) * elapsed / Double(drop)
        guard center.isFinite, center > 0, center < 1000 else { return nil }
        return max(1, Int(floor(center * 0.7)))...max(1, Int(ceil(center * 1.3)))
    }
}
