import Foundation
import CoreGraphics
import AppKit

private func check(_ result: @autoclosure () -> Bool, line: UInt = #line) {
    if !result() { print("FAIL scroll event assertion at line \(line)"); exit(1) }
}

private func wheel(x: Int32 = 0, y: Int32 = 3) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!
    event.setIntegerValueField(.eventTargetUnixProcessID, value: 123)
    return event
}

@main struct ScrollEventTestRunner {
    static func main() {
        let settings = ScrollSettings.balanced
        let event = wheel()
        check(ScrollEventCodec.input(from: event, settings: settings, excludedPIDs: []) == ScrollVector(x: 0, y: 3))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        check(ScrollEventCodec.input(from: event, settings: settings, excludedPIDs: []) == nil)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        check(ScrollEventCodec.input(from: event, settings: settings, excludedPIDs: []) == nil)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        check(ScrollEventCodec.input(from: event, settings: settings, excludedPIDs: []) == nil)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        for flag: CGEventFlags in [.maskAlternate, .maskControl, .maskCommand, .maskShift] {
            event.flags = flag
            check(ScrollEventCodec.input(from: event, settings: settings, excludedPIDs: []) == nil)
        }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: ScrollEventCodec.marker)
        check(ScrollEventCodec.input(from: event, settings: settings, excludedPIDs: []) == nil)

        let background = wheel()
        background.setIntegerValueField(.eventTargetUnixProcessID, value: 321)
        check(ScrollEventCodec.input(from: background, settings: settings, excludedPIDs: [321]) == nil)
        check(ScrollEventCodec.input(from: background, settings: settings, excludedPIDs: [123]) != nil)
        background.setIntegerValueField(.eventTargetUnixProcessID, value: 0)
        check(ScrollEventCodec.input(from: background, settings: settings, excludedPIDs: [321]) == nil)
        check(ScrollEventCodec.input(from: background, settings: settings, excludedPIDs: []) == nil)
        var verticalOnly = settings
        verticalOnly.smoothHorizontal = false
        check(ScrollEventCodec.input(from: wheel(x: 1, y: 3), settings: verticalOnly, excludedPIDs: []) == nil)
        check(ScrollEventCodec.input(from: wheel(y: 3), settings: verticalOnly, excludedPIDs: []) != nil)

        var codec = ScrollEventCodec()
        var total = 0
        for i in 0..<20 {
            let frame = ScrollFrame(delta: ScrollVector(x: -0.25, y: 0.35), phase: i == 0 ? .began : .changed)
            let encoded = codec.event(for: frame, location: CGPoint(x: 10, y: 20), flags: [], trackpadPhases: true)!
            check(encoded.getIntegerValueField(.eventSourceUserData) == ScrollEventCodec.marker)
            check(encoded.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
            check(encoded.getIntegerValueField(.scrollWheelEventScrollPhase) == frame.phase.rawValue)
            check(encoded.location == CGPoint(x: 10, y: 20))
            total += Int(encoded.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            check(ScrollEventCodec.input(from: encoded, settings: settings, excludedPIDs: []) == nil)
        }
        check(abs(total - 7) <= 1)
        let momentum = codec.event(for: ScrollFrame(momentum: .began), location: .zero, flags: [], trackpadPhases: true)!
        check(momentum.getIntegerValueField(.scrollWheelEventMomentumPhase) == 1)
        check(momentum.getIntegerValueField(.scrollWheelEventScrollPhase) == 0)
        let simple = codec.event(for: ScrollFrame(phase: .began), location: .zero, flags: [], trackpadPhases: false)!
        check(simple.getIntegerValueField(.scrollWheelEventScrollPhase) == 0)
        codec.reset()
        let original = wheel()
        original.setIntegerValueField(.eventTargetUnixProcessID, value: 456)
        original.setIntegerValueField(.eventTargetProcessSerialNumber, value: 789)
        original.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 222)
        original.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 222)
        original.setIntegerValueField(.mouseEventNumber, value: 555)
        let copied = codec.event(for: ScrollFrame(delta: ScrollVector(x: 0, y: 5), phase: .changed),
                                 location: CGPoint(x: 10, y: 20), flags: [], trackpadPhases: true, template: original)!
        check(copied.getIntegerValueField(.eventTargetUnixProcessID) == 456)
        check(copied.getIntegerValueField(.eventTargetProcessSerialNumber) == 789)
        check(copied.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) == original.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent))
        check(copied.getIntegerValueField(.mouseEventNumber) == original.getIntegerValueField(.mouseEventNumber))
        check(copied.getIntegerValueField(.eventSourceStateID) == original.getIntegerValueField(.eventSourceStateID))
        check(original.getIntegerValueField(.eventSourceUserData) != ScrollEventCodec.marker)
        check(original.getIntegerValueField(.scrollWheelEventIsContinuous) == 0)
        let native = NSEvent(cgEvent: copied)!
        check(native.hasPreciseScrollingDeltas)
        check(native.scrollingDeltaY == 5)
        check(native.phase == .changed)
        check(native.momentumPhase.isEmpty)
        check(native.windowNumber == NSEvent(cgEvent: original)!.windowNumber)
        original.location = CGPoint(x: 123, y: -456)
        let preservedPosition = codec.event(for: ScrollFrame(delta: ScrollVector(x: 0, y: 5), phase: .changed),
                                            location: CGPoint(x: 999, y: 888), flags: [], trackpadPhases: true, template: original)!
        check(preservedPosition.location == original.location)
        let slowDetent = wheel(y: 1)
        slowDetent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.100006103515625)
        check(ScrollEventCodec.input(from: slowDetent, settings: settings, excludedPIDs: []) == ScrollVector(x: 0, y: 1))
        print("PASS · scroll event integration: native input, modifiers, recursion, background-app exclusions, axes, fractional pixels, native phases")
    }
}
