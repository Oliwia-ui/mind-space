import Foundation

public enum TaskLogEventType: String, Codable, Sendable {
    case created = "task_created"
    case edited = "task_edited"
    case completed = "task_completed"
    case reopened = "task_reopened"
    case deleted = "task_deleted"
    case restored = "task_restored"
}

public struct TaskLogEvent: Codable, Equatable, Sendable {
    public let eventID: String
    public let timestamp: Date
    public let type: TaskLogEventType
    public let task: MindSpaceTask
    public let projectName: String?
    public let changedFields: [String: String]

    public init(
        eventID: String = "event_\(UUID().uuidString)",
        timestamp: Date,
        type: TaskLogEventType,
        task: MindSpaceTask,
        projectName: String? = nil,
        changedFields: [String: String] = [:]
    ) {
        self.eventID = eventID
        self.timestamp = timestamp
        self.type = type
        self.task = task
        self.projectName = projectName
        self.changedFields = changedFields
    }
}

public protocol TaskEventLogging: Sendable {
    @discardableResult
    func append(_ event: TaskLogEvent) throws -> URL
}

public final class ObsidianTaskLogger: TaskEventLogging, @unchecked Sendable {
    private let vaultURL: URL
    private let timeZone: TimeZone
    private let eventIDOverride: (@Sendable () -> String)?
    private let lock = NSLock()

    public init(
        vaultURL: URL,
        timeZone: TimeZone = .current,
        eventID: (@Sendable () -> String)? = nil
    ) {
        self.vaultURL = vaultURL
        self.timeZone = timeZone
        self.eventIDOverride = eventID
    }

    @discardableResult
    public func append(_ event: TaskLogEvent) throws -> URL {
        try lock.withLock {
            let date = formatted(event.timestamp, format: "yyyy-MM-dd")
            let directory = vaultURL
                .appendingPathComponent("Productivity Log", isDirectory: true)
                .appendingPathComponent("Tasks", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("\(date).md")
            let isNewFile = !FileManager.default.fileExists(atPath: fileURL.path)
            if isNewFile {
                guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()

            var markdown = ""
            if isNewFile {
                markdown += "## \(date)\n\n"
            }
            markdown += render(event)
            try handle.write(contentsOf: Data(markdown.utf8))
            try handle.synchronize()
            return fileURL
        }
    }

    private func render(_ event: TaskLogEvent) -> String {
        let time = formatted(event.timestamp, format: "HH:mm:ss")
        var lines = [
            "- \(time) \(timeZone.identifier) | \(event.type.rawValue)",
            "  - event_id: \(sanitized(eventIDOverride?() ?? event.eventID))",
            "  - id: \(sanitized(event.task.id))",
            "  - title: “\(sanitized(event.task.title))”",
        ]
        if let projectName = event.projectName {
            lines.append("  - project: “\(sanitized(projectName))”")
        }
        lines.append("  - status: \(event.task.status.rawValue)")
        for field in event.changedFields.keys.sorted() {
            if let value = event.changedFields[field] {
                lines.append("  - changed_\(sanitized(field)): \(sanitized(value))")
            }
        }
        return lines.joined(separator: "\n") + "\n\n"
    }

    private func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
