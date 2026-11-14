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
    var setDayKelvin: (Double) -> Void
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
            scheduleBlock

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

    /// One row only: the app name and its switch on the left, the applied
    /// temperature with its small mode word on the right. The temperature keeps
    /// its full width — it is the headline — so the mode word is the flexible
    /// part if a label ever needs the room. Both groups stay on a single line,
    /// so neither wraps.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Sandia")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Toggle("Enabled", isOn: $preferences.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(appliedTemperature)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(modeLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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

    /// The schedule and the display controls share one compact block: each
    /// boundary is a row pairing its temperature with the time it applies,
    /// then Darkroom, the fade and the pause sit on a single control strip.
    private var scheduleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            temperatureRow(title: L("Sunset"),
                           label: L("Night temperature"),
                           value: kelvinText(preferences.nightKelvin),
                           time: \.nightStart) {
                temperatureSlider(Binding(get: { preferences.nightKelvin },
                                          set: { actions.setNightKelvin($0) }))
            }

            rowSeparator
            temperatureRow(title: L("Sunrise"),
                           label: L("Day temperature"),
                           value: kelvinText(preferences.dayKelvin),
                           time: \.nightEnd) {
                temperatureSlider(Binding(get: { preferences.dayKelvin },
                                          set: { actions.setDayKelvin($0) }))
            }

            rowSeparator
            controlStrip

            // The slider only concerns the darkroom red intensity, so it is
            // meaningless — and looks like a screen setting — while it is off.
            if preferences.isDarkroom {
                HStack(spacing: 8) {
                    Text("Darkroom intensity")
                    Slider(value: $preferences.darkroomBrightness, in: 0...1)
                        .scrollWheelValue($preferences.darkroomBrightness)
                    Text(percentText(preferences.darkroomBrightness))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// The control strip keeps three comparable zones and the same spacing:
    /// Darkroom first, then the fade, and the pause at the trailing edge.
    private var controlStrip: some View {
        HStack(alignment: .top, spacing: 8) {
            labelledColumn(L("Darkroom")) {
                Toggle("", isOn: Binding(get: { preferences.isDarkroom },
                                         set: { actions.setDarkroom($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            labelledColumn(L("Fade")) {
                HStack(spacing: 2) {
                    Text("\(preferences.transitionMinutes) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: $preferences.transitionMinutes, in: 0...180, step: 5)
                        .labelsHidden()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            labelledColumn(L("Pause")) {
                Button(isPaused ? L("Resume") : L("Pause 1 h")) { actions.togglePause() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!preferences.isEnabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// A hairline between two rows, with just enough breathing room to read as
    /// a separation rather than another row of content.
    private var rowSeparator: some View {
        Divider().padding(.vertical, 6)
    }

    /// One schedule boundary: the temperature with its full-width slider, then
    /// the clock time in a fixed-width column so both rows line up vertically.
    private func temperatureRow<SliderContent: View>(title: String,
                                                     label: String,
                                                     value: String,
                                                     time keyPath: ReferenceWritableKeyPath<Preferences, TimeOfDay>,
                                                     @ViewBuilder slider: () -> SliderContent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(label)
                    Spacer(minLength: 8)
                    Text(value)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                slider()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            labelledColumn(title) {
                DatePicker(title,
                           selection: timeBinding(keyPath),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
                    .font(.body.monospacedDigit())
            }
        }
    }

    /// The backlight speaks percent: the slider and its scroll share one binding.
    private var backlightPercent: Binding<Double> {
        Binding(get: { model.backlightPercent },
                set: { actions.setBacklight($0) })
    }

    private var keyboardSection: some View {
        section {
            sliderRow(L("Keyboard backlight"), value: "\(Int(model.backlightPercent.rounded())) %") {
                Slider(value: backlightPercent, in: 0...100)
                    .scrollWheelValue(backlightPercent, in: 0...100)
            }
            Toggle("Adjust in low light",
                   isOn: Binding(get: { model.backlightAuto },
                                 set: { _ in actions.toggleBacklightAuto() }))
        }
    }

    // MARK: - Footer

    /// The footer is one row: the login toggle on the left, the quit button on
    /// the right, so the panel ends on a single line. The long approval caption,
    /// when it appears, hangs below that row instead of narrowing either
    /// control; the button keeps its full label and the toggle truncates first.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("Launch at login",
                       isOn: Binding(get: { model.launchAtLogin },
                                     set: { actions.setLaunchAtLogin($0) }))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .disabled(!model.launchAtLoginAvailable)

                Spacer(minLength: 8)

                Button("Quit Sandia") { actions.quit() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .layoutPriority(1)
            }

            if !model.launchAtLoginAvailable {
                Text("Unavailable from a build folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.launchAtLoginNeedsApproval {
                Text("Allow it in System Settings › General › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// A small caption over a control, the shape used by the three columns of
    /// the control strip. It keeps its intrinsic width so the strip can place
    /// each control side by side without truncating a label.
    private func labelledColumn<Content: View>(_ title: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
        }
        .fixedSize()
    }

    /// A temperature slider works in track position, not kelvin: the warm
    /// 1000–6504 K range gets 85 % of the travel and the cold 6504–12000 K
    /// range the remaining 15 % (`ColorTemperature.position(forKelvin:)`).
    /// The value is snapped in kelvin, so preferences and the preview stay in
    /// kelvin, and the slider carries no `step`: AppKit would draw tick marks
    /// that the popover's vibrant background turns into a white bar.
    /// The scroll wheel moves that same position, so it follows the same curve.
    private func temperatureSlider(_ kelvin: Binding<Double>) -> some View {
        let position = Binding(get: { ColorTemperature.position(forKelvin: kelvin.wrappedValue) },
                               set: { kelvin.wrappedValue = snappedKelvin(ColorTemperature.kelvin(forPosition: $0)) })
        return Slider(value: position, in: 0...1)
            .scrollWheelValue(position)
    }

    private func snappedKelvin(_ kelvin: Double) -> Double {
        (kelvin / 10).rounded() * 10
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
            return night ? L("Night") : L("Day")
        case .darkroom:
            return L("Darkroom · %@", percentText(preferences.darkroomBrightness))
        case .paused:
            guard let minutes = pausedMinutesLeft else { return L("Pause") }
            return L("Pause · %d min", minutes)
        case .disabled:
            return L("Off")
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
