import Foundation

/// A time-remaining projection for a single peripheral.
struct BatteryProjection {
    /// Hours until the battery hits 0% at the observed average rate. `nil` when
    /// there isn't enough data (too few samples, too little elapsed time, or
    /// no observed drop yet).
    let hoursRemaining: Double?

    /// Average drain rate in % per hour over the measurement window. 0 when
    /// the battery has held steady. `nil` when there isn't enough data.
    let drainRatePerHour: Double?

    /// How many hours of history the projection looked at. Useful for labels.
    let observedHours: Double

    /// Explanation of why a projection isn't available, for UI messaging.
    let reason: InsufficientReason?

    enum InsufficientReason {
        case notEnoughSamples
        case tooLittleElapsed
        case noDropYet
    }

    static func insufficient(_ reason: InsufficientReason, observedHours: Double = 0) -> BatteryProjection {
        BatteryProjection(
            hoursRemaining: nil,
            drainRatePerHour: nil,
            observedHours: observedHours,
            reason: reason
        )
    }
}

extension BatteryProjection {
    /// Short, human-readable time remaining: "3 days", "36 hours", "< 1 hour".
    var formattedRemaining: String? {
        guard let h = hoursRemaining else { return nil }
        if h < 1 { return "< 1 hour" }
        if h < 48 {
            let rounded = Int(h.rounded())
            return "\(rounded) \(rounded == 1 ? "hour" : "hours")"
        }
        if h < 24 * 14 {
            let days = Int((h / 24).rounded())
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        let weeks = Int((h / (24 * 7)).rounded())
        return "\(weeks) \(weeks == 1 ? "week" : "weeks")"
    }

    /// "1.5%/hr", "0.08%/hr", etc.
    var formattedRate: String? {
        guard let rate = drainRatePerHour else { return nil }
        if rate <= 0 { return "—" }
        if rate < 0.1 { return String(format: "%.2f%%/hr", rate) }
        return String(format: "%.1f%%/hr", rate)
    }
}

extension Device {
    /// Projects time remaining via **linear regression** over the current
    /// discharge cycle (samples after the most recent confirmed charge).
    ///
    /// Algorithm:
    /// 1. Determine the cutoff: the later of (a) `windowHours` ago, or (b)
    ///    the end of the most recent confirmed charge event. Confirmed
    ///    charges come from `chargeEvents()`'s strict detector — a sustained
    ///    ramp across consecutive connected samples — so single-sample
    ///    glitches (firmware sleep-recovery spikes, ADC noise) do **not**
    ///    truncate the discharge segment.
    /// 2. Take samples after the cutoff.
    /// 3. Fit a least-squares line to (time, percent).
    /// 4. Drain rate = –slope (in %/hour). A positive rate means draining.
    /// 5. Remaining = currentPercent / rate.
    ///
    /// Insufficient-data cases return `nil` with a reason so the UI can
    /// explain why.
    func projection(windowHours: Double = 24, now: Date = .now) -> BatteryProjection {
        let windowStart = now.addingTimeInterval(-windowHours * 3600)

        // Use the strict charge detector to find where the current discharge
        // segment starts. A confirmed-charge end after windowStart trims the
        // window forward; otherwise windowStart wins. This is the same
        // criterion `averageLifetimeHours` uses, so both stats agree on what
        // counts as "the current discharge."
        let confirmedChargeEnd = chargeEvents().last(where: { $0.isConfirmed })?.end
        let cutoff: Date
        if let chargeEnd = confirmedChargeEnd {
            cutoff = Swift.max(chargeEnd, windowStart)
        } else {
            cutoff = windowStart
        }

        let relevant = samples
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        guard relevant.count >= 2,
              let first = relevant.first,
              let last = relevant.last else {
            return .insufficient(.notEnoughSamples)
        }

        let elapsedHours = last.timestamp.timeIntervalSince(first.timestamp) / 3600
        guard elapsedHours >= (10.0 / 60.0) else {
            return .insufficient(.tooLittleElapsed, observedHours: elapsedHours)
        }

        // Least-squares linear regression on (seconds-since-first, percent).
        // Normalizing x to "seconds since first sample" keeps the arithmetic
        // numerically stable versus using absolute Unix timestamps.
        let baseTs = first.timestamp.timeIntervalSince1970
        let n = Double(relevant.count)
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0
        for sample in relevant {
            let x = sample.timestamp.timeIntervalSince1970 - baseTs
            let y = Double(sample.percent)
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }
        let denom = n * sumX2 - sumX * sumX
        guard denom > 0 else {
            return .insufficient(.notEnoughSamples)
        }

        // Slope in %/second. Drain rate is the negation, in %/hour.
        let slopePerSecond = (n * sumXY - sumX * sumY) / denom
        let ratePerHour = -slopePerSecond * 3600

        guard ratePerHour > 0 else {
            return BatteryProjection(
                hoursRemaining: nil,
                drainRatePerHour: 0,
                observedHours: elapsedHours,
                reason: .noDropYet
            )
        }

        let remaining = Double(last.percent) / ratePerHour
        return BatteryProjection(
            hoursRemaining: remaining,
            drainRatePerHour: ratePerHour,
            observedHours: elapsedHours,
            reason: nil
        )
    }
}
