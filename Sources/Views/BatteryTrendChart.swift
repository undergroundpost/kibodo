import SwiftUI
import SwiftData
import Charts

struct BatteryTrendChart: View {
    let keyboard: Keyboard
    @Environment(\.themeColors) private var colors
    @State private var model = RenderModel.empty
    @State private var refreshTick = Date()

    /// Pre-computed bundle of everything the chart needs to render.
    /// Recomputed only when the underlying sample set changes or on the
    /// hourly tick — never per scroll-frame.
    private struct RenderModel {
        var dotPoints: [DotPoint]
        var trendPoints: [TrendPoint]
        var rangeStart: Date
        var rangeEnd: Date
        var yLower: Int
        var yUpper: Int
        var yTicks: [Int]
        var xTicks: [Date]
        var axisScale: AxisScale
        var ratesLine: String?

        static let empty = RenderModel(
            dotPoints: [], trendPoints: [],
            rangeStart: .now, rangeEnd: .now,
            yLower: 0, yUpper: 100, yTicks: [],
            xTicks: [], axisScale: .days(step: 1), ratesLine: nil
        )
    }

    private struct DotPoint: Identifiable {
        let id: PersistentIdentifier
        let timestamp: Date
        let percent: Int
    }

    private struct TrendPoint: Identifiable {
        let time: Date
        let value: Double
        var id: Date { time }
    }

    private enum AxisScale {
        case hours(step: Int)
        case days(step: Int)
    }

    var body: some View {
        Group {
            if model.dotPoints.isEmpty && model.trendPoints.isEmpty {
                Text("No battery history yet.")
                    .font(.appBody)
                    .foregroundStyle(colors.sub)
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    chart
                    if let line = model.ratesLine {
                        Text(line)
                            .font(.appTitle3)
                            .foregroundStyle(colors.sub)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .onAppear { recompute() }
        // Recompute whenever the actual sample volume changes (a meaningful
        // proxy for "data has new content"). Avoids reacting to in-place
        // property tweaks like lastSeen ticking.
        .onChange(of: totalSampleCount) { _, _ in recompute() }
        // Slow background tick so rangeStart slides forward over the month
        // window without polling. Every 15 minutes is more than enough — a
        // user staring at the chart won't notice the boundary advancing.
        .background(
            TimelineView(.periodic(from: .now, by: 60 * 15)) { context in
                Color.clear
                    .onChange(of: context.date) { _, newDate in
                        refreshTick = newDate
                        recompute()
                    }
            }
        )
    }

    private var totalSampleCount: Int {
        keyboard.peripherals.reduce(0) { $0 + $1.samples.count }
    }

    // MARK: - Chart view

    private var chart: some View {
        Chart {
            ForEach(model.dotPoints) { dot in
                PointMark(
                    x: .value("Time", dot.timestamp),
                    y: .value("Battery", dot.percent)
                )
                .symbolSize(12)
                .foregroundStyle(colors.sub.opacity(0.35))
            }
            ForEach(model.trendPoints) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Battery", point.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(colors.main)
            }
        }
        .chartYScale(domain: model.yLower...model.yUpper)
        .chartXScale(domain: model.rangeStart...model.rangeEnd)
        .chartYAxis {
            AxisMarks(position: .trailing, values: model.yTicks) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.appCaption)
                            .foregroundStyle(colors.sub)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: model.xTicks) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(for: date))
                            .font(.appCaption)
                            .foregroundStyle(colors.sub)
                    }
                }
            }
        }
        .chartYAxisLabel(position: .trailing, alignment: .center) {
            Text("Battery")
                .font(.appCaption)
                .foregroundStyle(colors.sub)
        }
        .frame(height: 240)
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch model.axisScale {
        case .hours: formatter.dateFormat = "HH:mm"
        case .days:  formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    // MARK: - Recompute

    /// Rebuilds the entire render model in one pass over the data. This is
    /// the only place that touches `keyboard.peripherals` for chart data —
    /// once per data change or hourly tick, never per render.
    private func recompute() {
        let now = Date()
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now

        // One walk per peripheral, in timestamp order.
        var dots: [DotPoint] = []
        var inRangeForTrend: [BatterySample] = []
        var earliest: Date?

        for peripheral in keyboard.peripherals {
            let sorted = peripheral.samples.sorted { $0.timestamp < $1.timestamp }
            var lastPercent: Int? = nil
            for sample in sorted {
                if earliest == nil || sample.timestamp < earliest! {
                    earliest = sample.timestamp
                }
                guard sample.timestamp >= monthAgo else { continue }
                inRangeForTrend.append(sample)
                // Change-point filter: only emit a dot when percent differs
                // from the previous sample on the same peripheral. Heartbeat
                // samples that repeat the prior value are skipped.
                if sample.percent != lastPercent {
                    dots.append(DotPoint(
                        id: sample.persistentModelID,
                        timestamp: sample.timestamp,
                        percent: sample.percent
                    ))
                    lastPercent = sample.percent
                }
            }
        }

        let rangeStart = Swift.max(earliest ?? monthAgo, monthAgo)
        let rangeEnd = now

        // Trend line: bucket-averaged. Bucket size matches the chart's range.
        let hours = rangeEnd.timeIntervalSince(rangeStart) / 3600
        let bucket: TimeInterval
        if hours < 48 { bucket = 15 * 60 }
        else if hours < 24 * 7 { bucket = 60 * 60 }
        else { bucket = 6 * 60 * 60 }

        var trendBuckets: [Date: [Int]] = [:]
        for sample in inRangeForTrend {
            let bucketStart = Date(
                timeIntervalSince1970:
                    floor(sample.timestamp.timeIntervalSince1970 / bucket) * bucket
            )
            trendBuckets[bucketStart, default: []].append(sample.percent)
        }
        let trend = trendBuckets
            .map { TrendPoint(time: $0.key, value: Double($0.value.reduce(0, +)) / Double($0.value.count)) }
            .sorted { $0.time < $1.time }

        // Y-axis: zoomed to the data, clamped 0-100, minimum 20-pt span.
        let percentValues = inRangeForTrend.map(\.percent)
        let yLower: Int
        let yUpper: Int
        if let dataMin = percentValues.min(), let dataMax = percentValues.max() {
            var lo = Swift.max(0, ((dataMin - 5) / 10) * 10)
            var hi = Swift.min(100, ((dataMax + 5 + 9) / 10) * 10)
            if hi - lo < 20 {
                let slack = 20 - (hi - lo)
                let growUp = Swift.min(100 - hi, slack / 2)
                let growDown = slack - growUp
                hi += growUp
                lo = Swift.max(0, lo - growDown)
            }
            yLower = lo
            yUpper = hi
        } else {
            yLower = 0
            yUpper = 100
        }
        let yTicks = Array(stride(from: yLower, through: yUpper, by: 10))

        // Axis scale + tick dates.
        let days = hours / 24
        let scale: AxisScale
        if hours < 6   { scale = .hours(step: 1) }
        else if hours < 12  { scale = .hours(step: 2) }
        else if hours < 24  { scale = .hours(step: 4) }
        else if hours < 48  { scale = .hours(step: 6) }
        else if days  < 7   { scale = .days(step: 1) }
        else if days  < 14  { scale = .days(step: 2) }
        else if days  < 30  { scale = .days(step: 3) }
        else if days  < 90  { scale = .days(step: 7) }
        else                { scale = .days(step: 30) }

        let xTicks = computeXTicks(scale: scale, rangeStart: rangeStart, rangeEnd: rangeEnd)

        // Per-peripheral discharge rate footer line.
        let ratesLine: String?
        let sortedPeripherals = keyboard.peripherals.sorted(by: { $0.slot < $1.slot })
        if sortedPeripherals.isEmpty {
            ratesLine = nil
        } else {
            let parts = sortedPeripherals.map { device -> String in
                let rate = device.projection().formattedRate ?? "—"
                return "\(device.displayName) \(rate)"
            }
            ratesLine = parts.joined(separator: " · ")
        }

        // Filter dots once more to the actual displayed range — the per-peripheral
        // walk above included earlier samples for the lastPercent state machine.
        let dotsInRange = dots.filter { $0.timestamp >= rangeStart }

        model = RenderModel(
            dotPoints: dotsInRange,
            trendPoints: trend,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            yLower: yLower,
            yUpper: yUpper,
            yTicks: yTicks,
            xTicks: xTicks,
            axisScale: scale,
            ratesLine: ratesLine
        )
    }

    private func computeXTicks(scale: AxisScale, rangeStart: Date, rangeEnd: Date) -> [Date] {
        let calendar = Calendar.current
        switch scale {
        case .hours(let step):
            let comps = calendar.dateComponents([.year, .month, .day, .hour], from: rangeStart)
            guard var cursor = calendar.date(from: comps) else { return [] }
            if cursor < rangeStart {
                cursor = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? cursor
            }
            let hour = calendar.component(.hour, from: cursor)
            let remainder = hour % step
            if remainder != 0 {
                cursor = calendar.date(byAdding: .hour, value: step - remainder, to: cursor) ?? cursor
            }
            var ticks: [Date] = []
            while cursor <= rangeEnd {
                ticks.append(cursor)
                cursor = calendar.date(byAdding: .hour, value: step, to: cursor)
                    ?? cursor.addingTimeInterval(Double(step) * 3600)
            }
            return ticks

        case .days(let step):
            var cursor = calendar.startOfDay(for: rangeStart)
            if cursor < rangeStart {
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
            var ticks: [Date] = []
            while cursor <= rangeEnd {
                ticks.append(cursor)
                cursor = calendar.date(byAdding: .day, value: step, to: cursor)
                    ?? cursor.addingTimeInterval(Double(step) * 86400)
            }
            return ticks
        }
    }
}
