import Foundation
import Testing
@testable import MindSpaceCore

private enum StubLoggingError: Error {
    case unavailable
}

private final class FailingTaskEventLogger: TaskEventLogging, @unchecked Sendable {
    func append(_ event: TaskLogEvent) throws -> URL {
        throw StubLoggingError.unavailable
    }
}

private final class RecordingTaskEventLogger: TaskEventLogging, @unchecked Sendable {
    private(set) var events: [TaskLogEvent] = []

    func append(_ event: TaskLogEvent) throws -> URL {
        events.append(event)
        return URL(fileURLWithPath: "/tmp/recorded.md")
    }
}

@Test("a vault failure never rolls back a task and queues the event for retry")
func vaultFailureQueuesRetryWithoutLosingTask() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(
        now: { instant },
        taskID: { "task_fixed" }
    )
    let service = TaskActionService(
        repository: repository,
        logger: FailingTaskEventLogger(),
        now: { instant },
        eventID: { "event_fixed" }
    )

    let result = try service.createTask(title: "Plan assignment")

    #expect(result.task.id == "task_fixed")
    #expect(result.loggingIssue != nil)
    #expect(try repository.task(id: "task_fixed") == result.task)
    let pending = try repository.pendingLogEvents()
    #expect(pending.count == 1)
    #expect(pending.first?.eventID == "event_fixed")
    #expect(pending.first?.type == .created)
    #expect(pending.first?.task.id == "task_fixed")
}

@Test("retrying pending events removes only successful writes")
func retryingPendingEventsRemovesSuccessfulWrites() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(
        now: { instant },
        taskID: { "task_fixed" }
    )
    let failingService = TaskActionService(
        repository: repository,
        logger: FailingTaskEventLogger(),
        now: { instant },
        eventID: { "event_fixed" }
    )
    _ = try failingService.createTask(title: "Plan assignment")
    let recordingLogger = RecordingTaskEventLogger()
    let retryingService = TaskActionService(repository: repository, logger: recordingLogger)

    let result = try retryingService.retryPendingLogEvents()

    #expect(result.succeededEventIDs == ["event_fixed"])
    #expect(result.failures.isEmpty)
    #expect(recordingLogger.events.map(\.eventID) == ["event_fixed"])
    #expect(try repository.pendingLogEvents().isEmpty)
}

@Test("editing a task logs the fields that changed")
func editingTaskLogsChangedFields() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    var task = try repository.createTask(title: "Draft", notes: "Old notes")
    task.title = "Final"
    task.notes = "New notes"
    let logger = RecordingTaskEventLogger()
    let service = TaskActionService(
        repository: repository,
        logger: logger,
        now: { instant },
        eventID: { "event_edit" }
    )

    let result = try service.updateTask(task)

    #expect(result.loggingIssue == nil)
    let event = try #require(logger.events.first)
    #expect(event.type == .edited)
    #expect(event.changedFields["title"] == "Draft → Final")
    #expect(event.changedFields["notes"] == "Old notes → New notes")
}

@Test("assigning a thought to a project logs the saved relationship")
func assigningThoughtLogsProjectChange() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let task = try repository.createTask(title: "University assignment")
    let project = try repository.createProject(name: "University", colorToken: "cobalt")
    let logger = RecordingTaskEventLogger()
    let service = TaskActionService(repository: repository, logger: logger, now: { instant })

    let result = try service.assignTask(id: task.id, to: project.id)

    #expect(result.task.projectID == project.id)
    #expect(result.task.status == .active)
    let event = try #require(logger.events.first)
    #expect(event.type == .edited)
    #expect(event.projectName == "University")
    #expect(event.changedFields["project"] != nil)
}

@Test("creating a galaxy logs membership changes for every original task")
func creatingGalaxyLogsEveryMembershipChange() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let first = try repository.createTask(title: "Learn 3D design")
    let second = try repository.createTask(title: "Build portfolio")
    let logger = RecordingTaskEventLogger()
    let service = TaskActionService(repository: repository, logger: logger, now: { instant })

    let result = try service.createProject(
        name: "Creative Future",
        colorToken: "purple",
        assigningTaskIDs: [first.id, second.id]
    )

    #expect(result.project.name == "Creative Future")
    #expect(result.tasks.map(\.projectID).allSatisfy { $0 == result.project.id })
    #expect(logger.events.count == 2)
    #expect(logger.events.allSatisfy { $0.type == .edited && $0.projectName == "Creative Future" })
}

@Test("completing a task writes a completion event")
func completingTaskWritesCompletionEvent() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let task = try repository.createTask(title: "Finish assignment")
    let logger = RecordingTaskEventLogger()
    let service = TaskActionService(repository: repository, logger: logger, now: { instant })

    let result = try service.completeTask(id: task.id)

    #expect(result.task.status == .completed)
    #expect(result.task.completedAt == instant)
    #expect(logger.events.map(\.type) == [.completed])
}

@Test("reopening a task writes a reopening event")
func reopeningTaskWritesReopeningEvent() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let task = try repository.createTask(title: "Finish assignment")
    _ = try repository.complete(taskID: task.id)
    let logger = RecordingTaskEventLogger()
    let service = TaskActionService(repository: repository, logger: logger, now: { instant })

    let result = try service.reopenTask(id: task.id)

    #expect(result.task.status == .inbox)
    #expect(result.task.completedAt == nil)
    #expect(logger.events.map(\.type) == [.reopened])
}

@Test("deleting a task uses recoverable Trash and writes a deletion event")
func deletingTaskUsesTrashAndWritesDeletionEvent() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let task = try repository.createTask(title: "Remove safely", isToday: true)
    let logger = RecordingTaskEventLogger()
    let service = TaskActionService(repository: repository, logger: logger, now: { instant })

    let result = try service.deleteTask(id: task.id)

    #expect(result.task.status == .trashed)
    #expect(result.task.trashedAt == instant)
    #expect(!result.task.isToday)
    #expect(logger.events.map(\.type) == [.deleted])
    #expect(try repository.task(id: task.id) != nil)
}

@Test("restoring a trashed task preserves its identity and writes a restoration event")
func restoringTaskPreservesIdentityAndWritesRestorationEvent() throws {
    let instant = Date(timeIntervalSince1970: 1_797_774_138)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let task = try repository.createTask(title: "Bring back", isToday: true)
    _ = try repository.trash(taskID: task.id)
    let logger = RecordingTaskEventLogger()
    let service = TaskActionService(repository: repository, logger: logger, now: { instant })

    let result = try service.restoreTask(id: task.id)

    #expect(result.task.id == task.id)
    #expect(result.task.status == .inbox)
    #expect(result.task.trashedAt == nil)
    #expect(logger.events.map(\.type) == [.restored])
}
