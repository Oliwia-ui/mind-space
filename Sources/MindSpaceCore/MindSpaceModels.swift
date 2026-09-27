import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case active
    case completed
    case trashed
}

public struct MindSpaceTask: Equatable, Codable, Sendable {
    public let id: String
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var projectID: String?
    public var dueDate: Date?
    public var category: String?
    public var energy: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var trashedAt: Date?
    public var isToday: Bool
    public var estimatedFocusMinutes: Int?
    public var externalSessionReferences: [String]
    public var previousStatus: TaskStatus?

    public init(
        id: String,
        title: String,
        notes: String? = nil,
        status: TaskStatus,
        projectID: String? = nil,
        dueDate: Date? = nil,
        category: String? = nil,
        energy: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        trashedAt: Date? = nil,
        isToday: Bool = false,
        estimatedFocusMinutes: Int? = nil,
        externalSessionReferences: [String] = [],
        previousStatus: TaskStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.projectID = projectID
        self.dueDate = dueDate
        self.category = category
        self.energy = energy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.trashedAt = trashedAt
        self.isToday = isToday
        self.estimatedFocusMinutes = estimatedFocusMinutes
        self.externalSessionReferences = externalSessionReferences
        self.previousStatus = previousStatus
    }
}

public struct MindSpaceProject: Equatable, Codable, Sendable {
    public let id: String
    public var name: String
    public var colorToken: String
    public let createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
    public var archivedAt: Date?

    public init(id: String, name: String, colorToken: String, createdAt: Date, updatedAt: Date, isArchived: Bool = false, archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.colorToken = colorToken
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }
}

public struct MindSpacePreferences: Equatable, Sendable {
    public var reducedMotion: Bool
    public var vaultBookmark: Data?
    public var vaultPath: String?

    public init(reducedMotion: Bool = false, vaultBookmark: Data? = nil, vaultPath: String? = nil) {
        self.reducedMotion = reducedMotion
        self.vaultBookmark = vaultBookmark
        self.vaultPath = vaultPath
    }
}

public enum MindSpaceRepositoryError: Error, Equatable, Sendable {
    case invalidTaskTitle
    case invalidProjectName
    case invalidEstimatedFocusMinutes
    case taskNotFound(String)
    case projectNotFound(String)
    case invalidTaskTransition(from: TaskStatus, operation: String)
    case databaseOpenFailed(String)
    case databaseFailure(code: Int32, message: String)
    case corruptStoredValue(field: String, value: String)
}