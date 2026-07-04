import SwiftUI
import SwiftData
import Combine

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)])
    private var alarms: [Alarm]

    @State private var viewModel = AlarmListViewModel()
    @State private var alarmToEdit: Alarm?
    @State private var showNew = false
    @State private var now: String = AlarmListView.currentClock()
    @State private var showDowntimeNotice = false
    @AppStorage(Constants.downtimeNoticeAcknowledgedKey) private var downtimeAcknowledged = false

    private let clockTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            LTopBar(
                left: "ALARMS · \(alarms.filter(\.enabled).count)/\(alarms.count) ON",
                right: now,
                rightColor: L.Palette.muted
            )

            if !downtimeAcknowledged {
                DowntimeNoticeBanner { showDowntimeNotice = true }
            }

            // Using List (not ScrollView) so .swipeActions work natively —
            // pull-left to reveal trash, full-swipe to delete.
            List {
                Section {
                    LTitle(
                        kicker: nextKicker,
                        title: "Alarms",
                        count: alarms.count
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(L.Palette.bg)
                    .listRowSeparator(.hidden)

                    ForEach(Array(alarms.enumerated()), id: \.element.id) { idx, alarm in
                        LAlarmRow(
                            alarm: alarm,
                            index: idx,
                            onFire: { fireAlarm(alarm) },
                            onEdit: { alarmToEdit = alarm },
                            onToggle: { viewModel.toggleAlarm(alarm) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(L.Palette.bg)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteAlarm(alarm, context: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    newCommitmentButton
                        .padding(.top, 6)
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
        .background(L.Palette.bg.ignoresSafeArea())
        .foregroundStyle(L.Palette.fg)
        .sheet(isPresented: $showNew) {
            AlarmEditView()
                .preferredColorScheme(.dark)
        }
        .sheet(item: $alarmToEdit) { alarm in
            AlarmEditView(alarm: alarm)
                .preferredColorScheme(.dark)
        }
        .onReceive(clockTimer) { _ in now = Self.currentClock() }
        .task {
            await viewModel.requestNotificationPermission()
            // First-run: show the Downtime caveat modal once. User can also
            // re-open it later via the persistent banner.
            if !downtimeAcknowledged {
                showDowntimeNotice = true
            }
        }
        .fullScreenCover(isPresented: $showDowntimeNotice) {
            DowntimeNoticeView(onDismiss: {
                downtimeAcknowledged = true
                showDowntimeNotice = false
            })
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Subviews

    private var newCommitmentButton: some View {
        VStack {
            Button {
                showNew = true
            } label: {
                HStack(spacing: 8) {
                    L.Plus(size: 10, color: L.Palette.muted)
                    Text("new commitment").kicker(L.Palette.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(
                    Rectangle()
                        .stroke(L.Palette.hair2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .overlay(alignment: .top) { L.Palette.hair.frame(height: 1) }
    }

    // MARK: - Derived

    private var nextKicker: String {
        guard let next = alarms.filter(\.enabled).min(by: minutesUntilFire) else {
            return "// no active alarms"
        }
        return "// next: \(next.label.lowercased()) · \(next.time12) \(next.period)"
    }

    private func minutesUntilFire(_ a: Alarm, _ b: Alarm) -> Bool {
        // Crude: minutes since midnight, both in 24h form.
        a.hour * 60 + a.minute < b.hour * 60 + b.minute
    }

    private func fireAlarm(_ alarm: Alarm) {
        // Dev affordance: opens the Conversation.
        appState.triggerAlarm(alarmId: alarm.id)
    }

    static func currentClock() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date()).uppercased()
    }
}

// MARK: - Row

struct LAlarmRow: View {
    let alarm: Alarm
    let index: Int
    let onFire: () -> Void
    let onEdit: () -> Void
    let onToggle: () -> Void

    private var stripeColor: Color { L.Palette.fg }

    private var outcomeColor: Color {
        switch alarm.lastOutcome {
        case "complied":   return L.Palette.goodGreen
        case "snoozed":    return L.Palette.warnYellow
        case "ignored":    return L.Palette.dim
        case "overridden": return L.Palette.badRed
        default:           return L.Palette.dim
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaLine
            timeAndLabel
            if alarm.isSnoozed {
                snoozeIndicator
            } else {
                reasonSnippet
            }
            tailLine
        }
        .padding(.vertical, L.Space.rowV)
        .padding(.horizontal, L.Space.pageH)
        .opacity(alarm.enabled ? 1.0 : 0.55)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(L.Palette.bg)
        .overlay(alignment: .leading) {
            if alarm.enabled {
                Rectangle()
                    .fill(alarm.isSnoozed ? L.Palette.warnYellow : stripeColor)
                    .frame(width: 2)
            }
        }
        .overlay(alignment: .top) { L.Palette.hair.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }

    private var snoozeIndicator: some View {
        HStack(spacing: 6) {
            L.Dot(size: 6, color: L.Palette.warnYellow)
            Text(alarm.snoozeRemainingLabel).kicker(L.Palette.warnYellow)
            Spacer()
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            L.Palette.warnYellow.opacity(0.6).frame(width: 1)
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("#\(String(format: "%03d", index + 1))")
                    .kicker(L.Palette.muted)
                Text(alarm.daysLabel).kicker()
            }
            .lineLimit(1)
            .layoutPriority(0)

            Spacer(minLength: 6)

            HStack(spacing: 10) {
                if alarm.enabled {
                    Button(action: onFire) {
                        L.PlayTri(size: 8, color: L.Palette.muted)
                            .frame(width: 24, height: 18)
                            .background(L.Palette.bg)
                            .overlay(Rectangle().stroke(L.Palette.hair2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                togglePill
            }
            .layoutPriority(1)
        }
    }

    private var togglePill: some View {
        Button(action: onToggle) {
            ZStack(alignment: alarm.enabled ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(alarm.enabled ? L.Palette.fg : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(alarm.enabled ? L.Palette.fg : L.Palette.hair2, lineWidth: 1)
                    )
                    .frame(width: 30, height: 16)
                Circle()
                    .fill(alarm.enabled ? L.Palette.bg : L.Palette.dim)
                    .frame(width: 12, height: 12)
                    .padding(.horizontal, 1)
            }
            .animation(.easeInOut(duration: 0.12), value: alarm.enabled)
        }
        .buttonStyle(.plain)
    }

    private var timeAndLabel: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(alarm.time12)
                    .font(L.Mono.font(32, weight: .regular))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(L.Palette.fg)
                Text(alarm.period)
                    .font(L.Mono.font(14))
                    .foregroundStyle(L.Palette.muted)
            }
            Text(alarm.label.isEmpty ? "—" : alarm.label)
                .font(L.Mono.font(13))
                .foregroundStyle(L.Palette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var reasonSnippet: some View {
        Text("\u{201C}\(alarm.reasonShort)\u{201D}")
            .font(L.Mono.font(12))
            .foregroundStyle(L.Palette.muted)
            .lineSpacing(2)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                L.Palette.hair2.frame(width: 1)
            }
            .lineLimit(2)
    }

    private var tailLine: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Text("last").kicker()
                HStack(spacing: 4) {
                    L.Dot(size: 5, color: outcomeColor)
                    Text(alarm.lastOutcome ?? "—").kicker(outcomeColor)
                }
            }
            Text("streak \(alarm.streak)").kicker()
            Spacer()
            HStack(spacing: 3) {
                Text("edit").kicker(L.Palette.dimmer)
                L.Chev(size: 8, color: L.Palette.dimmer)
            }
        }
    }
}
