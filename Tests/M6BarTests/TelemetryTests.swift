import Foundation

private let liveReport: [UInt8] = [
    0xb4,0x06,0x00,0x22,0x22,0x02,0x90,0x01,0x20,0x03,0x40,0x06,0x80,0x0c,0x88,0x13,
    0x15,0x05,0x04,0x0a,0x53,0,0,0,0,0,0,0x37,0,0,0,0x04,0x14,0x04,0x04,0x04,0x04,0x04,
    0x04,0x04,0x04,0,0,0,0,1,2,0,0,0,3,5,0,0,0,0,0,0,0,0,0,0,0,0
]

func capturedHardwarePacket() throws {
    let payload = try require(M6Protocol.payload(liveReport, reportID: 0xB4))
    let battery = try require(M6Protocol.battery(payload, wireless: true))
    expect(battery.percent == 83)
    expect(!battery.charging)
    expect(battery.dpi == 1600)
    expect(battery.pollingRate == 1000)
    expect(M6Protocol.payload(payload, reportID: 0xB4) == payload)
}

func malformedAndUnknownBatteryNeverBecomePercent() throws {
    expect(M6Protocol.payload(Array(liveReport.prefix(20)), reportID: 0xB4) == nil)
    expect(M6Protocol.payload(liveReport, reportID: 0xB6) == nil)
    var p = try require(M6Protocol.payload(liveReport, reportID: 0xB4))
    p[19] = 0xFF
    expect(M6Protocol.battery(p, wireless: true) == nil)
    p[19] = 0x80
    expect(M6Protocol.battery(p, wireless: true)?.percent == 0)
    expect(M6Protocol.battery(p, wireless: true)?.charging == true)
    p[0] = 0xE2
    expect(M6Protocol.battery(p, wireless: true) == nil)
}

func receiverMustConfirmOurMouseIsOnline() {
    var p: [UInt8] = [3,1,0x34,0x34,0x60,0xD0,1] + Array(repeating: 0, count: 13)
    expect(M6Protocol.pairedMouse(p) == true)
    p[6] = 0
    expect(M6Protocol.pairedMouse(p) == false)
    p[6] = 1; p[4] = 0x61
    expect(M6Protocol.pairedMouse(p) == false)
    p[1] = 255
    expect(M6Protocol.pairedMouse(p) == nil)
}

func verifiedFirmwareIdentity() {
    let p: [UInt8] = [2,4,0,0x34,0x34,0x60,0xD0,3,1,0x11] + Array(repeating: 0, count: 10)
    expect(M6Protocol.firmware(p) == "1.0.3")
}

func estimateNeedsContinuousMeaningfulDischarge() throws {
    let now = Date()
    let id = UUID()
    let samples = (0...72).map { i in
        BatterySample(date: now.addingTimeInterval(Double(i - 72) * 300), percent: 90 - i / 6, charging: false, session: id)
    }
    expect(RuntimeEstimate.hours(samples: samples, now: now) != nil)
    expect(RuntimeEstimate.hours(samples: Array(samples.suffix(10)), now: now) == nil)
    expect(RuntimeEstimate.hours(samples: samples, now: now.addingTimeInterval(300)) == nil)
    expect(RuntimeEstimate.hours(samples: samples, now: now.addingTimeInterval(240), latestObservation: now.addingTimeInterval(240)) != nil)
    let charging = samples + [BatterySample(date: now, percent: 78, charging: true, session: id)]
    expect(RuntimeEstimate.hours(samples: charging, now: now) == nil)
    var interrupted = samples
    interrupted.removeSubrange(10...20)
    expect(RuntimeEstimate.hours(samples: interrupted, now: now) == nil)
    let newSession = samples + [BatterySample(date: now, percent: 78, charging: false, session: UUID())]
    expect(RuntimeEstimate.hours(samples: newSession, now: now) == nil)
}

private func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    precondition(condition(), "Assertion failed", file: (file), line: line)
}
private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw TestError.missingValue }
    return value
}
private enum TestError: Error { case missingValue }
@main struct TestRunner {
    static func main() throws {
        try capturedHardwarePacket()
        try malformedAndUnknownBatteryNeverBecomePercent()
        receiverMustConfirmOurMouseIsOnline()
        verifiedFirmwareIdentity()
        try estimateNeedsContinuousMeaningfulDischarge()
        print("PASS · 5 test groups: captured hardware, invalid reports, receiver identity, firmware, runtime estimator")
    }
}
