import AppKit

/// Converts only discrete, unmodified mouse-wheel input. No global input is posted here.
struct ScrollEventCodec {
    static let marker: Int64 = 0x4D36424152534352
    private var remainder = ScrollVector.zero
    private let source: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        source?.pixelsPerLine = 10
        return source
    }()

    static func input(from event: CGEvent, settings: ScrollSettings, excludedPIDs: Set<Int32>) -> ScrollVector? {
        guard settings.enabled, event.type == .scrollWheel,
              event.getIntegerValueField(.eventSourceUserData) != marker,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              event.flags.intersection([.maskAlternate, .maskControl, .maskCommand, .maskShift]).isEmpty else { return nil }
        let target = Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
        guard target > 0, !excludedPIDs.contains(target) else { return nil }
        var x = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        var y = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        if x == 0 { x = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) }
        if y == 0 { y = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) }
        let lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        // macOS reduces a slow M6 detent to ~0.1 fixed-point lines despite a whole line tick.
        if lineX * x > 0 && abs(x) < abs(lineX) { x = lineX }
        if lineY * y > 0 && abs(y) < abs(lineY) { y = lineY }
        let lines = ScrollVector(x: x, y: y)
        guard lines.isFinite, lines != .zero, settings.smoothHorizontal || x == 0 else { return nil }
        return lines
    }

    mutating func event(for frame: ScrollFrame, location: CGPoint, flags: CGEventFlags, trackpadPhases: Bool, template: CGEvent? = nil) -> CGEvent? {
        guard frame.delta.isFinite else { return nil }
        let value = frame.delta + remainder
        let x = min(Double(Int32.max), max(Double(Int32.min), value.x.rounded(.towardZero)))
        let y = min(Double(Int32.max), max(Double(Int32.min), value.y.rounded(.towardZero)))
        guard let pixelEvent = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(y), wheel2: Int32(x), wheel3: 0) else { return nil }
        // Preserve the physical event's destination and native identity for Chromium/AppKit routing.
        let event: CGEvent
        if let template {
            guard let copied = template.copy() else { return nil }
            event = copied
            let deltaFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis3,
                .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis3,
                .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3]
            for field in deltaFields { event.setIntegerValueField(field, value: pixelEvent.getIntegerValueField(field)) }
            event.timestamp = pixelEvent.timestamp
        } else { event = pixelEvent }
        remainder = value - ScrollVector(x: x, y: y)
        // Rewriting even the SAME location invalidates the physical event's native window-local stamp.
        if template == nil { event.location = location }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: trackpadPhases ? frame.phase.rawValue : 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: trackpadPhases ? frame.momentum.rawValue : 0)
        return event
    }

    mutating func reset() { remainder = .zero }
}
