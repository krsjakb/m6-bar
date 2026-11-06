import SwiftUI
import Charts

@MainActor
struct PopoverView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { Color(red: 0.23, green: 0.72, blue: 0.58) }
    private var displayPercent: String { model.battery.map(String.init) ?? "—" }
    private var chartSamples: [BatterySample] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return model.history.filter { $0.date >= cutoff }
    }
    private var hasChart: Bool {
        chartSamples.count > 1 && Set(chartSamples.map(\.percent)).count > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 10)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if model.showSettings {
                        settings
                    } else {
                        batteryHero
                        if !model.isFresh { connectionNotice }
                        estimateCard
                        telemetry
                        if hasChart { historyCard }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(width: 390, height: 572)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, accent.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .tint(accent)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("M6 BAR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(.secondary)
                Text(model.deviceName)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            HStack(spacing: 5) {
                Circle()
                    .fill(model.isFresh ? accent : Color.secondary.opacity(0.6))
                    .frame(width: 5, height: 5)
                Text(model.isFresh ? "Élő" : model.isConnected ? "Várakozás" : "Nincs kapcsolat")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background((model.isFresh ? accent : Color.secondary).opacity(0.09), in: Capsule())
            .accessibilityLabel(model.isFresh ? "Friss akkumulátoradat" : "Nincs friss akkumulátoradat")
        }
    }

    private var batteryHero: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(displayPercent)
                        .font(.system(size: 70, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .tracking(-3)
                    if model.battery != nil {
                        Text("%")
                            .font(.system(size: 25, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(model.isFresh ? Color.primary : Color.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.battery.map { "\(model.isFresh ? "Töltöttség" : "Utolsó ismert töltöttség"): \($0) százalék" } ?? "A töltöttség még nem érhető el")

                Label(batteryCaption, systemImage: batterySymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.isFresh && model.isCharging ? accent : Color.secondary)

                batterySegments
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MouseIllustration(accent: accent, charging: model.isFresh && model.isCharging)
                .frame(width: 112, height: 152)
                .opacity(model.isFresh ? 1 : 0.55)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
    }

    private var batteryCaption: String {
        guard model.isFresh else { return model.battery == nil ? "Mérésre vár" : "Utolsó ismert érték" }
        if model.isCharging { return "Töltés alatt" }
        return model.battery == 100 ? "Teljesen feltöltve" : "Akkumulátorról működik"
    }

    private var batterySymbol: String {
        if model.isFresh && model.isCharging { return "bolt.fill" }
        guard let battery = model.battery else { return "battery.0percent" }
        if battery <= 10 { return "battery.0percent" }
        if battery <= 35 { return "battery.25percent" }
        if battery <= 65 { return "battery.50percent" }
        if battery <= 85 { return "battery.75percent" }
        return "battery.100percent"
    }

    private var batterySegments: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(segmentColor(index))
                    .frame(height: 9)
            }
        }
        .frame(width: 189)
        .accessibilityHidden(true)
    }

    private func segmentColor(_ index: Int) -> Color {
        guard let percent = model.battery, Double(index) < Double(percent) / 5 else {
            return Color.primary.opacity(0.06)
        }
        let fill = percent <= 15 ? Color.orange : accent
        return fill.opacity(model.isFresh ? 0.95 : 0.3)
    }

    private var connectionNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(model.statusMessage, systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Segítség a csatlakozáshoz", action: model.openConnectionHelp)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var estimateCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.estimateText == nil ? "sparkle" : "hourglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.estimateText ?? "A használat során tanul")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.estimateText == nil
                     ? "Több saját mérés után itt jelenik meg a becsült üzemidő, hasonló használat mellett."
                     : "Hasonló használattal, ébren lévő Mac mellett. A becslés nem aktív egéridő.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [accent.opacity(colorScheme == .dark ? 0.09 : 0.06), Color.primary.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.12), lineWidth: 0.7))
    }

    private var telemetry: some View {
        VStack(spacing: 11) {
            dataRow("Kapcsolat", value: model.connectionLabel, symbol: "antenna.radiowaves.left.and.right")
            if let dpi = model.dpi {
                dataRow("Érzékenység", value: "\(dpi.formatted()) DPI", symbol: "scope")
            }
            if let pollingRate = model.pollingRate {
                dataRow("Lekérdezési frekvencia", value: "\(pollingRate.formatted()) Hz", symbol: "waveform.path")
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                dataRow("Utolsó mérés", value: measurementAge(at: context.date), symbol: "clock")
            }
        }
        .padding(.horizontal, 2)
    }

    private func dataRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 15)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
    }

    private func measurementAge(at date: Date) -> String {
        guard let updated = model.lastUpdated else { return "Még nincs adat" }
        let seconds = max(0, Int(date.timeIntervalSince(updated)))
        if seconds < 60 { return "Most" }
        if seconds < 3600 { return "\(seconds / 60) perce" }
        if seconds < 86400 { return "\(seconds / 3600) órája" }
        return "\(seconds / 86400) napja"
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Töltöttség alakulása")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("24 ÓRA")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(.tertiary)
            }
            Chart(chartSamples) { sample in
                LineMark(
                    x: .value("Idő", sample.date),
                    y: .value("Töltöttség", sample.percent),
                    series: .value("Mérési szakasz", sample.session.uuidString)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [2, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisValueLabel().font(.system(size: 8))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 8))
                }
            }
            .frame(height: 70)
            .accessibilityLabel("Az elmúlt 24 óra valós töltöttségi mérései")
        }
        .padding(.top, 3)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text("BEÁLLÍTÁSOK")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.secondary)
            Toggle("Indítás bejelentkezéskor", isOn: $model.launchAtLogin)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
            if let error = model.launchError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let firmware = model.firmware {
                dataRow("Firmware", value: firmware, symbol: "cpu")
            }
            Button(action: model.exportDiagnostics) {
                Label("Diagnosztika mentése…", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            Text("A mérések ezen a Macen maradnak. M6 Bar 1.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: model.refresh) {
                HStack(spacing: 6) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Frissítés")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Az egér adatainak frissítése")
            Spacer()
            Button { model.showSettings.toggle() } label: {
                Image(systemName: model.showSettings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(model.showSettings ? accent : Color.secondary)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.showSettings ? "Beállítások bezárása" : "Beállítások")
            .accessibilityLabel(model.showSettings ? "Beállítások bezárása" : "Beállítások megnyitása")
            .accessibilityValue(model.showSettings ? "Nyitva" : "Zárva")
            Button(action: model.quit) {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Kilépés az M6 Bar alkalmazásból")
            .accessibilityLabel("Kilépés az M6 Bar alkalmazásból")
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

private struct MouseIllustration: View {
    let accent: Color
    let charging: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Ellipse()
                .fill(accent.opacity(colorScheme == .dark ? 0.09 : 0.07))
                .frame(width: 107, height: 117)
                .blur(radius: 18)

            MouseShell()
                .fill(LinearGradient(
                    colors: colorScheme == .dark ? [Color(white: 0.25), Color(white: 0.12)] : [Color(white: 0.99), Color(white: 0.84)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(MouseShell().stroke(Color.primary.opacity(0.14), lineWidth: 0.8))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.1), radius: 7, x: 3, y: 6)
                .frame(width: 82, height: 133)
                .rotationEffect(.degrees(12))

            Group {
                Path { path in
                    path.move(to: CGPoint(x: 53, y: 15))
                    path.addLine(to: CGPoint(x: 53, y: 62))
                    path.move(to: CGPoint(x: 23, y: 64))
                    path.addQuadCurve(to: CGPoint(x: 86, y: 64), control: CGPoint(x: 53, y: 69))
                }
                .stroke(Color.primary.opacity(0.13), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.11))
                    .frame(width: 9, height: 24)
                    .overlay {
                        VStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { _ in
                                Capsule().fill(Color.primary.opacity(0.19)).frame(width: 5, height: 1)
                            }
                        }
                    }
                    .position(x: 53, y: 41)

                Capsule()
                    .fill(accent.opacity(0.85))
                    .frame(width: 3, height: 7)
                    .position(x: 53, y: 78)

                Capsule()
                    .fill(Color.primary.opacity(0.19))
                    .frame(width: 4, height: 17)
                    .position(x: 20, y: 59)
            }
            .frame(width: 106, height: 148)
            .rotationEffect(.degrees(12))

            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(accent.opacity(0.3), lineWidth: 0.8))
                    .offset(x: 32, y: 48)
            }
        }
    }
}

private struct MouseShell: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let w = rect.width
            let h = rect.height
            p.move(to: CGPoint(x: w * 0.52, y: 0))
            p.addCurve(to: CGPoint(x: w * 0.97, y: h * 0.30), control1: CGPoint(x: w * 0.86, y: 0), control2: CGPoint(x: w * 0.98, y: h * 0.12))
            p.addCurve(to: CGPoint(x: w * 0.91, y: h * 0.84), control1: CGPoint(x: w * 0.98, y: h * 0.50), control2: CGPoint(x: w * 1.04, y: h * 0.69))
            p.addCurve(to: CGPoint(x: w * 0.48, y: h), control1: CGPoint(x: w * 0.83, y: h * 0.97), control2: CGPoint(x: w * 0.65, y: h))
            p.addCurve(to: CGPoint(x: w * 0.05, y: h * 0.83), control1: CGPoint(x: w * 0.22, y: h), control2: CGPoint(x: w * 0.02, y: h * 0.96))
            p.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.43), control1: CGPoint(x: -w * 0.07, y: h * 0.69), control2: CGPoint(x: w * 0.16, y: h * 0.56))
            p.addCurve(to: CGPoint(x: w * 0.52, y: 0), control1: CGPoint(x: w * 0.08, y: h * 0.16), control2: CGPoint(x: w * 0.18, y: 0))
            p.closeSubpath()
        }
    }
}
