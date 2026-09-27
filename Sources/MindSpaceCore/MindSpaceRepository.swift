import Foundation
import SQLite3

public final class MindSpaceRepository: @unchecked Sendable {
    private let database: OpaquePointer
    private let lock = NSRecursiveLock()
    private let now: @Sendable () -> Date
    private let taskID: @Sendable () -> String
    private let projectID: @Sendable () -> String

    private init(
        path: String,
        now: @escaping @Sendable () -> Date,
        taskID: @escaping @Sendable () -> String,
        projectID: @escaping @Sendable () -> String
    ) throws {
        self.now = now
        self.taskID = taskID
        self.projectID = projectID
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to allocate SQLite handle"
            if let handle { sqlite3_close(handle) }
            throw MindSpaceRepositoryError.databaseOpenFailed(message)
        }
        database = handle
        do {
            try execute("PRAGMA foreign_keys = ON")
            try migrate()
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    public static func inMemory(
        now: @escaping @Sendable () -> Date = Date.init,
        taskID: @escaping @Sendable () -> String = { "task_\(UUID().uuidString)" },
        projectID: @escaping @Sendable () -> String = { "project_\(UUID().uuidString)" }
    ) throws -> MindSpaceRepository {
        try MindSpaceRepository(path: ":memory:", now: now, taskID: taskID, projectID: projectID)
    }

    public static func disk(
        at url: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        taskID: @escaping @Sendable () -> String = { "task_\(UUID().uuidString)" },
        projectID: @escaping @Sendable () -> String = { "project_\(UUID().uuidString)" }
    ) throws -> MindSpaceRepository {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try MindSpaceRepository(path: url.path, now: now, taskID: taskID, projectID: projectID)
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
    ) throws -> MindSpaceTask {
        let title = try validatedTaskTitle(title)
        try validateFocusMinutes(estimatedFocusMinutes)
        if let projectID { _ = try requiredProject(projectID) }
        let date = now()
        let task = MindSpaceTask(
            id: taskID(), title: title, notes: notes,
            status: projectID == nil ? .inbox : .active, projectID: projectID,
            dueDate: dueDate, category: category, energy: energy,
            createdAt: date, updatedAt: date, isToday: isToday,
            estimatedFocusMinutes: estimatedFocusMinutes,
            externalSessionReferences: externalSessionReferences
        )
        try transaction { try insert(task) }
        return task
    }

    public func task(id: String) throws -> MindSpaceTask? {
        try lock.withLock {
            let statement = try prepare("SELECT \(taskColumns) FROM tasks WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            try bind(id, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeTask(statement)
        }
    }

    public func tasks(status: TaskStatus? = nil) throws -> [MindSpaceTask] {
        try lock.withLock {
            let sql = "SELECT \(taskColumns) FROM tasks" + (status == nil ? "" : " WHERE status = ?") + " ORDER BY created_at, id"
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            if let status { try bind(status.rawValue, to: statement, at: 1) }
            var result: [MindSpaceTask] = []
            while sqlite3_step(statement) == SQLITE_ROW { result.append(try decodeTask(statement)) }
            try checkFinished(statement)
            return result
        }
    }

    public func updateTask(_ task: MindSpaceTask) throws -> MindSpaceTask {
        guard try self.task(id: task.id) != nil else { throw MindSpaceRepositoryError.taskNotFound(task.id) }
        var updated = task
        updated.title = try validatedTaskTitle(task.title)
        try validateFocusMinutes(task.estimatedFocusMinutes)
        if let projectID = task.projectID { _ = try requiredProject(projectID) }
        updated.updatedAt = now()
        try transaction { try replace(updated) }
        return updated
    }

    public func assign(taskID: String, to projectID: String?) throws -> MindSpaceTask {
        var task = try requiredTask(taskID)
        if let projectID { _ = try requiredProject(projectID) }
        task.projectID = projectID
        if task.status == .inbox, projectID != nil { task.status = .active }
        if task.status == .active, projectID == nil { task.status = .inbox }
        return try updateTask(task)
    }

    public func setToday(taskID: String, isToday: Bool) throws -> MindSpaceTask {
        var task = try requiredTask(taskID)
        task.isToday = isToday
        return try updateTask(task)
    }

    public func todayTasks() throws -> [MindSpaceTask] {
        try lock.withLock {
            let statement = try prepare(
                "SELECT \(taskColumns) FROM tasks WHERE is_today = 1 AND status NOT IN ('completed', 'trashed') ORDER BY created_at, id"
            )
            defer { sqlite3_finalize(statement) }
            var result: [MindSpaceTask] = []
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                result.append(try decodeTask(statement))
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE else { throw dbError() }
            return result
        }
    }

    public func complete(taskID: String) throws -> MindSpaceTask {
        var task = try requiredTask(taskID)
        guard task.status != .trashed else { throw MindSpaceRepositoryError.invalidTaskTransition(from: task.status, operation: "complete") }
        guard task.status != .completed else { return task }
        task.previousStatus = task.status
        task.status = .completed
        task.completedAt = now()
        task.isToday = false
        return try updateTask(task)
    }

    public func reopen(taskID: String) throws -> MindSpaceTask {
        var task = try requiredTask(taskID)
        guard task.status == .completed else { throw MindSpaceRepositoryError.invalidTaskTransition(from: task.status, operation: "reopen") }
        task.status = task.previousStatus == .active || task.previousStatus == .inbox ? task.previousStatus! : (task.projectID == nil ? .inbox : .active)
        task.previousStatus = nil
        task.completedAt = nil
        return try updateTask(task)
    }

    public func trash(taskID: String) throws -> MindSpaceTask {
        var task = try requiredTask(taskID)
        guard task.status != .trashed else { return task }
        task.previousStatus = task.status
        task.status = .trashed
        task.trashedAt = now()
        task.isToday = false
        return try updateTask(task)
    }

    public func restore(taskID: String) throws -> MindSpaceTask {
        var task = try requiredTask(taskID)
        guard task.status == .trashed else { throw MindSpaceRepositoryError.invalidTaskTransition(from: task.status, operation: "restore") }
        task.status = task.previousStatus ?? (task.projectID == nil ? .inbox : .active)
        task.previousStatus = nil
        task.trashedAt = nil
        return try updateTask(task)
    }

    public func createProject(
        name: String,
        colorToken: String,
        assigningTaskIDs: [String] = []
    ) throws -> MindSpaceProject {
        let name = try validatedProjectName(name)
        var tasksToAssign = try assigningTaskIDs.map(requiredTask)
        let date = now()
        let project = MindSpaceProject(id: projectID(), name: name, colorToken: colorToken, createdAt: date, updatedAt: date)
        try transaction {
            let statement = try prepare("INSERT INTO projects (id,name,color_token,created_at,updated_at,is_archived,archived_at) VALUES (?,?,?,?,?,0,NULL)")
            defer { sqlite3_finalize(statement) }
            try bind(project.id, to: statement, at: 1); try bind(project.name, to: statement, at: 2); try bind(project.colorToken, to: statement, at: 3)
            sqlite3_bind_double(statement, 4, date.timeIntervalSince1970); sqlite3_bind_double(statement, 5, date.timeIntervalSince1970)
            try stepDone(statement)

            for index in tasksToAssign.indices {
                tasksToAssign[index].projectID = project.id
                if tasksToAssign[index].status == .inbox { tasksToAssign[index].status = .active }
                tasksToAssign[index].updatedAt = date
                try replace(tasksToAssign[index])
            }
        }
        return project
    }

    public func project(id: String) throws -> MindSpaceProject? {
        try lock.withLock {
            let statement = try prepare("SELECT id,name,color_token,created_at,updated_at,is_archived,archived_at FROM projects WHERE id = ?")
            defer { sqlite3_finalize(statement) }; try bind(id, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return decodeProject(statement)
        }
    }

    public func projects(includeArchived: Bool = false) throws -> [MindSpaceProject] {
        try lock.withLock {
            let sql = "SELECT id,name,color_token,created_at,updated_at,is_archived,archived_at FROM projects" + (includeArchived ? "" : " WHERE is_archived = 0") + " ORDER BY created_at,id"
            let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
            var result: [MindSpaceProject] = []
            while sqlite3_step(statement) == SQLITE_ROW { result.append(decodeProject(statement)) }
            try checkFinished(statement); return result
        }
    }

    public func updateProject(_ project: MindSpaceProject) throws -> MindSpaceProject {
        _ = try requiredProject(project.id)
        var updated = project; updated.name = try validatedProjectName(project.name); updated.updatedAt = now()
        try transaction {
            let statement = try prepare("UPDATE projects SET name=?,color_token=?,updated_at=?,is_archived=?,archived_at=? WHERE id=?")
            defer { sqlite3_finalize(statement) }
            try bind(updated.name,to:statement,at:1); try bind(updated.colorToken,to:statement,at:2); sqlite3_bind_double(statement,3,updated.updatedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement,4,updated.isArchived ? 1 : 0); bind(updated.archivedAt?.timeIntervalSince1970,to:statement,at:5); try bind(updated.id,to:statement,at:6); try stepDone(statement)
        }
        return updated
    }

    public func updateProject(_ project: MindSpaceProject, memberTaskIDs: [String]) throws -> MindSpaceProject {
        _ = try requiredProject(project.id)
        let selectedIDs = Set(memberTaskIDs)
        var selectedTasks = try selectedIDs.map(requiredTask)
        var removedTasks = try tasks().filter { $0.projectID == project.id && !selectedIDs.contains($0.id) }
        var updated = project
        updated.name = try validatedProjectName(project.name)
        updated.updatedAt = now()

        try transaction {
            let statement = try prepare("UPDATE projects SET name=?,color_token=?,updated_at=?,is_archived=?,archived_at=? WHERE id=?")
            defer { sqlite3_finalize(statement) }
            try bind(updated.name,to:statement,at:1); try bind(updated.colorToken,to:statement,at:2); sqlite3_bind_double(statement,3,updated.updatedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement,4,updated.isArchived ? 1 : 0); bind(updated.archivedAt?.timeIntervalSince1970,to:statement,at:5); try bind(updated.id,to:statement,at:6); try stepDone(statement)

            for index in removedTasks.indices {
                removedTasks[index].projectID = nil
                if removedTasks[index].status == .active { removedTasks[index].status = .inbox }
                if (removedTasks[index].status == .completed || removedTasks[index].status == .trashed),
                   removedTasks[index].previousStatus == .active {
                    removedTasks[index].previousStatus = .inbox
                }
                removedTasks[index].updatedAt = updated.updatedAt
                try replace(removedTasks[index])
            }
            for index in selectedTasks.indices {
                selectedTasks[index].projectID = project.id
                if selectedTasks[index].status == .inbox { selectedTasks[index].status = .active }
                if (selectedTasks[index].status == .completed || selectedTasks[index].status == .trashed),
                   selectedTasks[index].previousStatus == .inbox {
                    selectedTasks[index].previousStatus = .active
                }
                selectedTasks[index].updatedAt = updated.updatedAt
                try replace(selectedTasks[index])
            }
        }
        return updated
    }

    public func setProjectArchived(projectID: String, isArchived: Bool) throws -> MindSpaceProject {
        var project = try requiredProject(projectID); project.isArchived = isArchived; project.archivedAt = isArchived ? now() : nil
        return try updateProject(project)
    }

    public func dissolveProject(projectID: String) throws {
        _ = try requiredProject(projectID)
        let date = now()
        try transaction {
            let taskStatement = try prepare(
                "UPDATE tasks SET project_id=NULL,status=CASE WHEN status='active' THEN 'inbox' ELSE status END,previous_status=CASE WHEN status IN ('completed','trashed') AND previous_status='active' THEN 'inbox' ELSE previous_status END,updated_at=? WHERE project_id=?"
            )
            defer { sqlite3_finalize(taskStatement) }
            sqlite3_bind_double(taskStatement, 1, date.timeIntervalSince1970)
            try bind(projectID, to: taskStatement, at: 2)
            try stepDone(taskStatement)

            let projectStatement = try prepare(
                "UPDATE projects SET is_archived=1,archived_at=?,updated_at=? WHERE id=?"
            )
            defer { sqlite3_finalize(projectStatement) }
            sqlite3_bind_double(projectStatement, 1, date.timeIntervalSince1970)
            sqlite3_bind_double(projectStatement, 2, date.timeIntervalSince1970)
            try bind(projectID, to: projectStatement, at: 3)
            try stepDone(projectStatement)
        }
    }

    public func preferences() throws -> MindSpacePreferences {
        try lock.withLock {
            let statement = try prepare("SELECT reduced_motion,vault_bookmark,vault_path FROM preferences WHERE singleton = 1")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return MindSpacePreferences() }
            let bookmark: Data? = sqlite3_column_type(statement,1) == SQLITE_NULL ? nil : Data(bytes: sqlite3_column_blob(statement,1), count: Int(sqlite3_column_bytes(statement,1)))
            return MindSpacePreferences(reducedMotion: sqlite3_column_int(statement,0) != 0, vaultBookmark: bookmark, vaultPath: text(statement,2))
        }
    }

    public func savePreferences(_ preferences: MindSpacePreferences) throws {
        try transaction {
            let statement = try prepare("UPDATE preferences SET reduced_motion=?,vault_bookmark=?,vault_path=? WHERE singleton=1")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement,1,preferences.reducedMotion ? 1 : 0)
            if let data = preferences.vaultBookmark {
                let result = data.withUnsafeBytes {
                    sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), transient)
                }
                guard result == SQLITE_OK else { throw dbError() }
            } else {
                sqlite3_bind_null(statement, 2)
            }
            try bind(preferences.vaultPath,to:statement,at:3); try stepDone(statement)
        }
    }

    public func objectPositions() throws -> [MindSpaceObjectPosition] {
        try lock.withLock {
            let statement = try prepare("SELECT object_id,kind,normalized_x,normalized_y FROM mind_space_positions ORDER BY kind,object_id")
            defer { sqlite3_finalize(statement) }
            var positions: [MindSpaceObjectPosition] = []
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                guard let objectID = text(statement, 0),
                      let kindValue = text(statement, 1),
                      let kind = MindSpaceObjectKind(rawValue: kindValue) else {
                    throw MindSpaceRepositoryError.corruptStoredValue(
                        field: "mind_space_positions.kind",
                        value: text(statement, 1) ?? "NULL"
                    )
                }
                positions.append(MindSpaceObjectPosition(
                    objectID: objectID,
                    kind: kind,
                    normalizedX: sqlite3_column_double(statement, 2),
                    normalizedY: sqlite3_column_double(statement, 3)
                ))
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE else { throw dbError() }
            return positions
        }
    }

    public func saveObjectPositions(_ positions: [MindSpaceObjectPosition]) throws {
        try transaction {
            let statement = try prepare(
                "INSERT OR REPLACE INTO mind_space_positions (object_id,kind,normalized_x,normalized_y) VALUES (?,?,?,?)"
            )
            defer { sqlite3_finalize(statement) }
            for position in positions {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(position.objectID, to: statement, at: 1)
                try bind(position.kind.rawValue, to: statement, at: 2)
                sqlite3_bind_double(statement, 3, min(max(position.normalizedX, 0), 1))
                sqlite3_bind_double(statement, 4, min(max(position.normalizedY, 0), 1))
                try stepDone(statement)
            }
        }
    }

    public func resetObjectPositions() throws {
        try transaction { try execute("DELETE FROM mind_space_positions") }
    }

    public func enqueueLogEvent(_ event: TaskLogEvent) throws {
        let payload = try String(decoding: JSONEncoder().encode(event), as: UTF8.self)
        try transaction {
            let statement = try prepare("INSERT OR REPLACE INTO pending_task_log_events (event_id, payload, created_at) VALUES (?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            try bind(event.eventID, to: statement, at: 1)
            try bind(payload, to: statement, at: 2)
            sqlite3_bind_double(statement, 3, event.timestamp.timeIntervalSince1970)
            try stepDone(statement)
        }
    }

    public func pendingLogEvents() throws -> [TaskLogEvent] {
        try lock.withLock {
            let statement = try prepare("SELECT payload FROM pending_task_log_events ORDER BY created_at, event_id")
            defer { sqlite3_finalize(statement) }
            var events: [TaskLogEvent] = []
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                guard let payload = text(statement, 0), let data = payload.data(using: .utf8) else {
                    throw MindSpaceRepositoryError.corruptStoredValue(field: "pending_task_log_events.payload", value: "NULL")
                }
                do {
                    events.append(try JSONDecoder().decode(TaskLogEvent.self, from: data))
                } catch {
                    throw MindSpaceRepositoryError.corruptStoredValue(field: "pending_task_log_events.payload", value: payload)
                }
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE else { throw dbError() }
            return events
        }
    }

    public func removePendingLogEvent(eventID: String) throws {
        try transaction {
            let statement = try prepare("DELETE FROM pending_task_log_events WHERE event_id = ?")
            defer { sqlite3_finalize(statement) }
            try bind(eventID, to: statement, at: 1)
            try stepDone(statement)
        }
    }

    private var taskColumns: String { "id,title,notes,status,project_id,due_date,category,energy,created_at,updated_at,completed_at,trashed_at,is_today,estimated_focus_minutes,external_session_references,previous_status" }

    private func migrate() throws {
        var version = try scalarInt("PRAGMA user_version")
        guard version <= 3 else { throw MindSpaceRepositoryError.databaseFailure(code: SQLITE_ERROR, message: "Database schema version \(version) is newer than supported version 3") }
        if version == 0 {
            try transaction {
                try execute("CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT NOT NULL, color_token TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, is_archived INTEGER NOT NULL DEFAULT 0, archived_at REAL)")
                try execute("CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT, status TEXT NOT NULL, project_id TEXT REFERENCES projects(id), due_date REAL, category TEXT, energy TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL, completed_at REAL, trashed_at REAL, is_today INTEGER NOT NULL DEFAULT 0, estimated_focus_minutes INTEGER, external_session_references TEXT NOT NULL DEFAULT '[]', previous_status TEXT)")
                try execute("CREATE INDEX tasks_status_index ON tasks(status)")
                try execute("CREATE INDEX tasks_project_index ON tasks(project_id)")
                try execute("CREATE TABLE preferences (singleton INTEGER PRIMARY KEY CHECK(singleton=1), reduced_motion INTEGER NOT NULL DEFAULT 0, vault_bookmark BLOB, vault_path TEXT)")
                try execute("INSERT INTO preferences(singleton) VALUES (1)")
                try execute("PRAGMA user_version = 1")
            }
            version = 1
        }
        if version == 1 {
            try transaction {
                try execute("CREATE TABLE pending_task_log_events (event_id TEXT PRIMARY KEY, payload TEXT NOT NULL, created_at REAL NOT NULL)")
                try execute("PRAGMA user_version = 2")
            }
            version = 2
        }
        if version == 2 {
            try transaction {
                try execute("CREATE TABLE mind_space_positions (object_id TEXT NOT NULL, kind TEXT NOT NULL, normalized_x REAL NOT NULL, normalized_y REAL NOT NULL, PRIMARY KEY (object_id, kind))")
                try execute("PRAGMA user_version = 3")
            }
        }
    }

    private func insert(_ task: MindSpaceTask) throws {
        let statement = try prepare("INSERT INTO tasks (\(taskColumns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(statement) }; try bindTask(task,to:statement); try stepDone(statement)
    }

    private func replace(_ task: MindSpaceTask) throws {
        let assignments = taskColumns.split(separator: ",").dropFirst().map { "\($0)=?" }.joined(separator: ",")
        let statement = try prepare("UPDATE tasks SET \(assignments) WHERE id=?")
        defer { sqlite3_finalize(statement) }
        try bindTask(task,to:statement,excludingID:true); try bind(task.id,to:statement,at:16); try stepDone(statement)
    }

    private func bindTask(_ task: MindSpaceTask, to statement: OpaquePointer, excludingID: Bool = false) throws {
        var index: Int32 = 1
        if !excludingID { try bind(task.id,to:statement,at:index); index += 1 }
        try bind(task.title,to:statement,at:index); index += 1; try bind(task.notes,to:statement,at:index); index += 1; try bind(task.status.rawValue,to:statement,at:index); index += 1
        try bind(task.projectID,to:statement,at:index); index += 1; bind(task.dueDate?.timeIntervalSince1970,to:statement,at:index); index += 1; try bind(task.category,to:statement,at:index); index += 1; try bind(task.energy,to:statement,at:index); index += 1
        sqlite3_bind_double(statement,index,task.createdAt.timeIntervalSince1970); index += 1; sqlite3_bind_double(statement,index,task.updatedAt.timeIntervalSince1970); index += 1
        bind(task.completedAt?.timeIntervalSince1970,to:statement,at:index); index += 1; bind(task.trashedAt?.timeIntervalSince1970,to:statement,at:index); index += 1; sqlite3_bind_int(statement,index,task.isToday ? 1 : 0); index += 1
        if let minutes = task.estimatedFocusMinutes { sqlite3_bind_int64(statement,index,sqlite3_int64(minutes)) } else { sqlite3_bind_null(statement,index) }; index += 1
        let sessions = try String(data: JSONEncoder().encode(task.externalSessionReferences), encoding: .utf8)!; try bind(sessions,to:statement,at:index); index += 1; try bind(task.previousStatus?.rawValue,to:statement,at:index)
    }

    private func decodeTask(_ s: OpaquePointer) throws -> MindSpaceTask {
        guard let statusText = text(s,3), let status = TaskStatus(rawValue: statusText) else { throw MindSpaceRepositoryError.corruptStoredValue(field:"status",value:text(s,3) ?? "NULL") }
        let sessionsText = text(s,14) ?? "[]"
        guard let sessionsData = sessionsText.data(using:.utf8), let sessions = try? JSONDecoder().decode([String].self,from:sessionsData) else { throw MindSpaceRepositoryError.corruptStoredValue(field:"external_session_references",value:sessionsText) }
        let previous: TaskStatus?
        if let value = text(s,15) { guard let decoded = TaskStatus(rawValue:value) else { throw MindSpaceRepositoryError.corruptStoredValue(field:"previous_status",value:value) }; previous = decoded } else { previous = nil }
        return MindSpaceTask(id:text(s,0)!,title:text(s,1)!,notes:text(s,2),status:status,projectID:text(s,4),dueDate:date(s,5),category:text(s,6),energy:text(s,7),createdAt:Date(timeIntervalSince1970:sqlite3_column_double(s,8)),updatedAt:Date(timeIntervalSince1970:sqlite3_column_double(s,9)),completedAt:date(s,10),trashedAt:date(s,11),isToday:sqlite3_column_int(s,12) != 0,estimatedFocusMinutes:sqlite3_column_type(s,13) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s,13)),externalSessionReferences:sessions,previousStatus:previous)
    }

    private func decodeProject(_ s: OpaquePointer) -> MindSpaceProject { MindSpaceProject(id:text(s,0)!,name:text(s,1)!,colorToken:text(s,2)!,createdAt:Date(timeIntervalSince1970:sqlite3_column_double(s,3)),updatedAt:Date(timeIntervalSince1970:sqlite3_column_double(s,4)),isArchived:sqlite3_column_int(s,5) != 0,archivedAt:date(s,6)) }
    private func requiredTask(_ id:String) throws -> MindSpaceTask { guard let value = try task(id:id) else { throw MindSpaceRepositoryError.taskNotFound(id) }; return value }
    private func requiredProject(_ id:String) throws -> MindSpaceProject { guard let value = try project(id:id) else { throw MindSpaceRepositoryError.projectNotFound(id) }; return value }
    private func validatedTaskTitle(_ value:String) throws -> String { let v=value.trimmingCharacters(in:.whitespacesAndNewlines); guard !v.isEmpty else { throw MindSpaceRepositoryError.invalidTaskTitle }; return v }
    private func validatedProjectName(_ value:String) throws -> String { let v=value.trimmingCharacters(in:.whitespacesAndNewlines); guard !v.isEmpty else { throw MindSpaceRepositoryError.invalidProjectName }; return v }
    private func validateFocusMinutes(_ value:Int?) throws { if let value, value <= 0 { throw MindSpaceRepositoryError.invalidEstimatedFocusMinutes } }
    private func transaction<T>(_ body:() throws -> T) throws -> T { try lock.withLock { try execute("BEGIN IMMEDIATE"); do { let value=try body(); try execute("COMMIT"); return value } catch { try? execute("ROLLBACK"); throw error } } }
    private func execute(_ sql:String) throws { var error:UnsafeMutablePointer<CChar>?; if sqlite3_exec(database,sql,nil,nil,&error) != SQLITE_OK { let message=error.map { String(cString: $0) } ?? String(cString:sqlite3_errmsg(database)); sqlite3_free(error); throw MindSpaceRepositoryError.databaseFailure(code:sqlite3_errcode(database),message:message) } }
    private func prepare(_ sql:String) throws -> OpaquePointer { var s:OpaquePointer?; guard sqlite3_prepare_v2(database,sql,-1,&s,nil) == SQLITE_OK, let s else { throw dbError() }; return s }
    private func scalarInt(_ sql:String) throws -> Int { let s=try prepare(sql); defer { sqlite3_finalize(s) }; guard sqlite3_step(s) == SQLITE_ROW else { throw dbError() }; return Int(sqlite3_column_int(s,0)) }
    private func stepDone(_ s:OpaquePointer) throws { guard sqlite3_step(s) == SQLITE_DONE else { throw dbError() } }
    private func checkFinished(_ s:OpaquePointer) throws { guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else { throw dbError() } }
    private func dbError() -> MindSpaceRepositoryError { .databaseFailure(code:sqlite3_errcode(database),message:String(cString:sqlite3_errmsg(database))) }
    private var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }
    private func bind(_ value:String?,to s:OpaquePointer,at i:Int32) throws { let result:Int32; if let value { result=sqlite3_bind_text(s,i,value,-1,transient) } else { result=sqlite3_bind_null(s,i) }; guard result == SQLITE_OK else { throw dbError() } }
    private func bind(_ value:Double?,to s:OpaquePointer,at i:Int32) { if let value { sqlite3_bind_double(s,i,value) } else { sqlite3_bind_null(s,i) } }
    private func text(_ s:OpaquePointer,_ i:Int32) -> String? { guard sqlite3_column_type(s,i) != SQLITE_NULL, let c=sqlite3_column_text(s,i) else { return nil }; return String(cString:c) }
    private func date(_ s:OpaquePointer,_ i:Int32) -> Date? { sqlite3_column_type(s,i) == SQLITE_NULL ? nil : Date(timeIntervalSince1970:sqlite3_column_double(s,i)) }
}