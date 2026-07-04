import SwiftUI
import SwiftData
import UIKit

/// Reverse-chronological list of every event captured by `LogService`. Used
/// to reconstruct what happened after an incident — especially useful for
/// alarm misbehavior that occurred while the app was suspended or
/// Downtime-restricted.
struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\AlarmLogEntry.timestamp, order: .reverse)])
    private var entries: [AlarmLogEntry]

    @State private var filter: LogCategory? = nil
    @State private var showCopied = false

    private var filtered: [AlarmLogEntry] {
        guard let filter else { return entries }
        return entries.filter { $0.category == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            LTopBar(
                left: "DEBUG · \(filtered.count) ENTRIES",
                right: showCopied ? "COPIED" : "COPY",
                rightColor: showCopied ? L.Palette.goodGreen : L.Palette.muted,
                onRight: copyAll
            )

            filterBar

            if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { entry in
                        row(entry)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(L.Palette.bg)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(L.Palette.bg)
                .environment(\.defaultMinListRowHeight, 0)
            }
        }
        .background(L.Palette.bg.ignoresSafeArea())
        .foregroundStyle(L.Palette.fg)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "all", value: nil)
                ForEach(LogCategory.allCases, id: \.rawValue) { cat in
                    filterChip(label: cat.label, value: cat)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    clearAll()
                } label: {
                    Text("clear").kicker(L.Palette.badRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, L.Space.pageH)
            .padding(.vertical, 8)
        }
        .background(L.Palette.bg)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private func filterChip(label: String, value: LogCategory?) -> some View {
        let isOn = filter == value
        return Button {
            filter = value
        } label: {
            Text(label).kicker(isOn ? L.Palette.fg : L.Palette.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Rectangle().stroke(isOn ? L.Palette.fg : L.Palette.hair2, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func row(_ entry: AlarmLogEntry) -> some View {
        let color = entry.isError ? L.Palette.badRed : color(for: entry.category)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(timeString(entry.timestamp))
                    .font(L.Mono.font(11))
                    .foregroundStyle(L.Palette.muted)
                Text(entry.category.label)
                    .kicker(color)
                if let alarmId = entry.alarmIdString {
                    Text(String(alarmId.prefix(8)))
                        .font(L.Mono.font(10))
                        .foregroundStyle(L.Palette.dim)
                }
                Spacer()
            }
            Text(entry.message)
                .font(L.Mono.font(12))
                .foregroundStyle(L.Palette.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(L.Palette.bg)
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 2)
        }
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("no entries").kicker(L.Palette.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(L.Palette.bg)
    }

    // MARK: - Actions

    private func copyAll() {
        let formatter = ISO8601DateFormatter()
        let lines = filtered.map { e -> String in
            let id = e.alarmIdString.map { " alarm=\($0.prefix(8))" } ?? ""
            let err = e.isError ? " ERROR" : ""
            return "\(formatter.string(from: e.timestamp)) [\(e.category.label)]\(err)\(id) \(e.message)"
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        showCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showCopied = false
        }
    }

    private func clearAll() {
        for entry in entries {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    private func color(for cat: LogCategory) -> Color {
        switch cat {
        case .alarmkit:     return L.Palette.warnYellow
        case .intent:       return L.Palette.goodGreen
        case .conversation: return L.Palette.fg
        case .app:          return L.Palette.muted
        case .error:        return L.Palette.badRed
        }
    }
}
