import AppKit
import SwiftUI

@main
struct M6BarMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            diagnose()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func diagnose() {
        let collector = DiagnosticCollector()
        let monitor = HIDMonitor { event in collector.record(event) }
        monitor.start()
        RunLoop.main.run(until: Date().addingTimeInterval(6))
        monitor.stop()
        collector.printResult()
    }
}

private final class DiagnosticCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var result: [String: Any] = ["device": "Keychron M6", "success": false]
    func record(_ event: DeviceEvent) {
        lock.lock(); defer { lock.unlock() }
        switch event {
        case let .reading(reading, wireless):
            result["success"] = true
            result["batteryPercent"] = reading.percent
            result["charging"] = reading.charging
            result["dpi"] = reading.dpi
            result["pollingRateHz"] = reading.pollingRate
            result["connection"] = wireless ? "2.4 GHz Link-KM" : "USB"
        case let .firmware(version): result["firmware"] = version
        case let .error(message), let .unavailable(message): result["message"] = message
        case .paused: break
        }
    }
    func printResult() {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private var status: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "hu.balint.m6bar").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApplication.shared.terminate(nil)
            return
        }
        status = NSStatusBar.system.statusItem(withLength: 72)
        if let button = status.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: PopoverView(model: model).onExitCommand { [weak self] in
            self?.popover.performClose(nil)
        })
        // Keep the anchor stable when replacing summary content with settings.
        hosting.sizingOptions = []
        hosting.preferredContentSize = NSSize(width: 390, height: 572)
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 390, height: 572)
        model.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        model.start()
        if CommandLine.arguments.contains("--scrolling") { model.panelSection = .scrolling }
        if !UserDefaults.standard.bool(forKey: "hasOpened") || CommandLine.arguments.contains("--show") {
            UserDefaults.standard.set(true, forKey: "hasOpened")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showPopover() }
        }
    }

    private func updateStatus() {
        guard let button = status?.button else { return }
        button.title = model.isFresh ? " \(model.battery.map(String.init) ?? "—")%" : " —"
        let symbol = model.isFresh && model.isCharging ? "computermouse.fill" : "computermouse"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Keychron M6")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = model.isFresh && (model.battery ?? 100) <= 15 && !model.isCharging ? .systemOrange : nil
        button.toolTip = model.isFresh ? "Keychron M6 · \(model.battery ?? 0)% · \(model.statusMessage)" : "Keychron M6 · Nincs friss mérés"
        button.setAccessibilityLabel(button.toolTip)
        if CommandLine.arguments.contains("--record-status") { recordStatus() }
    }

    private func recordStatus() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("M6Bar")
        let value: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "battery": model.battery.map { $0 as Any } ?? NSNull(), "batteryFresh": model.isFresh,
            "scrollEnabled": model.scrollSettings.enabled, "scrollActive": model.isScrollActive,
            "scrollPermission": model.scrollPermissionGranted, "scrollStatus": model.scrollStatusTitle,
            "scrollMessage": model.scrollStatusMessage, "updated": Date().ISO8601Format()]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: folder.appendingPathComponent("runtime-status.json"), options: .atomic)
        } catch { NSLog("M6 Bar diagnostic status could not be written: %@", error.localizedDescription) }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = status?.button else { return }
        model.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}
