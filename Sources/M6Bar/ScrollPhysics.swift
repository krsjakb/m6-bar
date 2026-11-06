import Foundation

enum ScrollPreset: String, CaseIterable, Sendable {
    case precise, balanced, fluid
    var title: String {
        switch self { case .precise: "Precíz"; case .balanced: "Kiegyensúlyozott"; case .fluid: "Lendületes" }
    }
}

struct ScrollSettings: Codable, Equatable, Sendable {
    var enabled = true
    var speed = 1.0
    var smoothing = 0.55
    var momentum = 0.35
    var reverseVertical = false
    var reverseHorizontal = false
    var smoothHorizontal = true
    var trackpadPhases = true
    var excludedBundleIDs: [String] = []

    static let balanced = ScrollSettings()

    func normalized() -> Self {
        var result = self
        result.speed = speed.isFinite ? min(3, max(0.3, speed)) : 1
        result.smoothing = smoothing.isFinite ? min(1, max(0, smoothing)) : 0.55
        result.momentum = momentum.isFinite ? min(1, max(0, momentum)) : 0.35
        result.excludedBundleIDs = Array(Set(excludedBundleIDs.filter { !$0.isEmpty })).sorted()
        return result
    }

    mutating func apply(_ preset: ScrollPreset) {
        switch preset {
        case .precise: speed = 0.85; smoothing = 0.18; momentum = 0.08
        case .balanced: speed = 1; smoothing = 0.55; momentum = 0.35
        case .fluid: speed = 1.15; smoothing = 0.85; momentum = 0.75
        }
    }

    var preset: ScrollPreset? {
        ScrollPreset.allCases.first { preset in
            var reference = Self.balanced
            reference.apply(preset)
            return abs(speed - reference.speed) < 0.001 && abs(smoothing - reference.smoothing) < 0.001 && abs(momentum - reference.momentum) < 0.001
        }
    }
}

struct ScrollVector: Equatable, Sendable {
    var x: Double
    var y: Double
    static let zero = Self(x: 0, y: 0)
    var isFinite: Bool { x.isFinite && y.isFinite }
    var magnitude: Double { max(abs(x), abs(y)) }
    static func + (a: Self, b: Self) -> Self { Self(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { Self(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { Self(x: a.x * b, y: a.y * b) }
}

enum ScrollPhase: Int64, Sendable { case none = 0, began = 1, changed = 2, ended = 4, cancelled = 8 }
enum ScrollMomentum: Int64, Sendable { case none = 0, began = 1, changed = 2, ended = 3 }

struct ScrollFrame: Sendable {
    var delta: ScrollVector = .zero
    var phase: ScrollPhase = .none
    var momentum: ScrollMomentum = .none
}

/// Bounded, time-based interpolation: speed controls distance; the other controls distribute it in time.
struct ScrollPhysics {
    let settings: ScrollSettings
    private var target = ScrollVector.zero
    private var position = ScrollVector.zero
    private var direction = ScrollVector.zero
    private var lastTick = 0.0
    private var lastInput = 0.0
    private var inMomentum = false
    private(set) var isActive = false

    init(settings: ScrollSettings) { self.settings = settings.normalized() }

    mutating func push(lines: ScrollVector, at time: Double) -> [ScrollFrame] {
        guard settings.enabled, lines.isFinite, time.isFinite, lines != .zero else { return [] }
        let pixels = ScrollVector(
            x: min(100, max(-100, lines.x)) * 18 * settings.speed * (settings.reverseHorizontal ? -1 : 1),
            y: min(100, max(-100, lines.y)) * 18 * settings.speed * (settings.reverseVertical ? -1 : 1))
        var frames: [ScrollFrame] = []
        let reversed = pixels.x * direction.x < 0 || pixels.y * direction.y < 0
        let carry = isActive && inMomentum && !reversed && time >= lastTick && time - lastInput <= 0.5 ? target - position : .zero
        if isActive && (inMomentum || reversed || time < lastTick || time - lastInput > 0.5) { frames += cancel() }
        if !isActive {
            isActive = true
            inMomentum = false
            lastTick = time
            position = ScrollVector(x: pixels.x == 0 ? 0 : min(1, abs(pixels.x)) * (pixels.x > 0 ? 1 : -1),
                                    y: pixels.y == 0 ? 0 : min(1, abs(pixels.y)) * (pixels.y > 0 ? 1 : -1))
            target = carry
            frames.append(ScrollFrame(delta: position, phase: .began))
        }
        target = target + pixels
        // Bound outstanding motion even if a high-rate free-spinning wheel floods the queue.
        let pending = target - position
        target = position + ScrollVector(x: min(4000, max(-4000, pending.x)), y: min(4000, max(-4000, pending.y)))
        direction = pixels
        lastInput = time
        return frames
    }

    mutating func tick(at time: Double) -> [ScrollFrame] {
        guard isActive else { return [] }
        guard time.isFinite, time >= lastTick, time - lastTick <= 0.25 else { return cancel() }
        let dt = time - lastTick
        guard dt > 0 else { return [] }
        lastTick = time
        var frames: [ScrollFrame] = []
        var beginningMomentum = false
        if !inMomentum && settings.momentum > 0 && time - lastInput >= 0.12 {
            frames.append(ScrollFrame(phase: .ended))
            inMomentum = true
            beginningMomentum = true
        }
        let tau = inMomentum ? 0.035 + settings.momentum * 0.22 : 0.018 + settings.smoothing * 0.09
        let remaining = target - position
        let delta = remaining * (1 - exp(-dt / tau))
        position = position + delta
        frames.append(ScrollFrame(delta: delta, phase: inMomentum ? .none : .changed,
                                  momentum: inMomentum ? (beginningMomentum ? .began : .changed) : .none))
        if (target - position).magnitude < 0.05 {
            let remainder = target - position
            if remainder != .zero {
                frames.append(ScrollFrame(delta: remainder, phase: inMomentum ? .none : .changed,
                                          momentum: inMomentum ? .changed : .none))
            }
            frames.append(ScrollFrame(phase: inMomentum ? .none : .ended, momentum: inMomentum ? .ended : .none))
            reset()
        }
        return frames
    }

    mutating func cancel() -> [ScrollFrame] {
        guard isActive else { return [] }
        let end = ScrollFrame(phase: inMomentum ? .none : .cancelled, momentum: inMomentum ? .ended : .none)
        reset()
        return [end]
    }

    private mutating func reset() {
        target = .zero; position = .zero; direction = .zero
        inMomentum = false; isActive = false
    }
}
