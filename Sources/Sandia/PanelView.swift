import Foundation
import SwiftUI
import SandiaCore

/// Reactive state the panel needs from AppKit: engine output and system capabilities.
final class PanelModel: ObservableObject {
    @Published var resolved: ResolvedState
    @Published var backlightAvailable = false
    @Published var backlightPercent: Double = 0
    @Published var backlightAuto = false
    @Published var launchAtLogin = false
    @Published var launchAtLoginAvailable = true
    @Published var launchAtLoginNeedsApproval = false

    init(resolved: ResolvedState) {
        self.resolved = resolved
    }
}

/// Side effects that cannot live in a SwiftUI binding.
struct PanelActions {
    var setNightKelvin: (Double) -> Void
    var setDarkroom: (Bool) -> Void
    var togglePause: () -> Void
    var setBacklight: (Double) -> Void
    var toggleBacklightAuto: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var quit: () -> Void
}

/// The status item's popover: the single place where Sandia is configured.
struct PanelView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    private let panelWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            header
            curve
            separator
            nightSection
            separator
            daySection
            separator
            scheduleSection
            separator
            darkroomSection
            separator
            pauseSection

            if model.backlightAvailable {
                separator
                keyboardSection
            }

            separator
            footer
        }
        .frame(width: panelWidth)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Sandia")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                Toggle("Activé", isOn: $preferences.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(appliedTemperature)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                Text(modeLabel)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var curve: some View {
        CurveView(schedule: preferences.state.schedule, now: Date())
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    // MARK: - Sections

    private var nightSection: some View {
        section {
            sliderRow("Température de nuit", value: kelvinText(preferences.nightKelvin)) {
                Slider(value: Binding(get: { preferences.nightKelvin },
                                      set: { actions.setNightKelvin($0) }),
                       in: 1200...6500,
                       step: 10)
            }
        }
    }

    private var daySection: some View {
        section {
            sliderRow("Température de jour", value: kelvinText(preferences.dayKelvin)) {
                Slider(value: $preferences.dayKelvin, in: 1200...6500, step: 10)
            }
        }
    }

    private var scheduleSection: some View {
        section {
            timeRow("Coucher", selection: timeBinding(\.nightStart))
            timeRow("Lever", selection: timeBinding(\.nightEnd))
            Stepper(value: $preferences.transitionMinutes, in: 0...180, step: 5) {
                HStack(spacing: 8) {
                    Text("Fondu")
                    Spacer(minLength: 8)
                    Text("\(preferences.transitionMinutes) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var darkroomSection: some View {
        section {
            HStack(spacing: 8) {
                Text("Darkroom")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { preferences.isDarkroom },
                                         set: { actions.setDarkroom($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            sliderRow("Luminosité", value: percentText(preferences.darkroomBrightness)) {
                Slider(value: $preferences.darkroomBrightness, in: 0...1)
            }
        }
    }

    private var pauseSection: some View {
        section {
            HStack(spacing: 8) {
                Text("Pause")
                Spacer(minLength: 8)
                Button(isPaused ? "Reprendre" : "Suspendre 1 h") { actions.togglePause() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!preferences.isEnabled)
            }
        }
    }

    private var keyboardSection: some View {
        section {
            sliderRow("Rétroéclairage", value: "\(Int(model.backlightPercent.rounded())) %") {
                Slider(value: Binding(get: { model.backlightPercent },
                                      set: { actions.setBacklight($0) }),
                       in: 0...100)
            }
            Toggle("Ajuster en faible lumière",
                   isOn: Binding(get: { model.backlightAuto },
                                 set: { _ in actions.toggleBacklightAuto() }))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Lancer à l'ouverture",
                       isOn: Binding(get: { model.launchAtLogin },
                                     set: { actions.setLaunchAtLogin($0) }))
                    .disabled(!model.launchAtLoginAvailable)

                if !model.launchAtLoginAvailable {
                    Text("Indisponible depuis un dossier de build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.launchAtLoginNeedsApproval {
                    Text("À autoriser dans Réglages Système › Général › Ouverture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button("Quitter Sandia") { actions.quit() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Building blocks

    private var separator: some View {
        Divider()
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func sliderRow<Content: View>(_ title: String,
                                          value: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func timeRow(_ title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
        }
    }

    // MARK: - Derived text

    private var appliedTemperature: String {
        guard let kelvin = model.resolved.kelvin else { return "—" }
        return kelvinText(kelvin)
    }

    private var modeLabel: String {
        switch model.resolved.mode {
        case .scheduled:
            let night = preferences.state.schedule.nightWeight(at: Date()) >= 0.5
            return night ? "Nuit" : "Jour"
        case .darkroom:
            return "Darkroom · \(percentText(preferences.darkroomBrightness))"
        case .paused:
            guard let minutes = pausedMinutesLeft else { return "Pause" }
            return "Pause · \(minutes) min"
        case .disabled:
            return "Désactivé"
        }
    }

    private var isPaused: Bool {
        pausedMinutesLeft != nil
    }

    private var pausedMinutesLeft: Int? {
        guard let until = preferences.pausedUntil, until > Date() else { return nil }
        return Int((until.timeIntervalSinceNow / 60).rounded(.up))
    }

    private func kelvinText(_ kelvin: Double) -> String {
        "\(Int(kelvin.rounded()).formatted()) K"
    }

    private func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }

    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: {
                let time = preferences[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences[keyPath: keyPath] = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            }
        )
    }
}
