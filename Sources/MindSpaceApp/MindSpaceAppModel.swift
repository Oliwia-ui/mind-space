import AppKit
import Foundation
import MindSpaceCore

@MainActor
final class MindSpaceAppModel: ObservableObject {
    enum Mode: Equatable {
        case mindSpace
        case structured
    }

    enum Section: String, CaseIterable, Identifiable {
        case today = "Today"
        case inbox = "Inbox"
        case projects = "Projects"
        case done = "Done"
        case trash = "Trash"
        case logbook = "Logbook"
        case settings = "Settings"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .inbox: "tray"
            case .projects: "square.stack.3d.up"
            case .done: "checkmark.circle"
            case .trash: "trash"
            case .logbook: "book.closed"
            case .settings: "gearshape"
            }
        }
    }

    @Published var mode: Mode = .mindSpace
    @Published var selectedSection: Section = .today
    @Published private(set) var tasks: [MindSpaceTask] = []
    @Published private(set) var projects: [MindSpaceProject] = []
    @Published private(set) var preferences = MindSpacePreferences()
    @Published private(set) var pendingLogCount = 0
    @Published var selectedTask: MindSpaceTask?
    @Published var selectedProjectID: String?
    @Published var editingProject: MindSpaceProject?
    @Published var isPresentingNewTask = false
    @Published var isCreatingProject = false
    @Published var isNamingGalaxy = false
    @Published private(set) var pendingGalaxyTaskIDs: [String] = []
    @Published var isTransforming = false
    @Published var errorMessage: String?
    @Published var vaultMessage: String?

    private let repository: MindSpaceRepository
    let physics: MindSpacePhysicsController
    private var logger: any TaskEventLogging = UnavailableTaskEventLogger()
    private var scopedVaultURL: URL?

    init() {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent(MindSpaceConfiguration.productName, isDirectory: true)
            let repository = try MindSpaceRepository.disk(
                at: appSupport.appendingPathComponent(MindSpaceConfiguration.databaseFilename)
            )
            self.repository = repository
            physics = try MindSpacePhysicsController(repository: repository)
            try loadPreferencesAndVault()
            try refresh()
        } catch {
            fatalError("Mind Space could not open its local database: \(error)")
        }
    }

    deinit {
        scopedVaultURL?.stopAccessingSecurityScopedResource()
    }

    var visibleTasks: [MindSpaceTask] {
        switch selectedSection {
        case .today:
            tasks.filter { $0.isToday && $0.status != .completed && $0.status != .trashed }
        case .inbox:
            tasks.filter { $0.status == .inbox }
        case .projects:
            tasks.filter { $0.status == .active }
        case .done:
            tasks.filter { $0.status == .completed }
        case .trash:
            tasks.filter { $0.status == .trashed }
        case .logbook, .settings:
            []
        }
    }

    func project(for task: MindSpaceTask) -> MindSpaceProject? {
        guard let projectID = task.projectID else { return nil }
        return projects.first { $0.id == projectID }
    }

    func makeSense() {
        mode = .structured
    }

    func returnToMindSpace() {
        mode = .mindSpace
    }

    func createTask(
        title: String,
        notes: String?,
        projectID: String?,
        dueDate: Date?,
        category: String?,
        energy: String?,
        isToday: Bool
    ) {
        perform {
            let result = try service().createTask(
                title: title,
                notes: notes,
                projectID: projectID,
                dueDate: dueDate,
                category: category,
                energy: energy,
                isToday: isToday
            )
            showLoggingIssue(result.loggingIssue)
        }
    }

    func updateTask(_ task: MindSpaceTask) {
        perform {
            let result = try service().updateTask(task)
            selectedTask = result.task
            showLoggingIssue(result.loggingIssue)
        }
    }

    func complete(_ task: MindSpaceTask) {
        perform {
            let result = try service().completeTask(id: task.id)
            showLoggingIssue(result.loggingIssue)
        }
    }

    func reopen(_ task: MindSpaceTask) {
        perform {
            let result = try service().reopenTask(id: task.id)
            showLoggingIssue(result.loggingIssue)
        }
    }

    func delete(_ task: MindSpaceTask) {
        perform {
            let result = try service().deleteTask(id: task.id)
            selectedTask = nil
            showLoggingIssue(result.loggingIssue)
        }
    }

    func restore(_ task: MindSpaceTask) {
        perform {
            let result = try service().restoreTask(id: task.id)
            selectedTask = nil
            showLoggingIssue(result.loggingIssue)
        }
    }

    func toggleToday(_ task: MindSpaceTask) {
        var edited = task
        edited.isToday.toggle()
        updateTask(edited)
    }

    func createProject(name: String, colorToken: String) {
        perform {
            _ = try repository.createProject(name: name, colorToken: colorToken)
        }
    }

    @discardableResult
    func updateProject(_ project: MindSpaceProject, name: String, colorToken: String, memberTaskIDs: Set<String>) -> Bool {
        perform {
            var edited = project
            edited.name = name
            edited.colorToken = colorToken
            let result = try service().updateProject(edited, memberTaskIDs: Array(memberTaskIDs))
            showLoggingIssues(result.loggingIssues)
            editingProject = nil
        }
    }

    @discardableResult
    func dissolveProject(_ project: MindSpaceProject) -> Bool {
        perform {
            let result = try service().dissolveProject(id: project.id)
            showLoggingIssues(result.loggingIssues)
            if selectedProjectID == project.id { selectedProjectID = nil }
            editingProject = nil
        }
    }

    func handleGroup(_ pair: ThoughtGroupPair) {
        let firstTask = tasks.first { $0.id == pair.firstID }
        let secondTask = tasks.first { $0.id == pair.secondID }
        let firstProject = projects.first { $0.id == pair.firstID }
        let secondProject = projects.first { $0.id == pair.secondID }

        if let task = firstTask, let project = secondProject {
            assign(taskID: task.id, to: project.id)
            return
        }
        if let project = firstProject, let task = secondTask {
            assign(taskID: task.id, to: project.id)
            return
        }
        guard let firstTask, let secondTask else { return }

        if let firstProjectID = firstTask.projectID,
           let secondProjectID = secondTask.projectID,
           firstProjectID != secondProjectID {
            errorMessage = "Move a thought out of its current galaxy before connecting it to another one."
        } else if let destinationProjectID = secondTask.projectID {
            assign(taskID: firstTask.id, to: destinationProjectID)
        } else if let destinationProjectID = firstTask.projectID {
            assign(taskID: secondTask.id, to: destinationProjectID)
        } else {
            pendingGalaxyTaskIDs = [firstTask.id, secondTask.id]
            isNamingGalaxy = true
        }
    }

    @discardableResult
    func createGalaxy(name: String, colorToken: String) -> Bool {
        let taskIDs = pendingGalaxyTaskIDs
        return perform {
            let result = try service().createProject(
                name: name,
                colorToken: colorToken,
                assigningTaskIDs: taskIDs
            )
            showLoggingIssues(result.loggingIssues)
            selectedProjectID = result.project.id
            pendingGalaxyTaskIDs = []
            isNamingGalaxy = false
        }
    }

    func cancelGalaxyCreation() {
        pendingGalaxyTaskIDs = []
        isNamingGalaxy = false
    }

    private func assign(taskID: String, to projectID: String) {
        perform {
            let result = try service().assignTask(id: taskID, to: projectID)
            showLoggingIssue(result.loggingIssue)
        }
    }

    func setReducedMotion(_ enabled: Bool) {
        perform {
            preferences.reducedMotion = enabled
            try repository.savePreferences(preferences)
        }
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Obsidian vault"
        panel.prompt = "Use This Vault"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        perform {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            scopedVaultURL?.stopAccessingSecurityScopedResource()
            scopedVaultURL = url
            _ = url.startAccessingSecurityScopedResource()
            preferences.vaultBookmark = bookmark
            preferences.vaultPath = url.path
            try repository.savePreferences(preferences)
            logger = ObsidianTaskLogger(vaultURL: url)
            vaultMessage = "Logging to \(url.lastPathComponent)"
            try retryPendingLogs()
        }
    }

    func retryPendingLogs() throws {
        let result = try service().retryPendingLogEvents()
        pendingLogCount = try repository.pendingLogEvents().count
        if result.failures.isEmpty {
            vaultMessage = result.succeededEventIDs.isEmpty
                ? "Nothing is waiting to be logged."
                : "Retried \(result.succeededEventIDs.count) task event(s)."
        } else {
            vaultMessage = "\(result.failures.count) task event(s) still need attention."
        }
    }

    private func service() -> TaskActionService {
        TaskActionService(repository: repository, logger: logger)
    }

    private func refresh() throws {
        tasks = try repository.tasks()
        projects = try repository.projects()
        preferences = try repository.preferences()
        pendingLogCount = try repository.pendingLogEvents().count
    }

    @discardableResult
    private func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            try refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = String(describing: error)
            return false
        }
    }

    private func showLoggingIssue(_ issue: String?) {
        guard issue != nil else { return }
        vaultMessage = "Task saved locally. Obsidian logging needs attention."
    }

    private func showLoggingIssues(_ issues: [String]) {
        guard !issues.isEmpty else { return }
        vaultMessage = "Changes saved locally. \(issues.count) Obsidian event(s) need attention."
    }

    private func loadPreferencesAndVault() throws {
        preferences = try repository.preferences()
        guard let bookmark = preferences.vaultBookmark else { return }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else {
            vaultMessage = "Choose the Obsidian vault again to restore access."
            return
        }
        scopedVaultURL = url
        _ = url.startAccessingSecurityScopedResource()
        logger = ObsidianTaskLogger(vaultURL: url)
        vaultMessage = "Logging to \(url.lastPathComponent)"
    }
}

private struct UnavailableTaskEventLogger: TaskEventLogging {
    struct VaultNotConfigured: Error {}

    func append(_ event: TaskLogEvent) throws -> URL {
        throw VaultNotConfigured()
    }
}
