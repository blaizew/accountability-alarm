import Foundation
import OSLog
import SwiftData

/// Unified logging. Writes every event to both:
///   1. `os.Logger` (subsystem-categorized) — visible in Console.app and Xcode
///      console even from background intent processes.
///   2. A SwiftData `AlarmLogEntry` model — visible in-app via `LogView`, so
///      the user can scroll through what happened after an incident without a
///      Mac.
///
/// Safe to call from any context (foreground app, background intent, etc.).
/// Container is lazily resolved and the SwiftData write is best-effort —
/// failures never surface to callers because losing a log entry shouldn't
/// break the actual alarm flow.
final class LogService: @unchecked Sendable {
    static let shared = LogService()

    private let logger = Logger(subsystem: "com.accountabilityalarm.app", category: "alarmkit")

    private init() {}

    func log(
        _ category: LogCategory,
        _ message: String,
        alarmId: String? = nil,
        alarmKitId: String? = nil,
        isError: Bool = false
    ) async {
        // 1. os.Logger — always works, no setup required.
        let prefix = "[\(category.label)]"
        if isError {
            logger.error("\(prefix) \(message, privacy: .public)")
        } else {
            logger.log("\(prefix) \(message, privacy: .public)")
        }

        // 2. SwiftData — best effort. Resolve container, write entry, prune.
        await persist(
            category: category,
            message: message,
            alarmId: alarmId,
            alarmKitId: alarmKitId,
            isError: isError
        )
    }

    private func persist(
        category: LogCategory,
        message: String,
        alarmId: String?,
        alarmKitId: String?,
        isError: Bool
    ) async {
        let resolved = resolveContainer()
        guard let resolved else { return }

        let context = ModelContext(resolved)
        let entry = AlarmLogEntry(
            category: category,
            message: message,
            alarmIdString: alarmId,
            alarmKitIdString: alarmKitId,
            isError: isError
        )
        context.insert(entry)

        // Cap at last 1000 entries — prevents unbounded growth if logging
        // ever runs hot. Cheap because SwiftData indexes by timestamp.
        if let count = try? context.fetchCount(FetchDescriptor<AlarmLogEntry>()),
           count > 1000 {
            let overflow = count - 1000
            var descriptor = FetchDescriptor<AlarmLogEntry>(
                sortBy: [SortDescriptor(\AlarmLogEntry.timestamp, order: .forward)]
            )
            descriptor.fetchLimit = overflow
            if let oldest = try? context.fetch(descriptor) {
                for e in oldest { context.delete(e) }
            }
        }

        try? context.save()
    }

    private func resolveContainer() -> ModelContainer? {
        // One container per process — intents run in the app process, so this
        // is the same stack the UI uses. See AppContainer for why a second
        // container over the same store is a bug, not a convenience.
        AppContainer.shared
    }
}
