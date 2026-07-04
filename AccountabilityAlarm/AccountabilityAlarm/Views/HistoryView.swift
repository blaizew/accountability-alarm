import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \AlarmEvent.firedAt, order: .reverse) private var events: [AlarmEvent]

    var body: some View {
        VStack(spacing: 0) {
            LTopBar(left: "HISTORY · LAST 30D", right: "")

            ScrollView {
                LTitle(kicker: kicker, title: "History")
                statTrio
                patternGrid
                ledger
                Color.clear.frame(height: 24)
            }
            .background(L.Palette.bg)
        }
        .background(L.Palette.bg.ignoresSafeArea())
        .foregroundStyle(L.Palette.fg)
    }

    // MARK: - Derived

    private var resolved: [AlarmEvent] {
        events.filter { $0.outcome != "pending" }
    }

    private var compliedEvents: [AlarmEvent] {
        events.filter { $0.outcome == "complied" || $0.outcome == "snoozed_then_complied" }
    }

    private var compliedPct: Int {
        guard !resolved.isEmpty else { return 0 }
        return Int(round(Double(compliedEvents.count) / Double(resolved.count) * 100))
    }

    private var totalSnoozes: Int {
        events.reduce(0) { $0 + $1.snoozeCount }
    }

    private var avgSnoozes: String {
        guard !events.isEmpty else { return "0.0" }
        let avg = Double(totalSnoozes) / Double(events.count)
        return String(format: "%.1f", avg)
    }

    private var compliedWithDuration: [AlarmEvent] {
        compliedEvents.filter { $0.complianceTimeMinutes > 0 }
    }

    private var avgComplyMinutes: Int {
        guard !compliedWithDuration.isEmpty else { return 0 }
        let sum = compliedWithDuration.reduce(0) { $0 + $1.complianceTimeMinutes }
        return sum / compliedWithDuration.count
    }

    private var alarmCount: Int {
        Set(events.compactMap(\.alarm?.id)).count
    }

    private var kicker: String {
        "// across \(alarmCount) alarm\(alarmCount == 1 ? "" : "s")"
    }

    // MARK: - Sections

    private var statTrio: some View {
        HStack(spacing: 0) {
            statCell(
                title: "complied",
                bigNumber: "\(compliedPct)",
                suffix: "%",
                bigColor: L.Palette.goodGreen,
                subtitle: "complied \(compliedEvents.count)/\(resolved.count)"
            )
            divider
            statCell(
                title: "avg snoozes",
                bigNumber: avgSnoozes,
                suffix: nil,
                bigColor: L.Palette.fg,
                subtitle: "\(totalSnoozes) total"
            )
            divider
            statCell(
                title: "avg comply-t",
                bigNumber: "\(avgComplyMinutes)",
                suffix: "m",
                bigColor: L.Palette.fg,
                subtitle: "\(compliedWithDuration.count) samples"
            )
        }
        .overlay(alignment: .top)    { L.Palette.hair.frame(height: 1) }
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private var divider: some View {
        L.Palette.hair.frame(width: 1)
    }

    private func statCell(title: String, bigNumber: String, suffix: String?, bigColor: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(L.Mono.font(9.5))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(L.Palette.dim)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(bigNumber)
                    .font(L.Mono.font(24, weight: .medium))
                    .foregroundStyle(bigColor)
                    .monospacedDigit()
                if let suffix {
                    Text(suffix)
                        .font(L.Mono.font(suffix.count > 1 ? 12 : 14))
                        .foregroundStyle(L.Palette.muted)
                }
            }
            Text(subtitle)
                .font(L.Mono.font(9.5))
                .foregroundStyle(L.Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    // MARK: - 28-day pattern grid

    private var patternGrid: some View {
        let cells = patternCells()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("28-day pattern · row = week")
                    .font(L.Mono.font(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(L.Palette.dim)
                Spacer()
                Text("↓ today")
                    .font(L.Mono.font(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(L.Palette.dim)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(Array(cells.enumerated()), id: \.offset) { idx, kind in
                    cell(kind, isToday: idx == cells.count - 1)
                }
            }
            HStack(spacing: 12) {
                legend(L.Palette.goodGreen, "kept")
                legend(L.Palette.warnYellow, "snoozed")
                legend(L.Palette.ringMirror, "mirror")
                legend(L.Palette.ringPreview, "preview")
                legend(L.Palette.dim, "missed")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    enum CellKind { case complied, snoozed, ignored, mirror, preview, empty }

    private func cell(_ kind: CellKind, isToday: Bool) -> some View {
        let c: Color = {
            switch kind {
            case .complied: return L.Palette.goodGreen
            case .snoozed:  return L.Palette.warnYellow
            case .ignored:  return L.Palette.dim
            case .mirror:   return L.Palette.ringMirror
            case .preview:  return L.Palette.ringPreview
            case .empty:    return L.Palette.bg3
            }
        }()
        return Rectangle()
            .fill(c)
            .opacity(kind == .ignored ? 0.28 : (kind == .empty ? 0.6 : 1))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isToday { Rectangle().stroke(L.Palette.fg, lineWidth: 1) }
            }
    }

    private func patternCells() -> [CellKind] {
        // 28 cells, oldest first, most-recent last (today bottom-right).
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var cells: [CellKind] = []
        for offset in (0..<28).reversed() {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else {
                cells.append(.empty); continue
            }
            let dayEvents = events.filter { cal.isDate($0.firedAt, inSameDayAs: day) }
            cells.append(cellKind(for: dayEvents))
        }
        return cells
    }

    private func cellKind(for dayEvents: [AlarmEvent]) -> CellKind {
        guard let first = dayEvents.sorted(by: { $0.firedAt < $1.firedAt }).first else {
            return .empty
        }
        if first.outcome == "complied" { return .complied }
        if first.outcome == "snoozed_then_complied" { return .snoozed }
        if first.outcome == "overridden" {
            if first.endedOnRing == .preview { return .preview }
            if first.endedOnRing == .mirror { return .mirror }
            return .preview
        }
        return .ignored
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(L.Mono.font(9.5))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(L.Palette.dim)
        }
    }

    // MARK: - Recent ledger

    private var ledger: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent")
                    .font(L.Mono.font(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(L.Palette.dim)
                Spacer()
                Text("outcome / ring")
                    .font(L.Mono.font(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(L.Palette.dim)
            }
            .padding(.horizontal, L.Space.pageH)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }

            ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                ledgerRow(index: idx + 1, event: event)
            }

            if events.isEmpty {
                Text("// no events yet")
                    .kicker()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }
        }
    }

    private func ledgerRow(index: Int, event: AlarmEvent) -> some View {
        let c: Color = {
            switch event.outcome {
            case "complied":               return L.Palette.goodGreen
            case "snoozed_then_complied":  return L.Palette.warnYellow
            case "overridden":             return L.Palette.badRed
            default:                       return L.Palette.dim
            }
        }()
        return HStack(spacing: 10) {
            Text(String(format: "%02d", index))
                .font(L.Mono.font(10))
                .foregroundStyle(L.Palette.dimmer)
                .frame(width: 22, alignment: .leading)
            Text(event.dateLabel)
                .font(L.Mono.font(11))
                .foregroundStyle(L.Palette.muted)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)
            HStack(spacing: 6) {
                Text(event.timeLabel)
                    .font(L.Mono.font(12))
                    .foregroundStyle(L.Palette.fg)
                Text("· \(event.alarm?.label ?? "alarm")")
                    .font(L.Mono.font(12))
                    .foregroundStyle(L.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if event.outcome == "overridden", let reason = event.overrideReason, !reason.isEmpty {
                    Text("· \"\(reason)\"")
                        .font(L.Mono.font(11))
                        .foregroundStyle(L.Palette.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let ring = event.endedOnRing {
                Rectangle()
                    .fill(L.ringColor(ring))
                    .frame(width: 8, height: 8)
            }
            Text(humanOutcome(event.outcome) + (event.snoozeCount > 0 ? " ·\(event.snoozeCount)" : ""))
                .font(L.Mono.font(10))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(c)
                .lineLimit(1)
        }
        .padding(.horizontal, L.Space.pageH)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
    }

    private func humanOutcome(_ raw: String) -> String {
        // "ignored" is stored for never-engaged/abandoned firings; the
        // user-facing word (and the pattern-grid legend) is "missed".
        if raw == "ignored" { return "missed" }
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}
