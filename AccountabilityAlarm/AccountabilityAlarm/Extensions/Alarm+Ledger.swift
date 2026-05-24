import Foundation

// LEDGER-shaped accessors layered on top of the existing Alarm model.

extension Alarm {

    // MARK: - Time presentation

    /// 12-hour time without period — "10:00", "02:30", "06:15"
    var time12: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%02d:%02d", h12, minute)
    }

    /// "AM" or "PM"
    var period: String { hour < 12 ? "AM" : "PM" }

    // MARK: - Days

    /// Existing `repeatDays` is 1=Sun ... 7=Sat. LEDGER uses 0=Sun ... 6=Sat.
    var daysSetZeroIndexed: Set<Int> {
        Set(repeatDays.map { $0 - 1 })
    }

    /// Human label following the LEDGER style.
    /// "Every day", "Weekdays", "Weekends", "Mon – Fri", "Mon, Wed, Fri", "Once"
    var daysLabel: String {
        if repeatDays.isEmpty { return "Once" }
        let set = Set(repeatDays)
        if set == Set(1...7) { return "Every day" }
        if set == [2, 3, 4, 5, 6] { return "Mon – Fri" }
        if set == [1, 7] { return "Weekends" }

        let short = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        // Detect contiguous run (e.g. Tue – Thu).
        let sorted = repeatDays.sorted()
        if sorted.count >= 3 {
            var contiguous = true
            for i in 1..<sorted.count where sorted[i] != sorted[i - 1] + 1 {
                contiguous = false; break
            }
            if contiguous, let first = sorted.first, let last = sorted.last {
                return "\(short[first]) – \(short[last])"
            }
        }
        return sorted.map { short[$0] }.joined(separator: ", ")
    }

    // MARK: - Reason

    /// First sentence (or first 60 chars) of the reason. Used as the row's snippet.
    var reasonShort: String {
        let trimmed = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "—" }
        // Split on sentence terminators.
        let firstSentence = trimmed.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? trimmed
        let cleaned = firstSentence.trimmingCharacters(in: .whitespaces)
        if cleaned.count <= 80 { return cleaned }
        return String(cleaned.prefix(78)) + "…"
    }

    // MARK: - Snooze state

    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return until > Date()
    }

    /// "snoozed · 2m left · ↻ 7:42 PM"
    var snoozeRemainingLabel: String {
        guard let until = snoozedUntil else { return "" }
        let secondsLeft = max(0, Int(until.timeIntervalSinceNow))
        let minutesLeft = (secondsLeft + 59) / 60
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let resumeAt = f.string(from: until)
        if minutesLeft <= 1 {
            return "snoozed · <1m · ↻ \(resumeAt)"
        }
        return "snoozed · \(minutesLeft)m left · ↻ \(resumeAt)"
    }

    // MARK: - History rollups

    /// Sorted events (newest first).
    private var eventsSortedDesc: [AlarmEvent] {
        events.sorted { $0.firedAt > $1.firedAt }
    }

    /// Last resolved outcome — `"complied"`, `"snoozed"`, `"overridden"`, `"ignored"`, or `nil`.
    var lastOutcome: String? {
        for e in eventsSortedDesc where e.outcome != "pending" {
            // Collapse the "snoozed_then_complied" variant to "snoozed" for the list chip.
            if e.outcome == "snoozed_then_complied" { return "complied" }
            return e.outcome
        }
        return nil
    }

    /// Consecutive non-overridden, non-ignored firings, walking newest → oldest.
    var streak: Int {
        var count = 0
        for e in eventsSortedDesc {
            if e.outcome == "complied" || e.outcome == "snoozed_then_complied" {
                count += 1
            } else if e.outcome == "pending" {
                continue
            } else {
                break
            }
        }
        return count
    }
}

// MARK: - LEDGER accessors on AlarmEvent

extension AlarmEvent {

    /// The escalation ring this event ended on. Derived from `complianceTimeMinutes`
    /// when the conversation engine didn't tag it explicitly.
    var endedOnRing: EscalationRing? {
        if outcome == "ignored" || outcome == "pending" { return nil }
        let mins = complianceTimeMinutes
        switch mins {
        case ..<10:  return .nudge
        case ..<20:  return .math
        case ..<30:  return .mirror
        default:     return .preview
        }
    }

    /// Human date like "Tue · 21 May" used in the History ledger.
    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · d MMM"
        return f.string(from: firedAt)
    }

    /// Human time like "10:00 PM" used in the History ledger.
    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: firedAt)
    }
}
