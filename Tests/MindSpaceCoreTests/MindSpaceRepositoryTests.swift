import Foundation
import Testing
@testable import MindSpaceCore

private final class TestClock: @unchecked Sendable {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date { date }
}

@Test("creating a task gives it a stable ID and defaults it to Inbox")
func creatingTaskGivesStableIDAndInboxDefault() throws {
    let instant = Date(timeIntervalSince1970: 1_700_000_000)
    let repository = try MindSpaceRepository.inMemory(now: { instant })

    let task = try repository.createTask(title: "Write outline")
    let loaded = try repository.task(id: task.id)

    #expect(task.id.hasPrefix("task_"))
    #expect(UUID(uuidString: String(task.id.dropFirst("task_".count))) != nil)
    #expect(task.status == .inbox)
    #expect(loaded == task)
}

@Test("ID generation can be injected for deterministic integrations")
func identifiersCanBeInjected() throws {
    let repository = try MindSpaceRepository.inMemory(
        taskID: { "task_fixed" },
        projectID: { "project_fixed" }
    )

    let project = try repository.createProject(name: "Coursework", colorToken: "purple")
    let task = try repository.createTask(title: "Outline", projectID: project.id)

    #expect(project.id == "project_fixed")
    #expect(task.id == "task_fixed")
}

@Test("tasks cannot reference a missing project")
func missingProjectIsRejected() throws {
    let repository = try MindSpaceRepository.inMemory()

    #expect(throws: MindSpaceRepositoryError.projectNotFound("project_missing")) {
        try repository.createTask(title: "Orphan", projectID: "project_missing")
    }
}

@Test("a selected project makes a new task active")
func projectAssignmentMakesTaskActive() throws {
    let instant = Date(timeIntervalSince1970: 1_700_000_000)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let project = try repository.createProject(name: "University", colorToken: "cobalt")

    let task = try repository.createTask(title: "Plan assignment", projectID: project.id)

    #expect(task.status == .active)
    #expect(task.projectID == project.id)
    #expect(try repository.project(id: project.id) == project)
}

@Test("a disk repository survives closing and reopening")
func diskRepositorySurvivesReopening() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MindSpaceSQLiteTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("MindSpace.sqlite3")
    let instant = Date(timeIntervalSince1970: 1_700_000_000)
    var taskID = ""

    do {
        let repository = try MindSpaceRepository.disk(at: databaseURL, now: { instant })
        let task = try repository.createTask(
            title: "Persist me",
            estimatedFocusMinutes: 45,
            externalSessionReferences: ["focus_session_1"]
        )
        taskID = task.id
    }

    let reopened = try MindSpaceRepository.disk(at: databaseURL, now: { instant })
    let loaded = try reopened.task(id: taskID)
    let task = try #require(loaded)
    #expect(task.title == "Persist me")
    #expect(task.estimatedFocusMinutes == 45)
    #expect(task.externalSessionReferences == ["focus_session_1"])
}

@Test("editing a task persists every editable and future-ready field")
func editingTaskPersistsFields() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let repository = try MindSpaceRepository.inMemory(now: clock.now)
    var task = try repository.createTask(title: "Draft")
    let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
    clock.date = Date(timeIntervalSince1970: 1_700_000_100)

    task.title = "Edited"
    task.notes = "Useful context"
    task.dueDate = dueDate
    task.category = "creative"
    task.energy = "high"
    task.estimatedFocusMinutes = 30
    task.externalSessionReferences = ["focus_session_2"]
    let updated = try repository.updateTask(task)

    #expect(updated.title == "Edited")
    #expect(updated.notes == "Useful context")
    #expect(updated.dueDate == dueDate)
    #expect(updated.category == "creative")
    #expect(updated.energy == "high")
    #expect(updated.estimatedFocusMinutes == 30)
    #expect(updated.externalSessionReferences == ["focus_session_2"])
    #expect(updated.updatedAt == clock.date)
    #expect(try repository.task(id: task.id) == updated)
}

@Test("Today, completion, and reopening preserve a task without losing its prior status")
func todayCompletionAndReopening() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let repository = try MindSpaceRepository.inMemory(now: clock.now)
    let task = try repository.createTask(title: "Finish this")

    let today = try repository.setToday(taskID: task.id, isToday: true)
    #expect(today.isToday)
    #expect(try repository.todayTasks().map(\.id) == [task.id])

    clock.date = Date(timeIntervalSince1970: 1_700_000_100)
    let completed = try repository.complete(taskID: task.id)
    #expect(completed.status == .completed)
    #expect(completed.completedAt == clock.date)
    #expect(!completed.isToday)

    let reopened = try repository.reopen(taskID: task.id)
    #expect(reopened.status == .inbox)
    #expect(reopened.completedAt == nil)
    #expect(try repository.task(id: task.id) == reopened)
}

@Test("trash is recoverable and removes the task from Today")
func trashAndRestoreAreSafe() throws {
    let instant = Date(timeIntervalSince1970: 1_700_000_000)
    let repository = try MindSpaceRepository.inMemory(now: { instant })
    let project = try repository.createProject(name: "Personal", colorToken: "green")
    let task = try repository.createTask(title: "Keep recoverable", projectID: project.id, isToday: true)

    let trashed = try repository.trash(taskID: task.id)
    #expect(trashed.status == .trashed)
    #expect(trashed.trashedAt == instant)
    #expect(!trashed.isToday)
    #expect(try repository.tasks(status: .trashed).map(\.id) == [task.id])

    let restored = try repository.restore(taskID: task.id)
    #expect(restored.status == .active)
    #expect(restored.trashedAt == nil)
    #expect(restored.projectID == project.id)
}

@Test("projects can be updated, listed, archived, and restored")
func projectLifecycle() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
    let repository = try MindSpaceRepository.inMemory(now: clock.now)
    var project = try repository.createProject(name: "Coursework", colorToken: "purple")
    clock.date = Date(timeIntervalSince1970: 1_700_000_100)

    project.name = "University"
    project.colorToken = "cobalt"
    let updated = try repository.updateProject(project)
    #expect(updated.name == "University")
    #expect(updated.colorToken == "cobalt")
    #expect(updated.updatedAt == clock.date)
    #expect(try repository.projects() == [updated])

    let archived = try repository.setProjectArchived(projectID: project.id, isArchived: true)
    #expect(archived.isArchived)
    #expect(archived.archivedAt == clock.date)
    #expect(try repository.projects().isEmpty)
    #expect(try repository.projects(includeArchived: true) == [archived])

    let restored = try repository.setProjectArchived(projectID: project.id, isArchived: false)
    #expect(!restored.isArchived)
    #expect(restored.archivedAt == nil)
}

@Test("preferences persist reduced motion and the native vault access boundary")
func preferencesPersist() throws {
    let repository = try MindSpaceRepository.inMemory()
    let preferences = MindSpacePreferences(
        reducedMotion: true,
        vaultBookmark: Data([1, 2, 3]),
        vaultPath: "/Users/example/Obsidian"
    )

    try repository.savePreferences(preferences)

    #expect(try repository.preferences() == preferences)
}

@Test("blank names and non-positive focus estimates are rejected")
func invalidInputIsRejected() throws {
    let repository = try MindSpaceRepository.inMemory()

    #expect(throws: MindSpaceRepositoryError.invalidTaskTitle) {
        try repository.createTask(title: "   ")
    }
    #expect(throws: MindSpaceRepositoryError.invalidProjectName) {
        try repository.createProject(name: "\n", colorToken: "orange")
    }
    #expect(throws: MindSpaceRepositoryError.invalidEstimatedFocusMinutes) {
        try repository.createTask(title: "Invalid estimate", estimatedFocusMinutes: 0)
    }
}
