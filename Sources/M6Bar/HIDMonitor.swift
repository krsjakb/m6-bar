import Foundation
import IOKit.hid

enum DeviceEvent: Sendable {
    case reading(BatteryReading, wireless: Bool)
    case firmware(String)
    case unavailable(String)
    case error(String)
    case paused
}

/// All HID state and buffers are confined to one dedicated run-loop thread.
final class HIDMonitor: @unchecked Sendable {
    private let receive: @Sendable (DeviceEvent) -> Void
    private let lock = NSLock()
    private var loop: CFRunLoop?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    private var timer: Timer?
    private var phase: Phase?
    private var deadline = Date.distantPast
    private var lastPoll = Date.distantPast
    private var wireless = true
    private var needsFirmware = true
    private var sleeping = false
    private enum Phase { case pair, battery, identity }

    init(receive: @escaping @Sendable (DeviceEvent) -> Void) {
        self.receive = receive
        buffer.initialize(repeating: 0, count: 128)
    }

    func start() {
        Thread.detachNewThread { [self] in run() }
    }

    func refresh() { perform { $0.poll(force: true) } }

    func setSleeping(_ value: Bool) {
        perform { monitor in
            monitor.sleeping = value
            monitor.phase = nil
            monitor.receive(.paused)
            if !value { monitor.lastPoll = .distantPast; monitor.poll(force: true) }
        }
    }

    func stop() { perform { _ in CFRunLoopStop(CFRunLoopGetCurrent()) } }

    private func perform(_ action: @escaping @Sendable (HIDMonitor) -> Void) {
        lock.lock(); let current = loop; lock.unlock()
        guard let current else { return }
        CFRunLoopPerformBlock(current, CFRunLoopMode.defaultMode.rawValue) { [self] in action(self) }
        CFRunLoopWakeUp(current)
    }

    private func run() {
        let current = CFRunLoopGetCurrent()!
        lock.lock(); loop = current; lock.unlock()
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = hid
        let matches: [[String: Int]] = [
            [kIOHIDVendorIDKey: M6Protocol.vendorID, kIOHIDProductIDKey: M6Protocol.receiverPID, kIOHIDPrimaryUsagePageKey: 0x8C],
            [kIOHIDVendorIDKey: M6Protocol.vendorID, kIOHIDProductIDKey: M6Protocol.mousePID, kIOHIDPrimaryUsagePageKey: 0xFFC1]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(hid, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hid, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().poll(force: true)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, removed in
            guard let context else { return }
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
            if let active = monitor.device, CFEqual(active, removed) {
                monitor.closeDevice()
                monitor.receive(.unavailable("A kapcsolat megszakadt. Csatlakoztasd újra a vevőt vagy az egeret."))
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, current, CFRunLoopMode.defaultMode.rawValue)
        timer = Timer(timeInterval: 1, repeats: true) { [self] _ in
            if phase != nil && Date() > deadline {
                let optional = phase == .identity
                phase = nil
                needsFirmware = true
                if !optional { receive(.unavailable("Az egér nem válaszol. Mozdítsd meg, majd frissíts.")) }
            }
            poll(force: false)
        }
        RunLoop.current.add(timer!, forMode: .default)
        poll(force: true)
        CFRunLoopRun()
        timer?.invalidate(); timer = nil
        closeDevice()
        IOHIDManagerUnscheduleFromRunLoop(hid, current, CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(hid, 0)
        manager = nil
        lock.lock(); loop = nil; lock.unlock()
    }

    private func selectDevice() -> Bool {
        guard let manager, let found = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !found.isEmpty else {
            closeDevice()
            receive(.unavailable("Csatlakoztasd az M6 Link-KM vevőjét vagy az egeret USB-kábellel."))
            return false
        }
        // Prefer the cable when both mouse and receiver are attached.
        let candidates = found.sorted { property($0, kIOHIDProductIDKey) > property($1, kIOHIDProductIDKey) }
        guard let selected = candidates.first else { return false }
        if let device, CFEqual(device, selected) { return true }
        closeDevice()
        receive(.paused)
        let result = IOHIDDeviceOpen(selected, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            receive(.error("Az eszköz nem nyitható meg (\(String(format: "%08x", result))). Zárd be a Keychron Launchert, és frissíts."))
            return false
        }
        device = selected
        wireless = property(selected, kIOHIDProductIDKey) == M6Protocol.receiverPID
        needsFirmware = true
        IOHIDDeviceRegisterInputReportCallback(selected, buffer, 128, { context, result, _, _, reportID, data, length in
            guard let context, result == kIOReturnSuccess, length > 0, length <= 128 else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
                .handle([UInt8](UnsafeBufferPointer(start: data, count: length)), reportID: reportID)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(selected, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        return true
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private func closeDevice() {
        if let device {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 128, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, 0)
        }
        device = nil
        phase = nil
        needsFirmware = true
    }

    private func poll(force: Bool) {
        guard !sleeping, phase == nil, force || Date().timeIntervalSince(lastPoll) >= 60 else { return }
        lastPoll = Date()
        guard selectDevice() else { return }
        if wireless { send(report: 0xB5, command: 3, phase: .pair) }
        else { send(report: 0xB3, command: 6, phase: .battery) }
    }

    private func send(report: UInt8, command: UInt8, phase next: Phase, mode: UInt8 = 0) {
        guard let device else { return }
        var bytes = [UInt8](repeating: 0, count: report == 0xB3 ? 64 : 21)
        bytes[0] = report; bytes[1] = command; bytes[2] = mode
        phase = next
        deadline = Date().addingTimeInterval(3)
        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report), $0.baseAddress!, $0.count)
        }
        if result != kIOReturnSuccess {
            phase = nil
            if next == .identity { needsFirmware = true; return }
            receive(.error("Nem sikerült lekérdezni az egeret (\(String(format: "%08x", result)))."))
            closeDevice()
        }
    }

    private func handle(_ bytes: [UInt8], reportID: UInt32) {
        guard let p = M6Protocol.payload(bytes, reportID: reportID), Date() <= deadline else { return }
        switch phase {
        case .pair where reportID == 0xB6 && p[0] == 3:
            guard M6Protocol.pairedMouse(p) == true else {
                phase = nil
                needsFirmware = true
                receive(.unavailable("A vevő csatlakoztatva, de az M6 nem elérhető. Mozdítsd meg vagy kapcsold be az egeret."))
                return
            }
            send(report: 0xB3, command: 6, phase: .battery)
        case .battery where reportID == 0xB4 && p[0] == 6:
            phase = nil
            guard let reading = M6Protocol.battery(p, wireless: wireless) else {
                needsFirmware = true
                receive(.error("Az egér érvénytelen akkumulátoradatot küldött. Próbáld újra.")); return
            }
            receive(.reading(reading, wireless: wireless))
            if needsFirmware {
                needsFirmware = false
                send(report: 0xB5, command: 2, phase: .identity, mode: wireless ? 1 : 0)
            }
        case .identity where reportID == 0xB6 && p[0] == 2:
            phase = nil
            if let version = M6Protocol.firmware(p) { receive(.firmware(version)) }
        default: break
        }
    }

    deinit { buffer.deinitialize(count: 128); buffer.deallocate() }
}
