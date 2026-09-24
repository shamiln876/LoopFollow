// LoopFollow
// InfoTableView.swift

import SwiftUI

struct InfoTableView: View {
    @ObservedObject var infoManager: InfoManager
    var timeZoneOverride: String?

    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 21

    var body: some View {
        List {
            if let tz = timeZoneOverride {
                row(name: "Time Zone", value: tz)
            }
            ForEach(infoManager.visibleRows) { item in
                if (item.id == InfoType.iob.rawValue || item.id == InfoType.cob.rawValue),
                   item.numericValue != nil {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(spacing: 0) {
                            rowContent(name: item.name, value: item.value, valueColor: color(for: item))
                            if let end = item.estimatedEnd,
                               let updated = item.estimateUpdatedAt,
                               context.date.timeIntervalSince(updated) < 15 * 60,
                               end > context.date {
                                let remaining = Int(ceil(end.timeIntervalSince(context.date) / 60))
                                let icon = item.id == InfoType.iob.rawValue ? "syringe" : "fork.knife"
                                let label = item.id == InfoType.iob.rawValue ? "bolus tail" : "COB trend"
                                Label("~\(remaining / 60)h \(remaining % 60)m \(label)", systemImage: icon)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .frame(minHeight: rowHeight)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    }
                } else {
                    row(name: item.name, value: item.value, valueColor: color(for: item))
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, rowHeight)
    }

    /// Threshold-based color for a row's value, or nil to use the default color.
    private func color(for item: InfoData) -> Color? {
        guard let numericValue = item.numericValue,
              let type = InfoType(rawValue: item.id),
              let config = type.colorConfig
        else { return nil }
        return Storage.shared.infoDisplayItems.value.item(for: type)?
            .coloring.color(for: numericValue, direction: config.direction)
    }

    private func row(name: String, value: String, valueColor: Color? = nil) -> some View {
        rowContent(name: name, value: value, valueColor: valueColor)
            .frame(minHeight: rowHeight)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
    }

    private func rowContent(name: String, value: String, valueColor: Color? = nil) -> some View {
        // Show a placeholder for any field that has no value yet,
        // so the row reads as "no data" rather than appearing empty.
        let displayValue = value.isEmpty ? "—" : value

        return ViewThatFits(in: .horizontal) {
            // Preferred: compact single line (label — value)
            HStack {
                Text(name)
                Spacer()
                Text(displayValue)
                    .foregroundStyle(valueColor ?? .primary)
            }

            // Fallback when the single line won't fit: label over value
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                Text(displayValue)
                    .foregroundStyle(valueColor ?? .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.system(size: fontSize))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}
