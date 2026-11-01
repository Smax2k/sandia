import Foundation
import SwiftUI
import DvskCore

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

/// The status item's popover: the single place where Dvsk is configured.
struct PanelView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var model: PanelModel
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()

            sliderRow("Night temperature", value: "\(Int(preferences.nightKelvin.rounded()))K") {
                Slider(value: Binding(get: { preferences.nightKelvin },
                                      set: { actions.setNightKelvin($0) }),
                       in: 1200...6500,
                       step: 10)
            }

            sliderRow("Day temperature", value: "\(Int(preferences.dayKelvin.rounded()))K") {
                Slider(value: $preferences.dayKelvin, in: 1200...6500, step: 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Night starts", selection: timeBinding(\.nightStart), displayedComponents: .hourAndMinute)
                DatePicker("Night ends", selection: timeBinding(\.nightEnd), displayedComponents: .hourAndMinute)
            }

            Stepper(value: $preferences.transitionMinutes, in: 0...180, step: 5) {
                Text("Fade: \(preferences.transitionMinutes) min")
            }

            sliderRow("Darkroom brightness", value: "\(Int((preferences.darkroomBrightness * 100).rounded()))%") {
                Slider(value: $preferences.darkroomBrightness, in: 0...1)
            }

            Toggle("Darkroom", isOn: Binding(get: { preferences.isDarkroom },
                                             set: { actions.setDarkroom($0) }))

            Button(pauseTitle) { actions.togglePause() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!preferences.isEnabled)

            if model.backlightAvailable {
                Divider()
                sliderRow("Keyboard backlight", value: "\(Int(model.backlightPercent.rounded()))%") {
                    Slider(value: Binding(get: { model.backlightPercent },
                                          set: { actions.setBacklight($0) }),
                           in: 0...100)
                }

                Toggle("Adjust keyboard in low light",
                       isOn: Binding(get: { model.backlightAuto },
                                     set: { _ in actions.toggleBacklightAuto() }))
            }

            Divider()
            launchSection

            Divider()
            Button("Quit Dvsk") { actions.quit() }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                Text(statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Toggle("Enabled", isOn: $preferences.isEnabled)
        }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login",
                   isOn: Binding(get: { model.launchAtLogin },
                                 set: { actions.setLaunchAtLogin($0) }))
                .disabled(!model.launchAtLoginAvailable)

            if !model.launchAtLoginAvailable {
                Text("Unavailable while running from a build folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.launchAtLoginNeedsApproval {
                Text("Approve Dvsk in System Settings › General › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sliderRow<Content: View>(_ title: String,
                                          value: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    // MARK: - Derived text

    private var statusTitle: String {
        switch model.resolved.mode {
        case .scheduled:
            return "\(Int((model.resolved.kelvin ?? 0).rounded())) K"
        case .darkroom:
            return "Darkroom"
        case .paused:
            return "Paused"
        case .disabled:
            return "Off"
        }
    }

    private var statusDetail: String {
        switch model.resolved.mode {
        case .scheduled:
            let night = preferences.state.schedule.nightWeight(at: Date()) >= 0.5
            return night ? "Night" : "Day"
        case .darkroom:
            return "\(Int((preferences.darkroomBrightness * 100).rounded()))% red"
        case .paused:
            guard let until = preferences.pausedUntil, until > Date() else { return "No tint" }
            let minutes = Int((until.timeIntervalSinceNow / 60).rounded(.up))
            return "\(minutes) min left"
        case .disabled:
            return "No tint"
        }
    }

    private var pauseTitle: String {
        isPaused ? "Resume" : "Disable for an hour"
    }

    private var isPaused: Bool {
        preferences.pausedUntil.map { $0 > Date() } ?? false
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
