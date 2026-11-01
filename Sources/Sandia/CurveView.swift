import Foundation
import SwiftUI
import SandiaCore

/// The 24-hour target-temperature curve for the current schedule.
///
/// The height is owned here and never derived from the drawing: a schedule
/// edit only redraws the canvas, so the popover keeps its size.
struct CurveView: View {
    static let height: CGFloat = 120

    let schedule: Schedule
    let now: Date

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Courbe de température sur 24 heures")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let width = max(size.width, 1)
        let top: CGFloat = 10
        let bottom = max(size.height - 20, top + 40)
        let plotHeight = bottom - top

        let calendar = Calendar.current
        // A fixed, ordinary local day: the curve is wall-clock based, so it must
        // not drift with today's DST transition.
        let baseDate = calendar.date(from: DateComponents(year: 2001, month: 6, day: 15)) ?? Date()

        let dayKelvin = schedule.dayKelvin
        let nightKelvin = schedule.nightKelvin
        let spread = max(abs(dayKelvin - nightKelvin), 400)
        let scaleLow = min(dayKelvin, nightKelvin) - spread * 0.15
        let scaleHigh = max(dayKelvin, nightKelvin) + spread * 0.15

        func x(_ minute: Double) -> CGFloat {
            CGFloat(min(max(minute, 0), 1440) / 1440) * width
        }

        func y(_ kelvin: Double) -> CGFloat {
            let progress = (kelvin - scaleLow) / (scaleHigh - scaleLow)
            return bottom - CGFloat(progress) * plotHeight
        }

        func kelvin(at minute: Double) -> Double {
            schedule.targetKelvin(at: baseDate.addingTimeInterval(minute * 60), calendar: calendar)
        }

        drawNightBands(in: &context, width: width, top: top, plotHeight: plotHeight, x: x)

        // Day and night reference levels.
        var levels = Path()
        for level in [dayKelvin, nightKelvin] {
            let levelY = y(level)
            levels.move(to: CGPoint(x: 0, y: levelY))
            levels.addLine(to: CGPoint(x: width, y: levelY))
        }
        context.stroke(levels,
                       with: .color(Color.primary.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 0.75, dash: [2, 3]))

        // Sampled curve, kept so the annotations can sit on the real plateaus.
        var samples: [(minute: Double, kelvin: Double)] = []
        var curve = Path()
        var minute: Double = 0
        while minute <= 1440 {
            let value = kelvin(at: minute)
            samples.append((minute, value))
            let point = CGPoint(x: x(minute), y: y(value))
            if minute == 0 {
                curve.move(to: point)
            } else {
                curve.addLine(to: point)
            }
            minute += 3
        }
        context.stroke(curve,
                       with: .color(Color.accentColor),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

        drawNowMarker(in: &context, width: width, top: top, bottom: bottom, calendar: calendar, y: y, x: x)

        drawAnnotations(in: &context,
                        samples: samples,
                        width: width,
                        top: top,
                        bottom: bottom,
                        y: y,
                        x: x)

        drawTimeAxis(in: &context, width: width, height: size.height, x: x)
    }

    private func drawNightBands(in context: inout GraphicsContext,
                                width: CGFloat,
                                top: CGFloat,
                                plotHeight: CGFloat,
                                x: (Double) -> CGFloat) {
        let start = Double(schedule.nightStart.minutesSinceMidnight)
        let end = Double(schedule.nightEnd.minutesSinceMidnight)
        guard start != end else { return }

        let bands: [(CGFloat, CGFloat)] = start < end
            ? [(x(start), x(end))]
            : [(x(start), width), (0, x(end))]

        for band in bands where band.1 - band.0 > 0.5 {
            let rect = CGRect(x: band.0, y: top, width: band.1 - band.0, height: plotHeight)
            context.fill(Path(rect), with: .color(Color.primary.opacity(0.055)))
        }
    }

    private func drawNowMarker(in context: inout GraphicsContext,
                               width: CGFloat,
                               top: CGFloat,
                               bottom: CGFloat,
                               calendar: Calendar,
                               y: (Double) -> CGFloat,
                               x: (Double) -> CGFloat) {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let minute = Double(parts.hour ?? 0) * 60
            + Double(parts.minute ?? 0)
            + Double(parts.second ?? 0) / 60
        let markerX = x(minute)

        var marker = Path()
        marker.move(to: CGPoint(x: markerX, y: top))
        marker.addLine(to: CGPoint(x: markerX, y: bottom))
        context.stroke(marker,
                       with: .color(Color.primary.opacity(0.30)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        let markerY = min(max(y(schedule.targetKelvin(at: now, calendar: calendar)), top + 3), bottom - 3)
        let dot = CGRect(x: markerX - 2.5, y: markerY - 2.5, width: 5, height: 5)
        context.fill(Path(ellipseIn: dot), with: .color(Color.accentColor))
    }

    private func drawAnnotations(in context: inout GraphicsContext,
                                 samples: [(minute: Double, kelvin: Double)],
                                 width: CGFloat,
                                 top: CGFloat,
                                 bottom: CGFloat,
                                 y: (Double) -> CGFloat,
                                 x: (Double) -> CGFloat) {
        let font = Font.system(size: 9.5, weight: .medium).monospacedDigit()
        let style = Color.secondary
        let horizontalMargin: CGFloat = 30

        func place(_ text: String, at point: CGPoint, preferAbove: Bool) {
            let label = context.resolve(Text(text).font(font).foregroundColor(style))
            let labelX = min(max(point.x, horizontalMargin), max(width - horizontalMargin, horizontalMargin))
            let above = preferAbove
                ? point.y - top >= 15
                : bottom - point.y < 15
            let labelY = min(max(above ? point.y - 8 : point.y + 9, top + 6), bottom - 5)
            context.draw(label, at: CGPoint(x: labelX, y: labelY), anchor: .center)
        }

        let dayKelvin = schedule.dayKelvin
        let nightKelvin = schedule.nightKelvin

        guard abs(dayKelvin - nightKelvin) >= 1 else {
            let center = plateauCenter(in: samples, level: dayKelvin) ?? 720
            place(kelvinLabel(dayKelvin),
                  at: CGPoint(x: x(center), y: y(dayKelvin)),
                  preferAbove: true)
            return
        }

        // Sit on the middle of the widest plateau so the label never crosses a
        // fade. The day label prefers the space above its level, the night label
        // the space below, which keeps both inside the plot.
        let dayCenter = plateauCenter(in: samples, level: dayKelvin) ?? 720
        let nightCenter = plateauCenter(in: samples, level: nightKelvin) ?? 120
        place(kelvinLabel(dayKelvin),
              at: CGPoint(x: x(dayCenter), y: y(dayKelvin)),
              preferAbove: true)
        place(kelvinLabel(nightKelvin),
              at: CGPoint(x: x(nightCenter), y: y(nightKelvin)),
              preferAbove: false)
    }

    /// Middle minute of the longest run of samples resting on `level`.
    private func plateauCenter(in samples: [(minute: Double, kelvin: Double)],
                               level: Double) -> Double? {
        var bestStart: Double?
        var bestEnd: Double?
        var runStart: Double?
        var runEnd: Double?

        func considerRun() {
            guard let start = runStart, let end = runEnd else { return }
            if bestStart == nil || end - start > (bestEnd ?? 0) - (bestStart ?? 0) {
                bestStart = start
                bestEnd = end
            }
            runStart = nil
            runEnd = nil
        }

        for sample in samples {
            if abs(sample.kelvin - level) <= 1 {
                if runStart == nil { runStart = sample.minute }
                runEnd = sample.minute
            } else {
                considerRun()
            }
        }
        considerRun()

        guard let start = bestStart, let end = bestEnd else { return nil }
        return (start + end) / 2
    }

    private func drawTimeAxis(in context: inout GraphicsContext,
                              width: CGFloat,
                              height: CGFloat,
                              x: (Double) -> CGFloat) {
        let font = Font.system(size: 9).monospacedDigit()
        let style = Color.secondary.opacity(0.9)
        let axisY = height - 6
        let marks: [(String, Double, UnitPoint)] = [
            ("0 h", 0, .leading),
            ("6 h", 360, .center),
            ("12 h", 720, .center),
            ("18 h", 1080, .center),
            ("24 h", 1440, .trailing),
        ]
        for mark in marks {
            let label = context.resolve(Text(mark.0).font(font).foregroundColor(style))
            context.draw(label, at: CGPoint(x: x(mark.1), y: axisY), anchor: mark.2)
        }
    }

    // MARK: - Text

    private func kelvinLabel(_ kelvin: Double) -> String {
        "\(Int(kelvin.rounded()).formatted()) K"
    }

    private var accessibilityValue: String {
        let night = "\(kelvinLabel(schedule.nightKelvin))"
        let day = "\(kelvinLabel(schedule.dayKelvin))"
        let start = String(format: "%02d:%02d", schedule.nightStart.hour, schedule.nightStart.minute)
        let end = String(format: "%02d:%02d", schedule.nightEnd.hour, schedule.nightEnd.minute)
        return "Nuit de \(start) à \(end), \(night). Jour \(day)."
    }
}
