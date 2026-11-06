import AppKit
import CoreGraphics

enum ScrollServiceState: Equatable, Sendable {
    case off, permissionRequired, starting, active
    case paused(String), failed(String)
}

struct ScrollEngineConfiguration: Equatable, Sendable {
    var settings: ScrollSettings
    var excludedPIDs: Set<Int32> = []
    var permitted = false
    var sleeping = false
}

/// The tap, animation and all mutable scrolling state belong to this one run-loop thread.
final class ScrollEventEngine: @unchecked Sendable {
    private let receive: @Sendable (ScrollServiceState) -> Void
    private let lock = NSLock()
    private var requested: ScrollEngineConfiguration
    private var loop: CFRunLoop?
    private var applied: ScrollEngineConfiguration?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var animation: Timer?
    private var physics = ScrollPhysics(settings: .balanced)
    private var codec = ScrollEventCodec()
    private var location = CGPoint.zero
    private var flags: CGEventFlags = []
    private var targetPID: Int64 = 0
    private var targetWindow: Int64 = 0
    private var template: CGEvent?
    private var blocked = false
    private var timeoutDates: [Double] = []
    private var lastState: ScrollServiceState?

    init(configuration: ScrollEngineConfiguration, receive: @escaping @Sendable (ScrollServiceState) -> Void) {
        requested = configuration
        self.receive = receive
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "M6 Bar scrolling"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func configure(_ value: ScrollEngineConfiguration) {
        lock.lock(); requested = value; let loop = loop; lock.unlock()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in applyConfiguration() }
        CFRunLoopWakeUp(loop)
    }

    func retry() { perform { engine in engine.blocked = false; engine.timeoutDates = []; engine.applied = nil; engine.applyConfiguration() } }
    func cancel() { perform { $0.cancelMotion() } }
    func stop() { perform { engine in engine.closeTap(); CFRunLoopStop(CFRunLoopGetCurrent()) } }

    private func perform(_ action: @escaping @Sendable (ScrollEventEngine) -> Void) {
        lock.lock(); let loop = loop; lock.unlock()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [self] in action(self) }
        CFRunLoopWakeUp(loop)
    }

    private func run() {
        lock.lock(); loop = CFRunLoopGetCurrent(); lock.unlock()
        // Keep the command run loop available with no active tap. The fast timer exists only during motion.
        let keepAlive = Timer(timeInterval: 60, repeats: true) { _ in }
        keepAlive.tolerance = 30
        RunLoop.current.add(keepAlive, forMode: .default)
        applyConfiguration()
        CFRunLoopRun()
        closeTap()
        keepAlive.invalidate()
        lock.lock(); loop = nil; lock.unlock()
    }

    private func applyConfiguration() {
        lock.lock(); let current = requested; lock.unlock()
        guard current != applied else { return }
        cancelMotion(emit: current.permitted)
        applied = current
        physics = ScrollPhysics(settings: current.settings)
        if !current.settings.enabled {
            blocked = false; closeTap(); publish(.off); return
        }
        guard current.permitted else { blocked = false; closeTap(); publish(.permissionRequired); return }
        guard !current.sleeping else { closeTap(); publish(.paused("A Mac alvása alatt a simítás szünetel.")); return }
        guard !blocked else { return }
        if let tap, CGEvent.tapIsEnabled(tap: tap) { publish(.active); return }
        closeTap()
        publish(.starting)
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let created = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap,
                                              options: .defaultTap, eventsOfInterest: mask,
                                              callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<ScrollEventEngine>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            blocked = true
            publish(.failed("A macOS nem engedte elindítani a görgetésjavítást. Ellenőrizd az M6 Bar rendszerengedélyét, majd próbáld újra."))
            return
        }
        tap = created; tapSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
        CGEvent.tapEnable(tap: created, enable: true)
        guard CGEvent.tapIsEnabled(tap: created) else {
            closeTap(); blocked = true
            publish(.failed("A görgetésjavítás nem indult el. A hagyományos görgetés továbbra is használható.")); return
        }
        publish(.active)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelMotion()
            let now = ProcessInfo.processInfo.systemUptime
            timeoutDates.removeAll { now - $0 > 60 }
            timeoutDates.append(now)
            if type == .tapDisabledByTimeout, timeoutDates.count < 3, let tap, applied?.permitted == true {
                CGEvent.tapEnable(tap: tap, enable: true)
                if CGEvent.tapIsEnabled(tap: tap) { publish(.active) }
                else { blocked = true; closeTap(); publish(.failed("A macOS nem engedte újraindítani a simítást.")) }
            } else {
                blocked = true
                closeTap()
                publish(.failed("A macOS leállította a simítást. A görgetés natív maradt; a folytatáshoz válaszd az Újrapróbálást."))
            }
            return Unmanaged.passUnretained(event)
        }
        // Our own generated frames must pass without cancelling or re-entering the animation.
        if event.getIntegerValueField(.eventSourceUserData) == ScrollEventCodec.marker { return Unmanaged.passUnretained(event) }
        guard let current = applied, current.permitted, current.settings.enabled, !blocked else { return Unmanaged.passUnretained(event) }
        if type == .flagsChanged {
            if !event.flags.intersection([.maskAlternate, .maskControl, .maskCommand, .maskShift]).isEmpty { cancelMotion() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else {
            cancelMotion()
            return Unmanaged.passUnretained(event)
        }
        guard let input = ScrollEventCodec.input(from: event, settings: current.settings, excludedPIDs: current.excludedPIDs) else {
            cancelMotion()
            return Unmanaged.passUnretained(event)
        }
        let pid = event.getIntegerValueField(.eventTargetUnixProcessID)
        let window = Int64(NSEvent(cgEvent: event)?.windowNumber ?? 0)
        if pid != targetPID || window != targetWindow || event.flags != flags { cancelMotion() }
        guard let captured = event.copy() else { cancelMotion(); return Unmanaged.passUnretained(event) }
        location = event.location; flags = event.flags; targetPID = pid; targetWindow = window
        template = captured
        let frames = physics.push(lines: input, at: ProcessInfo.processInfo.systemUptime)
        guard emit(frames) else {
            failPosting()
            return Unmanaged.passUnretained(event)
        }
        startAnimation()
        return nil
    }

    private func startAnimation() {
        guard animation == nil, physics.isActive else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [self] _ in
            let frames = physics.tick(at: ProcessInfo.processInfo.systemUptime)
            if !emit(frames) { failPosting(); return }
            if !physics.isActive { animation?.invalidate(); animation = nil; template = nil }
        }
        timer.tolerance = 0.0005
        animation = timer
        RunLoop.current.add(timer, forMode: .default)
    }

    @discardableResult private func emit(_ frames: [ScrollFrame]) -> Bool {
        guard !frames.isEmpty else { return true }
        guard let current = applied else { return frames.isEmpty }
        guard let template, targetPID > 0, targetPID <= Int64(Int32.max) else { return false }
        for frame in frames {
            guard let generated = codec.event(for: frame, location: location, flags: flags,
                                               trackpadPhases: current.settings.trackpadPhases, template: template) else { return false }
            // App-directed delivery never repositions the desktop pointer or retargets a tail under it.
            generated.postToPid(Int32(targetPID))
        }
        return true
    }

    private func cancelMotion(emit shouldEmit: Bool = true) {
        let end = physics.cancel()
        if shouldEmit { emit(end) }
        animation?.invalidate(); animation = nil
        codec.reset()
        template = nil
    }

    private func failPosting() {
        cancelMotion(emit: false)
        blocked = true
        closeTap()
        publish(.failed("A simítás leállt, ezért a görgetés visszaállt natívra. Próbáld újra."))
    }

    private func closeTap() {
        cancelMotion()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), tapSource, CFRunLoopMode.defaultMode) }
        tapSource = nil; tap = nil
    }

    private func publish(_ value: ScrollServiceState) {
        guard value != lastState else { return }
        lastState = value
        receive(value)
    }
}
