import SwiftUI
import SwiftData
import Charts

struct LayerUsageChart: View {
    let keyboard: Keyboard
    @Environment(\.themeColors) private var colors

    private struct LayerEntry: Identifiable {
        let index: Int
        let label: String
        let percent: Double
        var id: Int { index }
    }

    /// When one layer dominates (≥ 2× the runner-up), peel it off so the bar
    /// chart can auto-scale to the remaining layers. Otherwise show everything
    /// on a full 0–100 axis.
    private struct LayoutPlan {
        let displayed: [LayerEntry]
        let excluded: LayerEntry?
        let upperBound: Double
        let tickValues: [Double]
    }

    /// Hand-picked tick schedules so axis labels are always round numbers.
    private static let axisSchedules: [(upper: Double, ticks: [Double])] = [
        (1,   [0, 0.25, 0.5, 0.75, 1]),
        (2,   [0, 0.5, 1, 1.5, 2]),
        (5,   [0, 1, 2, 3, 4, 5]),
        (10,  [0, 2.5, 5, 7.5, 10]),
        (20,  [0, 5, 10, 15, 20]),
        (25,  [0, 5, 10, 15, 20, 25]),
        (50,  [0, 10, 20, 30, 40, 50]),
        (100, [0, 25, 50, 75, 100]),
    ]

    private var plan: LayoutPlan {
        let all = entries
        let sortedByPercent = all.sorted { $0.percent > $1.percent }
        let top = sortedByPercent.first
        let runnerUp = sortedByPercent.dropFirst().first

        let shouldSplit: Bool
        if let top, let runnerUp, runnerUp.percent > 0 {
            shouldSplit = top.percent >= 2 * runnerUp.percent
        } else {
            shouldSplit = false
        }

        if shouldSplit, let top {
            let rest = all.filter { $0.index != top.index }
            let maxVisible = rest.map(\.percent).max() ?? 0
            let schedule = Self.axisSchedules.first(where: { $0.upper >= maxVisible })
                ?? (upper: 100.0, ticks: [0, 25, 50, 75, 100])
            return LayoutPlan(
                displayed: rest,
                excluded: top,
                upperBound: schedule.upper,
                tickValues: schedule.ticks
            )
        }

        return LayoutPlan(
            displayed: all,
            excluded: nil,
            upperBound: 100,
            tickValues: [0, 25, 50, 75, 100]
        )
    }

    private var entries: [LayerEntry] {
        var totals: [Int: TimeInterval] = [:]
        for row in keyboard.layerUsage {
            totals[row.layerIndex, default: 0] += row.totalSeconds
        }

        // Credit the time since the current layer became active — otherwise a
        // layer you've been sitting on for hours shows as zero until you move off.
        if let current = keyboard.activeLayerIndex,
           let startedAt = keyboard.lastLayerTransitionAt {
            let inflight = Date().timeIntervalSince(startedAt)
            if inflight > 0 {
                totals[current, default: 0] += inflight
            }
        }

        let grandTotal = totals.values.reduce(0, +)
        guard grandTotal > 0 else { return [] }

        return totals
            .map { index, seconds -> LayerEntry in
                let label: String
                if index < keyboard.layerLabels.count, !keyboard.layerLabels[index].isEmpty {
                    label = keyboard.layerLabels[index]
                } else {
                    label = "Layer \(index)"
                }
                return LayerEntry(
                    index: index,
                    label: label,
                    percent: (seconds / grandTotal) * 100
                )
            }
            .sorted { $0.index < $1.index }
    }

    var body: some View {
        if entries.isEmpty {
            Text("No layer history yet.")
                .font(.appBody)
                .foregroundStyle(colors.sub)
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .leading)
        } else {
            let plan = plan
            VStack(alignment: .leading, spacing: 16) {
                chart(plan: plan)
                if let excluded = plan.excluded {
                    Text("\(excluded.label) usage: \(formatted(excluded.percent))")
                        .font(.appTitle3)
                        .foregroundStyle(colors.sub)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private func chart(plan: LayoutPlan) -> some View {
        Chart {
            ForEach(plan.displayed) { entry in
                BarMark(
                    x: .value("Layer", entry.label),
                    y: .value("Usage", entry.percent)
                )
                .foregroundStyle(colors.main)
                .annotation(position: .top) {
                    Text(formatted(entry.percent))
                        .font(.appCaption)
                        .foregroundStyle(colors.sub)
                }
            }
        }
        .chartYScale(domain: 0...plan.upperBound)
        .chartYAxis {
            AxisMarks(position: .trailing, values: plan.tickValues) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(tickLabel(v))
                            .font(.appCaption)
                            .foregroundStyle(colors.sub)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.appCaption)
                            .foregroundStyle(colors.sub)
                    }
                }
            }
        }
        .chartYAxisLabel(position: .trailing, alignment: .center) {
            Text("Usage")
                .font(.appCaption)
                .foregroundStyle(colors.sub)
        }
        .frame(height: 240)
    }

    private func formatted(_ percent: Double) -> String {
        if percent < 0.1 { return "<0.1%" }
        if percent < 10 { return String(format: "%.1f%%", percent) }
        return String(format: "%.0f%%", percent)
    }

    private func tickLabel(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }
}
