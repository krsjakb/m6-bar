import AppKit
import Observation
import ServiceManagement
@preconcurrency import ApplicationServices
import UniformTypeIdentifiers

enum PanelSection { case battery, scrolling, settings }
struct ScrollExcludedApp: Identifiable { let id: String; let name: String }

@Observable @MainActor
final class AppModel {
    private(set) var battery: Int?
    private(set) var isFresh = false
    private(set) var isCharging = false
    private(set) var isConnected = false
    let deviceName = "Keychron M6"
    private(set) var connectionLabel = "Kapcsolódás…"
    private(set) var lastUpdated: Date?
    private(set) var statusMessage = "Az egér keresése…"
    private(set) var dpi: Int?
    private(set) var pollingRate: Int?
    private(set) var firmware: String?
    private(set) var history: [BatterySample] = []
    private(set) var launchError: String?
    var panelSection = PanelSection.battery
    var showSettings: Bool {
        get { panelSection == .settings }
        set { panelSection = newValue ? .settings : .battery }
    }
    var scrollSettings = ScrollSettings.balanced { didSet { scrollSettingsChanged() } }
    private(set) var scrollPermissionGranted = AXIsProcessTrusted() && CGPreflightPostEventAccess()
    private(set) var scrollServiceState = ScrollServiceState.off
    private(set) var scrollConflictMessage: String?
    private(set) var scrollError: String?
    var isScrollActive: Bool { scrollServiceState == .active }
    var needsScrollPermission: Bool { scrollSettings.enabled && !scrollPermissionGranted }
    var scrollStatusTitle: String {
        switch scrollServiceState {
        case .off: "Kikapcsolva"
        case .permissionRequired: "Rendszerengedély szükséges"
        case .starting: "Indítás…"
        case .active: "Görgetésjavítás aktív"
        case .paused: "Szünetel"
        case .failed: "A simítás nem aktív"
        }
    }
    var scrollStatusMessage: String {
        switch scrollServiceState {
        case .off: "Kapcsold be a finomabb, lendületes görgetéshez."
        case .permissionRequired: "A görgő jeleinek átalakításához engedélyezd az M6 Bart a Rendszerbeállításokban."
        case .starting: "A görgetőmotor indul."
        case .active: "A hagyományos egérgörgők mozgását finom, folyamatos görgetéssé alakítja."
        case let .paused(message), let .failed(message): message
        }
    }
    var scrollExcludedApps: [ScrollExcludedApp] {
        scrollSettings.excludedBundleIDs.map { id in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? id
            return ScrollExcludedApp(id: id, name: name.replacingOccurrences(of: ".app", with: ""))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private(set) var isRefreshing = true
    private var launchRevision = 0
    var launchAtLogin: Bool {
        get { _ = launchRevision; return SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                launchError = SMAppService.mainApp.status == .requiresApproval ? "Az automatikus indulást a Rendszerbeállításokban hagyhatod jóvá." : nil
            } catch { launchError = "Az automatikus indulás beállítása sikertelen: \(error.localizedDescription)" }
            launchRevision += 1
            onChange?()
        }
    }
    var estimateText: String? {
        guard isFresh, let lastUpdated,
              let range = RuntimeEstimate.hours(samples: history, now: Date(), latestObservation: lastUpdated) else { return nil }
        return "Kb. \(range.lowerBound)–\(range.upperBound) óra"
    }
    var onChange: (() -> Void)?
    @ObservationIgnored private var monitor: HIDMonitor?
    @ObservationIgnored private var scrollEngine: ScrollEventEngine?
    @ObservationIgnored private var scrollSleeping = false
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var previousReading: BatteryReading?
    @ObservationIgnored private var persistenceError: String?
    @ObservationIgnored private let historyURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        historyURL = support.appendingPathComponent("M6Bar/history-v1.json")
        do {
            let data = try Data(contentsOf: historyURL)
            let loaded = try JSONDecoder().decode([BatterySample].self, from: data)
            let cutoff = Date().addingTimeInterval(-14 * 86400)
            history = loaded.filter { (0...100).contains($0.percent) && $0.date >= cutoff && $0.date <= Date() }.sorted { $0.date < $1.date }
        } catch {
            if FileManager.default.fileExists(atPath: historyURL.path) { persistenceError = "A korábbi előzmények nem olvashatók: \(error.localizedDescription)" }
        }
        // A persisted sample is historical, never a fresh device measurement.
        battery = history.last?.percent
        lastUpdated = history.last?.date
        if let stored = UserDefaults.standard.data(forKey: "scrollSettings.v1") {
            do { scrollSettings = try JSONDecoder().decode(ScrollSettings.self, from: stored).normalized() }
            catch { scrollError = "A görgetési beállítások nem olvashatók; az alapbeállításokat használjuk." }
        }
    }

    func start() {
        monitor = HIDMonitor { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
        monitor?.start()
        scrollEngine = ScrollEventEngine(configuration: scrollConfiguration()) { [weak self] state in
            DispatchQueue.main.async { self?.scrollServiceState = state; self?.onChange?() }
        }
        scrollEngine?.start()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let date = self.lastUpdated, Date().timeIntervalSince(date) > 150, self.isFresh {
                    self.isFresh = false
                    self.session = UUID()
                    self.statusMessage = "Régebbi mérés. Mozdítsd meg az egeret, majd frissíts."
                }
                self.onChange?()
                self.synchronizeScrolling()
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause(sleeping: true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause(sleeping: false) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollEngine?.cancel(); self?.synchronizeScrolling() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.synchronizeScrolling() }
            })
        }
    }

    private func pause(sleeping: Bool) {
        isFresh = false; session = UUID()
        statusMessage = sleeping ? "A megfigyelés szünetel." : "Újracsatlakozás…"
        monitor?.setSleeping(sleeping)
        scrollSleeping = sleeping
        synchronizeScrolling()
        onChange?()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        monitor?.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.isRefreshing = false }
    }

    private func handle(_ event: DeviceEvent) {
        switch event {
        case let .reading(value, wireless):
            let now = Date()
            if let previousReading, previousReading.charging != value.charging || previousReading.dpi != value.dpi || previousReading.pollingRate != value.pollingRate || value.percent > previousReading.percent {
                session = UUID()
            }
            if let lastUpdated, now.timeIntervalSince(lastUpdated) > 150 { session = UUID() }
            battery = value.percent; isCharging = value.charging
            dpi = value.dpi; pollingRate = value.pollingRate
            previousReading = value
            isConnected = true; isFresh = true; lastUpdated = now; isRefreshing = false
            connectionLabel = wireless ? "2,4 GHz · Link-KM" : "USB-kábel"
            statusMessage = value.charging ? "Töltés alatt" : value.percent <= 15 ? "Hamarosan érdemes feltölteni" : "Akkumulátorról működik"
            if let last = history.last, last.session == session, last.percent == value.percent, now.timeIntervalSince(last.date) < 300 { break }
            history.append(BatterySample(date: now, percent: value.percent, charging: value.charging, session: session))
            saveHistory()
        case let .firmware(version): firmware = version
        case let .unavailable(message), let .error(message):
            isConnected = false; isFresh = false; isRefreshing = false; statusMessage = message
            connectionLabel = "Nincs élő kapcsolat"
            dpi = nil; pollingRate = nil; firmware = nil
            session = UUID()
        case .paused:
            isFresh = false; isRefreshing = false; session = UUID()
        }
        onChange?()
    }

    private func saveHistory() {
        history.removeAll { $0.date < Date().addingTimeInterval(-14 * 86400) }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = "Az előzmények mentése sikertelen: \(error.localizedDescription)" }
    }

    func openConnectionHelp() {
        NSWorkspace.shared.open(URL(string: "https://www.keychron.com/pages/keychron-m6-user-guide")!)
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "M6-Bar-diagnosztika.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = """
        M6 Bar 1.1 · helyi diagnosztika
        Modell: Keychron M6 (3434:d060)
        Kapcsolat: \(connectionLabel)
        Friss mérés: \(isFresh)
        Akkumulátor: \(battery.map(String.init) ?? "—")%
        Töltés: \(isCharging)
        DPI: \(dpi.map(String.init) ?? "—")
        Frekvencia: \(pollingRate.map(String.init) ?? "—") Hz
        Firmware: \(firmware ?? "—")
        Utolsó mérés: \(lastUpdated?.ISO8601Format() ?? "—")
        Állapot: \(statusMessage)
        Előzmények: \(history.count) mérés
        Tárolás: \(persistenceError ?? "Rendben")
        Görgetés: \(scrollStatusTitle)
        Görgetés állapota: \(scrollStatusMessage)
        Görgetési engedély: \(scrollPermissionGranted)
        Sebesség: \(scrollSettings.speed), simítás: \(scrollSettings.smoothing), lendület: \(scrollSettings.momentum)
        """
        do { try report.write(to: url, atomically: true, encoding: .utf8) }
        catch {
            let alert = NSAlert(); alert.messageText = "A diagnosztika nem menthető"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }

    private func scrollSettingsChanged() {
        do {
            let data = try JSONEncoder().encode(scrollSettings.normalized())
            UserDefaults.standard.set(data, forKey: "scrollSettings.v1")
            scrollError = nil
        } catch { scrollError = "A görgetési beállítások mentése sikertelen: \(error.localizedDescription)" }
        synchronizeScrolling()
    }

    private func scrollConfiguration() -> ScrollEngineConfiguration {
        let excluded = Set(scrollSettings.excludedBundleIDs)
        let pids = Set(NSWorkspace.shared.runningApplications.compactMap { app -> Int32? in
            guard let id = app.bundleIdentifier, excluded.contains(id) else { return nil }
            return app.processIdentifier
        })
        return ScrollEngineConfiguration(settings: scrollSettings.normalized(), excludedPIDs: pids,
                                         permitted: scrollPermissionGranted, sleeping: scrollSleeping)
    }

    private func synchronizeScrolling() {
        scrollPermissionGranted = AXIsProcessTrusted() && CGPreflightPostEventAccess()
        let known: [(String, String)] = [
            ("com.nuebling.mac-mouse-fix", "Mac Mouse Fix"), ("com.caldis.Mos", "Mos"),
            ("com.linearmouse", "LinearMouse"), ("com.smoothscroll", "SmoothScroll"), ("com.better-mouse", "BetterMouse")
        ]
        let ids = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let conflicts = known.filter { prefix, _ in ids.contains { $0.lowercased().hasPrefix(prefix.lowercased()) } }.map(\.1)
        scrollConflictMessage = conflicts.isEmpty ? nil : "Másik görgetőapp is fut: \(conflicts.joined(separator: ", ")). A legjobb eredményhez csak az egyik appban legyen bekapcsolva a simítás."
        scrollEngine?.configure(scrollConfiguration())
    }

    func requestScrollPermission() {
        scrollSettings.enabled = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if AXIsProcessTrusted() && !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        retryScrolling()
    }

    func retryScrolling() { synchronizeScrolling(); scrollEngine?.retry() }
    func selectScrollPreset(_ preset: ScrollPreset) {
        var settings = scrollSettings; settings.apply(preset); scrollSettings = settings
    }
    func resetScrollSettings() {
        var settings = ScrollSettings.balanced
        settings.enabled = scrollSettings.enabled
        settings.excludedBundleIDs = scrollSettings.excludedBundleIDs
        scrollSettings = settings
    }
    func addScrollExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = "Melyik alkalmazásban maradjon natív a görgetés?"
        panel.prompt = "Kihagyás"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let id = Bundle(url: url)?.bundleIdentifier else { scrollError = "Az alkalmazás nem azonosítható."; return }
        if !scrollSettings.excludedBundleIDs.contains(id) { scrollSettings.excludedBundleIDs.append(id) }
    }
    func removeScrollExcludedApp(_ id: String) { scrollSettings.excludedBundleIDs.removeAll { $0 == id } }

    func stop() {
        monitor?.stop(); scrollEngine?.stop(); heartbeat?.invalidate()
        for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        observers.removeAll()
    }
    func quit() { NSApplication.shared.terminate(nil) }
}
