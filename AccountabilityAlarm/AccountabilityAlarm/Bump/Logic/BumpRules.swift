import Foundation

enum BumpSendOff {
    /// The last message's text when it is a non-blank assistant message.
    static func pick(_ messages: [ConversationMessage]) -> String? {
        guard let last = messages.last, last.role == .assistant else { return nil }
        let trimmed = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : last.content
    }
}

enum BumpRules {
    static func shouldOverrideForTurnLimit(
        isCompleted: Bool,
        actionAuthorized: Bool,
        turnsThisSession: Int,
        maxTurns: Int
    ) -> Bool {
        !isCompleted && !actionAuthorized && turnsThisSession >= maxTurns * 2
    }
}
