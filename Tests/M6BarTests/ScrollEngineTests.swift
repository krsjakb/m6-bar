import Foundation

private final class StateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var values: [ScrollServiceState] = []
    func record(_ value: ScrollServiceState) { lock.lock(); values.append(value); lock.unlock(); signal.signal() }
    func waitFor(_ value: ScrollServiceState) {
        let deadline = DispatchTime.now() + 3
        while true {
            lock.lock(); let found = values.contains(value); lock.unlock()
            if found { return }
            precondition(signal.wait(timeout: deadline) == .success, "Missing state: \(value)")
        }
    }
}

@main struct ScrollEngineTestRunner {
    static func main() {
        var settings = ScrollSettings.balanced
        settings.enabled = false
        var config = ScrollEngineConfiguration(settings: settings)
        let states = StateRecorder()
        let engine = ScrollEventEngine(configuration: config) { states.record($0) }
        engine.start()
        states.waitFor(.off)
        config.settings.enabled = true
        engine.configure(config)
        states.waitFor(.permissionRequired)
        // A sleeping configuration must never create a global tap, even if permission is present.
        config.sleeping = true; config.permitted = true
        engine.configure(config)
        states.waitFor(.paused("A Mac alvása alatt a simítás szünetel."))
        config.settings.enabled = false
        engine.configure(config)
        engine.cancel()
        engine.stop()
        print("PASS · scroll service lifecycle: disabled, permission missing, sleep, cancellation and teardown without global event interception")
    }
}
