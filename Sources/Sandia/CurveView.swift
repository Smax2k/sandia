import AppKit
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
        .accessibilityLabel(L("Temperature curve over 24 hours"))
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

        let marker = drawNowMarker(in: &context,
                                   width: width,
                                   top: top,
                                   bottom: bottom,
                                   calendar: calendar,
                                   y: y,
                                   x: x)
        let annotations = drawAnnotations(in: &context,
                                          samples: samples,
                                          width: width,
                                          top: top,
                                          bottom: bottom,
                                          y: y,
                                          x: x)
        drawNowLabel(in: &context,
                     text: marker.label,
                     dot: marker.dot,
                     radius: marker.radius,
                     width: width,
                     top: top,
                     bottom: bottom,
                     avoiding: annotations)

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

    /// The marker is deliberately drawn inside the plot: at 23:59 the true time
    /// coordinate sits on the frame edge, where a dot would be clipped in half.
    private func drawNowMarker(in context: inout GraphicsContext,
                               width: CGFloat,
                               top: CGFloat,
                               bottom: CGFloat,
                               calendar: Calendar,
                               y: (Double) -> CGFloat,
                               x: (Double) -> CGFloat) -> (dot: CGPoint, radius: CGFloat, label: String) {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let hour = parts.hour ?? 0
        let minuteOfHour = parts.minute ?? 0
        let minute = Double(hour) * 60
            + Double(minuteOfHour)
            + Double(parts.second ?? 0) / 60

        let radius: CGFloat = 4.5
        let halo: CGFloat = 2.5
        let inset = radius + halo
        let markerX = min(max(x(minute), inset), max(width - inset, inset))
        let markerY = min(max(y(schedule.targetKelvin(at: now, calendar: calendar)),
                              top + inset), bottom - inset)

        var marker = Path()
        marker.move(to: CGPoint(x: markerX, y: top))
        marker.addLine(to: CGPoint(x: markerX, y: bottom))
        context.stroke(marker,
                       with: .color(Color.accentColor),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        // A light rim keeps the dot readable over the accent curve, the night
        // bands and the plateau lines; primary follows the system appearance.
        let haloRect = CGRect(x: markerX - radius - halo, y: markerY - radius - halo,
                              width: (radius + halo) * 2, height: (radius + halo) * 2)
        context.fill(Path(ellipseIn: haloRect), with: .color(Color.primary.opacity(0.85)))
        let dotRect = CGRect(x: markerX - radius, y: markerY - radius,
                             width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(Color.accentColor))

        return (CGPoint(x: markerX, y: markerY),
                radius + halo,
                String(format: "%02d:%02d", hour, minuteOfHour))
    }

    /// The time sits beside the dot, on the side that stays inside the plot and
    /// clear of the temperature labels.
    private func drawNowLabel(in context: inout GraphicsContext,
                              text: String,
                              dot: CGPoint,
                              radius: CGFloat,
                              width: CGFloat,
                              top: CGFloat,
                              bottom: CGFloat,
                              avoiding obstacles: [CGRect]) {
        let font = Font.system(size: 9.5, weight: .semibold).monospacedDigit()
        let resolved = context.resolve(Text(text).font(font).foregroundColor(Color.primary))
        let textSize = resolved.measure(in: CGSize(width: width, height: 40))
        let chipSize = CGSize(width: textSize.width + 8, height: textSize.height + 2)
        let gap = radius + 2
        let plot = CGRect(x: 0, y: top, width: width, height: bottom - top)

        // Temperature labels sit above their plateau line, so the space under
        // the dot is the safest place for the time; sides and top are fallbacks
        // for a marker close to the bottom of the plot.
        let below = gap + chipSize.height / 2
        let beside = gap + chipSize.width / 2
        let farBelow = below + chipSize.height + 6
        let farBeside = beside + chipSize.width + 8
        let offsets: [CGSize] = [
            CGSize(width: 0, height: below),
            CGSize(width: 0, height: -below),
            CGSize(width: beside, height: 0),
            CGSize(width: -beside, height: 0),
            CGSize(width: beside, height: below),
            CGSize(width: -beside, height: below),
            CGSize(width: beside, height: -below),
            CGSize(width: -beside, height: -below),
            CGSize(width: 0, height: -farBelow),
            CGSize(width: 0, height: farBelow),
            CGSize(width: farBeside, height: 0),
            CGSize(width: -farBeside, height: 0),
        ]

        func clamped(_ center: CGPoint) -> CGRect {
            let x = min(max(center.x - chipSize.width / 2, plot.minX + 1),
                        max(plot.maxX - chipSize.width - 1, plot.minX + 1))
            let y = min(max(center.y - chipSize.height / 2, plot.minY + 1),
                        max(plot.maxY - chipSize.height - 1, plot.minY + 1))
            return CGRect(origin: CGPoint(x: x, y: y), size: chipSize)
        }

        let dotRect = CGRect(x: dot.x - radius, y: dot.y - radius,
                             width: radius * 2, height: radius * 2).insetBy(dx: -1, dy: -1)
        let blocked = obstacles + [dotRect]
        var chip = clamped(CGPoint(x: dot.x, y: dot.y - farBelow))
        for offset in offsets {
            let candidate = clamped(CGPoint(x: dot.x + offset.width, y: dot.y + offset.height))
            if !blocked.contains(where: { $0.intersects(candidate.insetBy(dx: -1, dy: -1)) }) {
                chip = candidate
                break
            }
        }

        let background = Path(roundedRect: chip, cornerRadius: 3)
        context.fill(background, with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
        context.draw(resolved, at: CGPoint(x: chip.midX, y: chip.midY), anchor: .center)
    }

    private func drawAnnotations(in context: inout GraphicsContext,
                                 samples: [(minute: Double, kelvin: Double)],
                                 width: CGFloat,
                                 top: CGFloat,
                                 bottom: CGFloat,
                                 y: (Double) -> CGFloat,
                                 x: (Double) -> CGFloat) -> [CGRect] {
        let font = Font.system(size: 9.5, weight: .medium).monospacedDigit()
        let style = Color.secondary
        let horizontalMargin: CGFloat = 30
        var drawn: [CGRect] = []

        func place(_ text: String, at point: CGPoint, preferAbove: Bool) {
            let label = context.resolve(Text(text).font(font).foregroundColor(style))
            let labelX = min(max(point.x, horizontalMargin), max(width - horizontalMargin, horizontalMargin))
            let above = preferAbove
                ? point.y - top >= 15
                : bottom - point.y < 15
            let labelY = min(max(above ? point.y - 8 : point.y + 9, top + 6), bottom - 5)
            context.draw(label, at: CGPoint(x: labelX, y: labelY), anchor: .center)
            // A slightly generous box, so the current-time label keeps clear of
            // the text even if its measured bounds are tighter than the ink.
            let estimated = CGSize(width: CGFloat(text.count) * 6.2 + 2, height: 13)
            drawn.append(CGRect(x: labelX - estimated.width / 2, y: labelY - estimated.height / 2,
                                width: estimated.width, height: estimated.height))
        }

        let dayKelvin = schedule.dayKelvin
        let nightKelvin = schedule.nightKelvin

        guard abs(dayKelvin - nightKelvin) >= 1 else {
            let center = plateauCenter(in: samples, level: dayKelvin) ?? 720
            place(kelvinLabel(dayKelvin),
                  at: CGPoint(x: x(center), y: y(dayKelvin)),
                  preferAbove: true)
            return drawn
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
        return drawn
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
        return L("Night from %@ to %@, %@. Day %@.", start, end, night, day)
    }
}
