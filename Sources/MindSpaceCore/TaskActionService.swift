import Foundation

public struct TaskActionResult: Sendable {
    public let task: MindSpaceTask
    public let loggingIssue: String?

    public init(task: MindSpaceTask, loggingIssue: String?) {
        self.task = task
        self.loggingIssue = loggingIssue
    }
}

public struct TaskLogRetryFailure: Equatable, Sendable {
    public let eventID: String
    public let message: String

    public init(eventID: String, message: String) {
        self.eventID = eventID
        self.message = message
    }
}

public struct TaskLogRetryResult: Equatable, Sendable {
    public let succeededEventIDs: [String]
    public let failures: [TaskLogRetryFailure]

    public init(succeededEventIDs: [String], failures: [TaskLogRetryFailure]) {
        self.succeededEventIDs = succeededEventIDs
        self.failures = failures
    }
}

public final class TaskActionService: @unchecked Sendable {
    private let repository: MindSpaceRepository
    private let logger: any TaskEventLogging
    private let now: @Sendable () -> Date
    private let eventID: @Sendable () -> String

    public init(
        repository: MindSpaceRepository,
        logger: any TaskEventLogging,
        now: @escaping @Sendable () -> Date = Date.init,
        eventID: @escaping @Sendable () -> String = { "event_\(UUID().uuidString)" }
    ) {
        self.repository = repository
        self.logger = logger
        self.now = now
        self.eventID = eventID
    }

    public func createTask(
        title: String,
        notes: String? = nil,
        projectID: String? = nil,
        dueDate: Date? = nil,
        category: String? = nil,
        energy: String? = nil,
        isToday: Bool = false,
        estimatedFocusMinutes: Int? = nil,
        externalSessionReferences: [String] = []
    ) throws -> TaskActionResult {
        let task = try repository.createTask(
            title: title,
            notes: notes,
            projectID: projectID,
            dueDate: dueDate,
            category: category,
            energy: energy,
            isToday: isToday,
            estimatedFocusMinutes: estimatedFocusMinutes,
            externalSessionReferences: externalSessionReferences
        )
        let projectName = try projectID.flatMap { try repository.project(id: $0)?.name }
        let event = TaskLogEvent(
            eventID: eventID(),
            timestamp: now(),
            type: .created,
            task: task,
            projectName: projectName
        )
        return try log(event)
    }

    public func retryPendingLogEvents() throws -> TaskLogRetryResult {
        let pendingEvents = try repository.pendingLogEvents()
        var succeededEventIDs: [String] = []
        var failures: [TaskLogRetryFailure] = []

        for event in pendingEvents {
            do {
                try logger.append(event)
                try repository.removePendingLogEvent(eventID: event.eventID)
                succeededEventIDs.append(event.eventID)
            } catch {
                failures.append(TaskLogRetryFailure(eventID: event.eventID, message: String(describing: error)))
            }
        }

        return TaskLogRetryResult(succeededEventIDs: succeededEventIDs, failures: failures)
    }

    public func updateTask(_ task: MindSpaceTask) throws -> TaskActionResult {
        guard let previous = try repository.task(id: task.id) else {
            throw MindSpaceRepositoryError.taskNotFound(task.id)
        }
        let updated = try repository.updateTask(task)
        let projectName = try updated.projectID.flatMap { try repository.project(id: $0)?.name }
        let event = TaskLogEvent(
            eventID: eventID(),
            timestamp: now(),
            type: .edited,
            task: updated,
            projectName: projectName,
            changedFields: changedFields(from: previous, to: updated)
        )
        return try log(event)
    }

    public func completeTask(id: String) throws -> TaskActionResult {
        let completed = try repository.complete(taskID: id)
        let projectName = try completed.projectID.flatMap { try repository.project(id: $0)?.name }
        let event = TaskLogEvent(
            eventID: eventID(),
            timestamp: now(),
            type: .completed,
            task: completed,
            projectName: projectName
        )
        return try log(event)
    }

    public func reopenTask(id: String) throws -> TaskActionResult {
        let reopened = try repository.reopen(taskID: id)
        let projectName = try reopened.projectID.flatMap { try repository.project(id: $0)?.name }
        let event = TaskLogEvent(
            eventID: eventID(),
            timestamp: now(),
            type: .reopened,
            task: reopened,
            projectName: projectName
        )
        return try log(event)
    }

    public func deleteTask(id: String) throws -> TaskActionResult {
        let trashed = try repository.trash(taskID: id)
        let projectName = try trashed.projectID.flatMap { try repository.project(id: $0)?.name }
        let event = TaskLogEvent(
            eventID: eventID(),
            timestamp: now(),
            type: .deleted,
            task: trashed,
            projectName: projectName
        )
        return try log(event)
    }

    private func log(_ event: TaskLogEvent) throws -> TaskActionResult {
        do {
            try logger.append(event)
            return TaskActionResult(task: event.task, loggingIssue: nil)
        } catch {
            try repository.enqueueLogEvent(event)
            return TaskActionResult(task: event.task, loggingIssue: String(describing: error))
        }
    }

    private func changedFields(from previous: MindSpaceTask, to updated: MindSpaceTask) -> [String: String] {
        var fields: [String: String] = [:]
        if previous.title != updated.title { fields["title"] = "\(previous.title) → \(updated.title)" }
        if previous.notes != updated.notes { fields["notes"] = "\(previous.notes ?? "") → \(updated.notes ?? "")" }
        if previous.projectID != updated.projectID { fields["project"] = "\(previous.projectID ?? "Inbox") → \(updated.projectID ?? "Inbox")" }
        if previous.category != updated.category { fields["category"] = "\(previous.category ?? "") → \(updated.category ?? "")" }
        if previous.energy != updated.energy { fields["energy"] = "\(previous.energy ?? "") → \(updated.energy ?? "")" }
        if previous.dueDate != updated.dueDate { fields["due_date"] = "\(String(describing: previous.dueDate)) → \(String(describing: updated.dueDate))" }
        if previous.isToday != updated.isToday { fields["today"] = "\(previous.isToday) → \(updated.isToday)" }
        if previous.estimatedFocusMinutes != updated.estimatedFocusMinutes { fields["estimated_focus_minutes"] = "\(String(describing: previous.estimatedFocusMinutes)) → \(String(describing: updated.estimatedFocusMinutes))" }
        return fields
    }
}
