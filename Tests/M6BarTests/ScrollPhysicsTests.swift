import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String = "Scroll assertion failed", line: UInt = #line) {
    if !value() { print("FAIL line \(line): \(message)"); exit(1) }
}

private func drain(_ physics: inout ScrollPhysics, from start: Double = 0, fps: Double = 120) -> [ScrollFrame] {
    var frames: [ScrollFrame] = []
    for i in 1...600 {
        frames += physics.tick(at: start + Double(i) / fps)
        if !physics.isActive { break }
    }
    check(!physics.isActive, "Animation must settle and stop its timer")
    return frames
}

func isolatedWheelIsSmoothAndConservesDistance() {
    var physics = ScrollPhysics(settings: .balanced)
    let first = physics.push(lines: ScrollVector(x: 0, y: 3), at: 0)
    check(first.first?.phase == .began)
    let frames = first + drain(&physics)
    let distance = frames.reduce(0) { $0 + $1.delta.y }
    check(abs(distance - 54) < 0.001, "One three-line wheel step should travel exactly 54 pixels")
    check(frames.filter { $0.delta.y > 0 }.count > 5, "A wheel step must be spread over frames")
    check(frames.allSatisfy { $0.delta.y >= 0 && $0.delta.x == 0 })
    check(frames.contains { $0.phase == .ended })
    check(frames.contains { $0.momentum == .began })
    check(frames.last?.momentum == .ended)
    check(physics.tick(at: 10).isEmpty)
}

func motionDoesNotDependOnFrameRate() {
    func simulate(_ fps: Double) -> Double {
        var physics = ScrollPhysics(settings: .balanced)
        let frames = physics.push(lines: ScrollVector(x: 0, y: -5), at: 0) + drain(&physics, fps: fps)
        return frames.reduce(0) { $0 + $1.delta.y }
    }
    check(abs(simulate(60) - simulate(120)) < 0.001)
    check(abs(simulate(144) + 90) < 0.001)
}

func speedDirectionAndHorizontalAreIndependent() {
    var settings = ScrollSettings.balanced
    settings.speed = 2
    settings.reverseVertical = true
    settings.reverseHorizontal = false
    var physics = ScrollPhysics(settings: settings)
    let frames = physics.push(lines: ScrollVector(x: 2, y: 3), at: 0) + drain(&physics)
    check(abs(frames.reduce(0) { $0 + $1.delta.x } - 72) < 0.001)
    check(abs(frames.reduce(0) { $0 + $1.delta.y } + 108) < 0.001)
}

func reversalStopsOldDirectionImmediately() {
    var physics = ScrollPhysics(settings: .balanced)
    _ = physics.push(lines: ScrollVector(x: 0, y: 8), at: 0)
    _ = physics.tick(at: 0.02)
    let reversed = physics.push(lines: ScrollVector(x: 0, y: -2), at: 0.025)
    let tail = drain(&physics, from: 0.025)
    check(reversed.contains { $0.phase == .cancelled })
    check((reversed + tail).allSatisfy { $0.delta.y <= 0 })

    physics = ScrollPhysics(settings: .balanced)
    _ = physics.push(lines: ScrollVector(x: 10, y: 0), at: 1)
    _ = physics.tick(at: 1.01)
    _ = physics.push(lines: ScrollVector(x: 0, y: 1), at: 1.015)
    _ = physics.tick(at: 1.02)
    let horizontalReversal = physics.push(lines: ScrollVector(x: -1, y: 0), at: 1.025)
    check(horizontalReversal.contains { $0.phase == .cancelled }, "Vertical input must not erase the pending horizontal direction")
    check(drain(&physics, from: 1.025).allSatisfy { $0.delta.x <= 0 })
}

func cancellationClosesGestureAndNeverLeaksTail() {
    var physics = ScrollPhysics(settings: .balanced)
    _ = physics.push(lines: ScrollVector(x: 1, y: 2), at: 0)
    let end = physics.cancel()
    check(end.last?.phase == .cancelled)
    check(end.allSatisfy { $0.delta == .zero })
    check(!physics.isActive)
    check(physics.tick(at: 0.05).isEmpty)
    check(physics.cancel().isEmpty)
    _ = physics.push(lines: ScrollVector(x: 0, y: 4), at: 1)
    _ = physics.tick(at: 1.13)
    check(physics.cancel().last?.momentum == .ended)
}

func disabledAndInvalidInputCannotGenerateMotion() {
    var disabled = ScrollSettings.balanced
    disabled.enabled = false
    var physics = ScrollPhysics(settings: disabled)
    check(physics.push(lines: ScrollVector(x: 0, y: 2), at: 0).isEmpty)
    check(!physics.isActive)
    physics = ScrollPhysics(settings: .balanced)
    check(physics.push(lines: .zero, at: 0).isEmpty)
    check(physics.push(lines: ScrollVector(x: .nan, y: 2), at: 0).isEmpty)
    check(physics.push(lines: ScrollVector(x: 0, y: .infinity), at: 0).isEmpty)
    check(physics.push(lines: ScrollVector(x: 0, y: 2), at: .nan).isEmpty)
    _ = physics.push(lines: ScrollVector(x: 0, y: 2), at: 1)
    let stalled = physics.tick(at: 3)
    check(stalled.allSatisfy { $0.delta == .zero }, "A stalled thread must not dump a delayed scroll jump")
    check(!physics.isActive)
}

func momentumCanBeDisabledAndBurstsStayBounded() {
    var settings = ScrollSettings.balanced
    settings.momentum = 0
    var physics = ScrollPhysics(settings: settings)
    var frames: [ScrollFrame] = []
    for i in 0..<20 {
        let t = Double(i) * 0.01
        frames += physics.push(lines: ScrollVector(x: 0, y: 1), at: t)
        frames += physics.tick(at: t + 0.005)
    }
    frames += drain(&physics, from: 0.195)
    check(frames.allSatisfy { $0.momentum == .none })
    check(abs(frames.reduce(0) { $0 + $1.delta.y } - 360) < 0.001)
    check(frames.allSatisfy { $0.delta.y >= 0 })
}

func newWheelDuringMomentumKeepsTheUnfinishedDistance() {
    var physics = ScrollPhysics(settings: .balanced)
    var frames = physics.push(lines: ScrollVector(x: 0, y: 3), at: 0)
    for i in 1...18 { frames += physics.tick(at: Double(i) / 120) }
    let resumed = physics.push(lines: ScrollVector(x: 0, y: 3), at: 0.16)
    check(resumed.first?.momentum == .ended)
    check(resumed.last?.phase == .began)
    frames += resumed
    frames += drain(&physics, from: 0.16)
    check(abs(frames.reduce(0) { $0 + $1.delta.y } - 108) < 0.001, "Resuming while coasting must preserve the remaining wheel distance")
}

func preferencesClampAndRoundTrip() throws {
    var settings = ScrollSettings.balanced
    settings.speed = .infinity
    settings.smoothing = -9
    settings.momentum = 7
    settings.excludedBundleIDs = ["com.apple.Safari", "com.apple.Safari", "", "com.apple.Terminal"]
    let normalized = settings.normalized()
    check(normalized.speed == 1)
    check(normalized.smoothing == 0)
    check(normalized.momentum == 1)
    check(normalized.excludedBundleIDs.count == 2)
    let decoded = try JSONDecoder().decode(ScrollSettings.self, from: JSONEncoder().encode(normalized))
    check(decoded == normalized)
    settings = .balanced
    settings.apply(.precise)
    check(settings.preset == .precise)
    settings.speed = 1.8
    check(settings.preset == nil)
    settings.apply(.balanced)
    check(settings.preset == .balanced)
}

@main struct ScrollTestRunner {
    static func main() throws {
        isolatedWheelIsSmoothAndConservesDistance()
        motionDoesNotDependOnFrameRate()
        speedDirectionAndHorizontalAreIndependent()
        reversalStopsOldDirectionImmediately()
        cancellationClosesGestureAndNeverLeaksTail()
        disabledAndInvalidInputCannotGenerateMotion()
        momentumCanBeDisabledAndBurstsStayBounded()
        newWheelDuringMomentumKeepsTheUnfinishedDistance()
        try preferencesClampAndRoundTrip()
        print("PASS · 9 scroll physics groups: distance, frame rates, axes, reversal, cancellation, fail-open inputs, bursts, momentum resumption, preferences")
    }
}
