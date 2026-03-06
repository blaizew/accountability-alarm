import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \AlarmEvent.firedAt, order: .reverse) private var events: [AlarmEvent]
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            List {
                if !events.isEmpty {
                    Section {
                        HStack {
                            StatCard(
                                title: "Compliance",
                                value: String(format: "%.0f%%", viewModel.complianceRate(events: events))
                            )
                            StatCard(
                                title: "Avg Snoozes",
                                value: String(format: "%.1f", viewModel.averageSnoozes(events: events))
                            )
                            StatCard(
                                title: "Total",
                                value: "\(events.count)"
                            )
                        }
                    }
                }

                if events.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Alarm events will appear here")
                    )
                } else {
                    Section("Recent Events") {
                        ForEach(events) { event in
                            HStack {
                                Image(systemName: viewModel.outcomeIcon(event.outcome))
                                    .foregroundStyle(colorForOutcome(event.outcome))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.alarm?.label ?? "Alarm")
                                        .font(.headline)
                                    Text(event.firedAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(event.outcome.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if event.snoozeCount > 0 {
                                        Text("\(event.snoozeCount) snooze\(event.snoozeCount == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func colorForOutcome(_ outcome: String) -> Color {
        switch outcome {
        case "complied": .green
        case "snoozed_then_complied": .yellow
        case "overridden": .red
        case "ignored": .gray
        default: .gray
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
