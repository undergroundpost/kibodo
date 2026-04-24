import SwiftUI
import SwiftData
import Charts

struct BatteryTrendChart: View {
    let keyboard: Keyboard
    @Environment(\.themeColors) private var colors

    private struct TrendPoint: Identifiable {
        let time: Date
        let value: Double
        var id: Date { time }
    }

    private var rangeStart: Date {
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let allStamps = keyboard.peripherals.flatMap(\.samples).map(\.timestamp)
        guard let earliest = allStamps.min() else { return monthAgo }
        return Swift.max(earliest, monthAgo)
    }

    private var rangeEnd: Date { Date() }

    private var samplesInRange: [BatterySample] {
        keyboard.peripherals
            .flatMap(\.samples)
            .filter { $0.timestamp >= rangeStart }
    }

    private var bucketSize: TimeInterval {
        let hours = rangeEnd.timeIntervalSince(rangeStart) / 3600
        if hours < 48 { return 15 * 60 }
        if hours < 24 * 7 { return 60 * 60 }
        return 6 * 60 * 60
    }

    private var trendPoints: [TrendPoint] {
        let bucket = bucketSize
        var buckets: [Date: [Int]] = [:]
        for sample in samplesInRange {
            let bucketStart = Date(
                timeIntervalSince1970:
                    floor(sample.timestamp.timeIntervalSince1970 / bucket) * bucket
            )
            buckets[bucketStart, default: []].append(sample.percent)
        }
        return buckets
            .map { TrendPoint(time: $0.key, value: Double($0.value.reduce(0, +)) / Double($0.value.count)) }
            .sorted { $0.time < $1.time }
    }

    /// Dynamic Y-axis range. Zooms to the data: min rounded down to nearest 10,
    /// max rounded up to nearest 10, with a half-tick pad on each side. Clamped
    /// to 0...100 and a minimum 20-point span so sparse data still reads well.
    private var yAxisDomain: ClosedRange<Int> {
        let values = samplesInRange.map(\.percent)
        guard let dataMin = values.min(), let dataMax = values.max() else {
            return 0...100
        }
        var lower = Swift.max(0, ((dataMin - 5) / 10) * 10)
        var upper = Swift.min(100, ((dataMax + 5 + 9) / 10) * 10)
        if upper - lower < 20 {
            let slack = 20 - (upper - lower)
            let growUp = Swift.min(100 - upper, slack / 2)
            let growDown = slack - growUp
            upper += growUp
            lower = Swift.max(0, lower - growDown)
        }
        return lower...upper
    }

    /// Axis granularity, chosen by total range.
    private enum AxisScale {
        case hours(step: Int)
        case days(step: Int)
    }

    private var axisScale: AxisScale {
        let hours = rangeEnd.timeIntervalSince(rangeStart) / 3600
        let days = hours / 24
        if hours < 6   { return .hours(step: 1) }
        if hours < 12  { return .hours(step: 2) }
        if hours < 24  { return .hours(step: 4) }
        if hours < 48  { return .hours(step: 6) }
        if days  < 7   { return .days(step: 1) }
        if days  < 14  { return .days(step: 2) }
        if days  < 30  { return .days(step: 3) }
        if days  < 90  { return .days(step: 7) }
        return .days(step: 30)
    }

    /// X-axis ticks aligned to natural boundaries of the chosen scale.
    /// - `.hours(step)` — every `step` hours, aligned to multiples of `step`
    ///   within each day (e.g. step=6 gives 00:00, 06:00, 12:00, 18:00).
    /// - `.days(step)` — every `step` days, aligned to midnight.
    private var xAxisTicks: [Date] {
        let calendar = Calendar.current

        switch axisScale {
        case .hours(let step):
            // Start at the next hour boundary at or after rangeStart, then
            // advance to the next multiple of `step` hours within the day.
            var comps = calendar.dateComponents([.year, .month, .day, .hour], from: rangeStart)
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

    private var peripheralRatesLine: String? {
        let sorted = keyboard.peripherals.sorted(by: { $0.slot < $1.slot })
        guard !sorted.isEmpty else { return nil }
        let parts = sorted.map { device -> String in
            let rate = device.projection().formattedRate ?? "—"
            return "\(device.displayName) \(rate)"
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if samplesInRange.isEmpty {
            Text("No battery history yet.")
                .font(.appBody)
                .foregroundStyle(colors.sub)
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                chart
                if let line = peripheralRatesLine {
                    Text(line)
                        .font(.appTitle3)
                        .foregroundStyle(colors.sub)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(samplesInRange) { sample in
                PointMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Battery", sample.percent)
                )
                .symbolSize(12)
                .foregroundStyle(colors.sub.opacity(0.35))
            }

            ForEach(trendPoints) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Battery", point.value)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(colors.main)
            }
        }
        .chartYScale(domain: yAxisDomain.lowerBound...yAxisDomain.upperBound)
        .chartXScale(domain: rangeStart...rangeEnd)
        .chartYAxis {
            AxisMarks(
                position: .trailing,
                values: Array(stride(from: yAxisDomain.lowerBound,
                                     through: yAxisDomain.upperBound,
                                     by: 10))
            ) { value in
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
            AxisMarks(values: xAxisTicks) { value in
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
        switch axisScale {
        case .hours: formatter.dateFormat = "HH:mm"
        case .days:  formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}
