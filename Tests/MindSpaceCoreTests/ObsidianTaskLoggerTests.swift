import Foundation
import Testing
@testable import MindSpaceCore

private func temporaryVault() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MindSpaceVaultTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("task events append readable Markdown to the predictable daily file")
func taskEventsAppendMarkdown() throws {
    let vault = try temporaryVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let timestamp = Date(timeIntervalSince1970: 1_797_774_138) // 2026-12-20 13:42:18 UTC
    let logger = ObsidianTaskLogger(
        vaultURL: vault,
        timeZone: try #require(TimeZone(identifier: "Europe/Brussels")),
        eventID: { "event_fixed" }
    )
    let task = MindSpaceTask(
        id: "task_fixed",
        title: "Plan assignment",
        status: .inbox,
        createdAt: timestamp,
        updatedAt: timestamp
    )

    let fileURL = try logger.append(
        TaskLogEvent(
            timestamp: timestamp,
            type: .created,
            task: task,
            projectName: "University"
        )
    )
    let markdown = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(fileURL.path.hasSuffix("Productivity Log/Tasks/2026-12-20.md"))
    #expect(markdown.contains("## 2026-12-20"))
    #expect(markdown.contains("14:42:18 Europe/Brussels | task_created"))
    #expect(markdown.contains("event_id: event_fixed"))
    #expect(markdown.contains("id: task_fixed"))
    #expect(markdown.contains("title: “Plan assignment”"))
    #expect(markdown.contains("project: “University”"))
    #expect(markdown.contains("status: inbox"))
}

@Test("existing task history is never overwritten")
func existingTaskHistoryIsNeverOverwritten() throws {
    let vault = try temporaryVault()
    defer { try? FileManager.default.removeItem(at: vault) }
    let timestamp = Date(timeIntervalSince1970: 1_797_774_138)
    let timeZone = try #require(TimeZone(identifier: "Europe/Brussels"))
    let task = MindSpaceTask(
        id: "task_fixed",
        title: "Plan assignment",
        status: .inbox,
        createdAt: timestamp,
        updatedAt: timestamp
    )

    let fileURL = try ObsidianTaskLogger(
        vaultURL: vault,
        timeZone: timeZone,
        eventID: { "event_created" }
    ).append(TaskLogEvent(timestamp: timestamp, type: .created, task: task))

    var completedTask = task
    completedTask.status = .completed
    try ObsidianTaskLogger(
        vaultURL: vault,
        timeZone: timeZone,
        eventID: { "event_completed" }
    ).append(TaskLogEvent(timestamp: timestamp, type: .completed, task: completedTask))

    let markdown = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(markdown.components(separatedBy: "## 2026-12-20").count == 2)
    #expect(markdown.contains("event_id: event_created"))
    #expect(markdown.contains("task_created"))
    #expect(markdown.contains("event_id: event_completed"))
    #expect(markdown.contains("task_completed"))
}
