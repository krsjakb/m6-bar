import SwiftUI
import Foundation

@MainActor
struct ScrollSettingsView: View {
    @Bindable var model: AppModel

    private var accent: Color { Color(red: 0.23, green: 0.72, blue: 0.58) }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            statusCard

            if model.scrollSettings.enabled && model.needsScrollPermission {
                permissionCard
            }

            if let conflict = model.scrollConflictMessage {
                message(conflict, symbol: "exclamationmark.triangle", color: .orange)
            }

            if let error = model.scrollError {
                VStack(alignment: .leading, spacing: 9) {
                    message(error, symbol: "exclamationmark.circle", color: .orange)
                    Button("Újrapróbálás", action: model.retryScrolling)
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                }
            }

            presetSelector

            VStack(alignment: .leading, spacing: 15) {
                adjustment(
                    "Sebesség", value: $model.scrollSettings.speed, range: 0.3...3,
                    valueText: speedText,
                    lower: "Lassabb", upper: "Gyorsabb"
                )
                adjustment(
                    "Simítás", value: $model.scrollSettings.smoothing, range: 0...1,
                    valueText: percentText(model.scrollSettings.smoothing),
                    lower: "Közvetlen", upper: "Lágy"
                )
                adjustment(
                    "Lendület", value: $model.scrollSettings.momentum, range: 0...1,
                    valueText: percentText(model.scrollSettings.momentum),
                    lower: "Rövid", upper: "Hosszan kifutó"
                )
            }

            DisclosureGroup {
                advancedSettings
                    .padding(.top, 12)
            } label: {
                Label("További beállítások", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
            }
            .disclosureGroupStyle(.automatic)

            Text("A hagyományos görgőt simítja minden egérnél. A trackpad és a módosítóbillentyűs görgetés változatlan marad.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Alapbeállítások visszaállítása", action: model.resetScrollSettings)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                Spacer()
                if model.scrollSettings.preset == nil {
                    Text("Egyéni profil")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .tint(accent)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $model.scrollSettings.enabled) {
                HStack(spacing: 9) {
                    Image(systemName: "computermouse")
                        .font(.system(size: 17))
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                    Text("Finom görgetés")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityHint("Az összes hagyományos egérgörgő simítását kapcsolja be vagy ki")

            HStack(alignment: .top, spacing: 7) {
                Circle()
                    .fill(model.isScrollActive ? accent : Color.secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.scrollStatusTitle)
                        .font(.system(size: 11, weight: .medium))
                    Text(model.scrollStatusMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .accessibilityElement(children: .combine)
            if case .failed = model.scrollServiceState {
                Button("Újrapróbálás", action: model.retryScrolling)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.12), lineWidth: 0.7))
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Egyszeri rendszerengedély szükséges", systemImage: "hand.raised")
                .font(.system(size: 11, weight: .semibold))
            Text("Nyisd meg a rendszerbeállításokat, és kézzel engedélyezd az M6 Bar hozzáférését a megjelenő listában. Ezután térj vissza ide.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ha frissítés után is ezt látod: a rendszer listájából távolítsd el az M6 Bart, majd az Alkalmazások mappából add hozzá újra.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Rendszerengedély…", action: model.requestScrollPermission)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                Button("Újraellenőrzés", action: model.retryScrolling)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
    }

    private var presetSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Milyen érzés legyen?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                ForEach(ScrollPreset.allCases, id: \.self) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private func presetButton(_ preset: ScrollPreset) -> some View {
        let selected = model.scrollSettings.preset == preset
        return Button { model.selectScrollPreset(preset) } label: {
            VStack(spacing: 7) {
                Image(systemName: presetSymbol(preset))
                    .font(.system(size: 15, weight: .regular))
                    .accessibilityHidden(true)
                Text(preset.title)
                    .font(.system(size: 9, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(selected ? accent.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? accent.opacity(0.55) : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.title) görgetési profil")
        .accessibilityValue(selected ? "Kiválasztva" : "Nincs kiválasztva")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func presetSymbol(_ preset: ScrollPreset) -> String {
        switch preset {
        case .precise: "scope"
        case .balanced: "slider.horizontal.3"
        case .fluid: "wind"
        }
    }

    private var speedText: String {
        model.scrollSettings.speed.formatted(.number.precision(.fractionLength(1...2)).locale(Locale(identifier: "hu_HU"))) + "×"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func adjustment(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>,
        valueText: String, lower: String, upper: String
    ) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.01)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
            HStack {
                Text(lower)
                Spacer()
                Text(upper)
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            compactToggle("Függőleges irány megfordítása", value: $model.scrollSettings.reverseVertical)
            compactToggle("Vízszintes irány megfordítása", value: $model.scrollSettings.reverseHorizontal)
            compactToggle("Vízszintes görgetés simítása", value: $model.scrollSettings.smoothHorizontal)
            VStack(alignment: .leading, spacing: 6) {
                compactToggle("Trackpadszerű viselkedés", value: $model.scrollSettings.trackpadPhases)
                Text("Görgetési fázisokat küld az appoknak. A támogatás alkalmazásonként eltérhet.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Kivételek")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button(action: model.addScrollExcludedApp) {
                        Label("App hozzáadása…", systemImage: "plus")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }
                Text("Ezekben az appokban az eredeti görgetés marad.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(model.scrollExcludedApps, id: \.id) { app in
                    HStack(spacing: 8) {
                        Image(systemName: "app")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(app.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Button { model.removeScrollExcludedApp(app.id) } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(app.name) eltávolítása a kivételek közül")
                        .accessibilityLabel("\(app.name) eltávolítása a kivételek közül")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func compactToggle(_ title: String, value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
            .font(.system(size: 11))
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    private func message(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }
}
