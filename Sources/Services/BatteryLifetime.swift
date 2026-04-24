import Foundation

/// A detected charging episode for a single peripheral.
struct ChargeEvent {
    let start: Date
    let end: Date
    let fromPercent: Int
    let toPercent: Int
    /// Confirmed events have a visible ramp across actively-connected samples.
    /// Unconfirmed events are inferred from a big timestamp gap with a higher
    /// percent on reconnect — likely charged while disconnected.
    let isConfirmed: Bool
}

extension Device {
    /// Walks the sample history and returns every detected charge event.
    ///
    /// Confirmed events require a visible ramp: ≥ minRise percent rise spread
    /// across consecutive samples, each within `maxRampStepSeconds` of the
    /// previous. A single isolated upward spike (sleep recovery, ADC noise)
    /// fails this and is ignored.
    ///
    /// Unconfirmed events model "charged while the dongle was disconnected":
    /// a gap ≥ `minDisconnectGapSeconds` followed by a reading ≥
    /// `minDisconnectRise` percent higher than the last known value.
    func chargeEvents(
        minRise: Int = 3,
        maxRampStepSeconds: TimeInterval = 300,
        minDisconnectGapSeconds: TimeInterval = 1800,
        minDisconnectRise: Int = 5
    ) -> [ChargeEvent] {
        let sorted = samples.sorted(by: { $0.timestamp < $1.timestamp })
        guard sorted.count >= 2 else { return [] }

        var events: [ChargeEvent] = []
        var i = 0
        while i < sorted.count - 1 {
            let current = sorted[i]
            let next = sorted[i + 1]
            let dt = next.timestamp.timeIntervalSince(current.timestamp)
            let dp = next.percent - current.percent

            if dp > 0, dt <= maxRampStepSeconds {
                // Extend the ramp while subsequent samples are non-decreasing
                // (tolerating a 1% dip for ADC noise) within the step budget.
                var rampEnd = i + 1
                var peak = next.percent
                while rampEnd + 1 < sorted.count {
                    let prev = sorted[rampEnd]
                    let cand = sorted[rampEnd + 1]
                    let stepDt = cand.timestamp.timeIntervalSince(prev.timestamp)
                    guard stepDt <= maxRampStepSeconds,
                          cand.percent >= prev.percent - 1 else { break }
                    rampEnd += 1
                    peak = Swift.max(peak, cand.percent)
                }

                if peak - current.percent >= minRise {
                    events.append(ChargeEvent(
                        start: current.timestamp,
                        end: sorted[rampEnd].timestamp,
                        fromPercent: current.percent,
                        toPercent: peak,
                        isConfirmed: true
                    ))
                }
                i = rampEnd + 1
                continue
            }

            if dt >= minDisconnectGapSeconds, dp >= minDisconnectRise {
                events.append(ChargeEvent(
                    start: current.timestamp,
                    end: next.timestamp,
                    fromPercent: current.percent,
                    toPercent: next.percent,
                    isConfirmed: false
                ))
            }

            i += 1
        }
        return events
    }

    /// Most recent charge of any confidence. Good enough for the "Last charged"
    /// stat — users want the ambient signal, not forensic certainty.
    var lastCharged: Date? {
        chargeEvents().last?.end
    }

    /// Average time a full 100% drain takes for this peripheral. Built from
    /// discharge segments bounded by **confirmed** charge events only, so
    /// disconnect-inferred (unknown-timing) transitions don't pollute the mean.
    func averageLifetimeHours(
        minSegmentSeconds: TimeInterval = 1800,
        minSegmentDrop: Int = 5
    ) -> Double? {
        let sorted = samples.sorted(by: { $0.timestamp < $1.timestamp })
        guard sorted.count >= 2 else { return nil }

        let confirmedEnds = chargeEvents().filter(\.isConfirmed).map(\.end)

        // Walk samples, opening a new segment after each confirmed charge end.
        var segments: [(start: BatterySample, end: BatterySample)] = []
        var segStart = sorted[0]
        var segEnd = sorted[0]
        var pendingChargeIdx = 0

        for sample in sorted.dropFirst() {
            // If this sample is at or after the next confirmed charge end,
            // close the current segment and re-open from this sample.
            while pendingChargeIdx < confirmedEnds.count,
                  sample.timestamp >= confirmedEnds[pendingChargeIdx] {
                segments.append((segStart, segEnd))
                segStart = sample
                segEnd = sample
                pendingChargeIdx += 1
            }
            segEnd = sample
        }
        segments.append((segStart, segEnd))

        let normalized: [Double] = segments.compactMap { seg in
            let drop = seg.start.percent - seg.end.percent
            let hours = seg.end.timestamp.timeIntervalSince(seg.start.timestamp) / 3600
            guard drop >= minSegmentDrop, hours >= minSegmentSeconds / 3600 else { return nil }
            return (hours / Double(drop)) * 100
        }

        guard !normalized.isEmpty else { return nil }
        return normalized.reduce(0, +) / Double(normalized.count)
    }
}

extension Keyboard {
    /// Average battery life across all peripherals, in hours.
    var averageBatteryLifeHours: Double? {
        let values = peripherals.compactMap { $0.averageLifetimeHours() }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Most recent charge across all peripherals.
    var lastCharged: Date? {
        peripherals.compactMap(\.lastCharged).max()
    }
}

/// Formats a duration for human-readable display. Used for Total Usage,
/// Current Session, and Average Battery Life.
func formatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24
    let weeks = days / 7

    if seconds < 60 { return "< 1m" }
    if minutes < 60 {
        return "\(Int(minutes.rounded()))m"
    }
    if hours < 24 {
        let h = Int(hours)
        let m = Int(minutes.truncatingRemainder(dividingBy: 60))
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
    if days < 14 {
        let d = Int(days)
        let h = Int(hours.truncatingRemainder(dividingBy: 24))
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }
    if weeks < 12 {
        return "\(Int(weeks.rounded()))w"
    }
    let months = days / 30
    return "\(Int(months.rounded()))mo"
}
