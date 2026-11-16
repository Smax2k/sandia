import SwiftUI
import SandiaCore

/// The advanced settings: the red–amber tint axis layered on the scheduled
/// tint, then the rows the panel hands over — the fade and the keyboard
/// backlight.
///
/// It starts collapsed so the panel keeps its everyday controls. The tint adds
/// nothing beyond itself and a way back to its default: the main slider still
/// sets the intensity, so at 0 % the tint has no effect.
struct AdvancedFilterView<Extra: View>: View {
    @Binding var tint: Double
    private let extra: () -> Extra
    @State private var isExpanded: Bool

    /// - Parameters:
    ///   - initiallyExpanded: whether the group starts open. Only the
    ///     off-screen screenshot harness passes `true`; the panel keeps the
    ///     collapsed default.
    ///   - extra: the rows below the tint, built by the panel so they keep
    ///     their own bindings and actions.
    init(tint: Binding<Double>,
         initiallyExpanded: Bool = false,
         @ViewBuilder extra: @escaping () -> Extra) {
        _tint = tint
        _isExpanded = State(initialValue: initiallyExpanded)
        self.extra = extra
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Tint")
                    Spacer(minLength: 8)
                    Text(valueText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Reset") { tint = FilterTint.neutral }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(tint == FilterTint.neutral)
                }

                HStack(spacing: 8) {
                    Text("Red")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $tint, in: FilterTint.minimum...FilterTint.maximum)
                        .accessibilityLabel("Tint")
                        .accessibilityValue(valueText)
                    Text("Amber")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("The main slider still sets the intensity; at 0 % this has no effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                extra()
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced settings")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Signed percentage, so the two ends read as one axis around zero.
    private var valueText: String {
        let percent = Int((FilterTint.clamped(tint) * 100).rounded())
        return percent > 0 ? "+\(percent) %" : "\(percent) %"
    }
}
