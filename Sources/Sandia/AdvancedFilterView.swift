import SwiftUI
import SandiaCore

/// The advanced filter: one red–amber axis layered on the scheduled tint.
///
/// It starts collapsed so the panel keeps its everyday controls, and it adds
/// nothing beyond the tint itself and a way back to its default. The main
/// slider still sets the intensity; at 0 % the tint has no effect.
struct AdvancedFilterView: View {
    @Binding var tint: Double
    @State private var isExpanded = false

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
