import SwiftUI

/// First-run modal explaining the Screen Time Downtime caveat. iOS doesn't
/// automatically add AlarmKit apps to Screen Time's "Always Allowed" list, so
/// alarms that collide with the user's Downtime start time will leave the
/// "Talk to Coach" button unresponsive (the app is blocked from
/// launching). The Slide-to-Stop snooze still works because it runs in a
/// background intent — but the conversation flow won't reach them.
///
/// Dismiss writes `Constants.downtimeNoticeAcknowledgedKey` to UserDefaults
/// so this never shows again. Reset by deleting/reinstalling the app.
struct DowntimeNoticeView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            L.Palette.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("// one-time setup").kicker()

                Text("Add this app to your Screen Time Always Allowed list")
                    .font(L.Mono.font(22, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(L.Palette.fg)
                    .fixedSize(horizontal: false, vertical: true)

                Text("If you use iOS Downtime (or Sleep Focus auto-enables it), this app gets restricted when Downtime starts — same as any other app. The alarm sound will still ring, but the \"Talk to Coach\" button can't open the app, so you can't engage with the conversation.")
                    .font(L.Mono.font(13))
                    .foregroundStyle(L.Palette.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                steps

                Spacer()

                Button(action: onDismiss) {
                    Text("got it")
                        .kicker(L.Palette.fg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(Rectangle().stroke(L.Palette.fg, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, L.Space.pageH)
            .padding(.top, 50)
            .padding(.bottom, 30)
        }
        .foregroundStyle(L.Palette.fg)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepRow(num: "01", text: "Open Settings → Screen Time → Always Allowed")
            stepRow(num: "02", text: "Tap the + next to AccountabilityAlarm")
        }
        .padding(.top, 6)
    }

    private func stepRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(L.Mono.font(11))
                .foregroundStyle(L.Palette.dim)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(L.Mono.font(13))
                .foregroundStyle(L.Palette.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Persistent banner shown above the alarm list until the user acknowledges
/// the Downtime caveat. Tapping it opens the same modal as first-run.
struct DowntimeNoticeBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                L.Dot(size: 5, color: L.Palette.warnYellow)
                Text("downtime caveat — tap for setup")
                    .kicker(L.Palette.warnYellow)
                Spacer()
                L.Chev(size: 8, color: L.Palette.warnYellow)
            }
            .padding(.horizontal, L.Space.pageH)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { L.Palette.hair.frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}
