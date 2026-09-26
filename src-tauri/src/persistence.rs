use std::{fs, path::Path, sync::Mutex};

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, OptionalExtension, Row, Transaction};
use thiserror::Error;
use uuid::Uuid;

use crate::domain::{
    CreateProject, CreateTask, EnergyLevel, Preferences, Project, Task, TaskStatus, UpdateProject,
    UpdateTask,
};

const TASK_COLUMNS: &str = "id, title, notes, status, project_id, due_at, category, energy, estimated_focus_minutes, external_session_references, today, created_at, updated_at, completed_at, trashed_at";
const PROJECT_COLUMNS: &str = "id, name, color, created_at, updated_at, archived_at";

#[derive(Debug, Error)]
pub enum PersistenceError {
    #[error("database error: {0}")]
    Database(#[from] rusqlite::Error),
    #[error("invalid stored date: {0}")]
    Date(#[from] chrono::ParseError),
    #[error("invalid stored JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("{entity} not found: {id}")]
    NotFound { entity: &'static str, id: String },
    #[error("validation failed: {0}")]
    Validation(String),
    #[error("database lock is unavailable")]
    Lock,
    #[error("failed to create database directory: {0}")]
    Directory(#[from] std::io::Error),
    #[error("invalid value in database column {column}: {value}")]
    InvalidValue { column: &'static str, value: String },
}

pub type Result<T> = std::result::Result<T, PersistenceError>;

pub struct Database {
    connection: Mutex<Connection>,
}

impl Database {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let connection = Connection::open(path)?;
        connection.pragma_update(None, "foreign_keys", "ON")?;
        connection.pragma_update(None, "journal_mode", "WAL")?;
        migrate(&connection)?;
        Ok(Self {
            connection: Mutex::new(connection),
        })
    }

    pub fn create_task(&self, input: CreateTask) -> Result<Task> {
        validate_required("task title", &input.title)?;
        validate_focus_minutes(input.estimated_focus_minutes)?;
        let mut connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let transaction = connection.transaction()?;
        validate_project(&transaction, input.project_id.as_deref())?;

        let id = format!("task_{}", Uuid::new_v4());
        let now = Utc::now();
        let status = if input.project_id.is_some() {
            TaskStatus::Active
        } else {
            TaskStatus::Inbox
        };
        transaction.execute(
            "INSERT INTO tasks (id, title, notes, status, project_id, due_at, category, energy, estimated_focus_minutes, external_session_references, today, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 0, ?11, ?11)",
            params![
                id,
                input.title.trim(),
                input.notes,
                status.as_str(),
                input.project_id,
                format_optional_date(input.due_at),
                input.category,
                input.energy.map(EnergyLevel::as_str),
                input.estimated_focus_minutes,
                serde_json::to_string(&input.external_session_references)?,
                format_date(now),
            ],
        )?;
        let task = get_task_from(&transaction, &id)?;
        transaction.commit()?;
        Ok(task)
    }

    pub fn get_task(&self, id: &str) -> Result<Task> {
        let connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        get_task_from(&connection, id)
    }

    pub fn list_tasks(&self) -> Result<Vec<Task>> {
        let connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        query_tasks(
            &connection,
            "SELECT {columns} FROM tasks WHERE status != 'trashed' ORDER BY created_at, id",
        )
    }

    pub fn list_today(&self) -> Result<Vec<Task>> {
        let connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        query_tasks(
            &connection,
            "SELECT {columns} FROM tasks WHERE today = 1 AND status NOT IN ('completed', 'trashed') ORDER BY created_at, id",
        )
    }

    pub fn update_task(&self, id: &str, input: UpdateTask) -> Result<Task> {
        let mut connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let transaction = connection.transaction()?;
        let mut task = get_task_from(&transaction, id)?;

        if let Some(title) = input.title {
            validate_required("task title", &title)?;
            task.title = title.trim().to_owned();
        }
        if let Some(notes) = input.notes {
            task.notes = notes;
        }
        if let Some(project_id) = input.project_id {
            validate_project(&transaction, project_id.as_deref())?;
            task.project_id = project_id;
        }
        if let Some(due_at) = input.due_at {
            task.due_at = due_at;
        }
        if let Some(category) = input.category {
            task.category = category;
        }
        if let Some(energy) = input.energy {
            task.energy = energy;
        }
        if let Some(minutes) = input.estimated_focus_minutes {
            validate_focus_minutes(minutes)?;
            task.estimated_focus_minutes = minutes;
        }
        if let Some(references) = input.external_session_references {
            task.external_session_references = references;
        }
        task.updated_at = Utc::now();

        transaction.execute(
            "UPDATE tasks SET title = ?2, notes = ?3, project_id = ?4, due_at = ?5, category = ?6, energy = ?7, estimated_focus_minutes = ?8, external_session_references = ?9, updated_at = ?10 WHERE id = ?1",
            params![
                id,
                task.title,
                task.notes,
                task.project_id,
                format_optional_date(task.due_at),
                task.category,
                task.energy.map(EnergyLevel::as_str),
                task.estimated_focus_minutes,
                serde_json::to_string(&task.external_session_references)?,
                format_date(task.updated_at),
            ],
        )?;
        let updated = get_task_from(&transaction, id)?;
        transaction.commit()?;
        Ok(updated)
    }

    pub fn set_today(&self, id: &str, today: bool) -> Result<Task> {
        self.update_task_state(id, |transaction, now| {
            let changed = transaction.execute(
                "UPDATE tasks SET today = ?2, updated_at = ?3 WHERE id = ?1 AND status NOT IN ('completed', 'trashed')",
                params![id, today, format_date(now)],
            )?;
            ensure_changed(changed, "task", id)
        })
    }

    pub fn complete_task(&self, id: &str) -> Result<Task> {
        self.update_task_state(id, |transaction, now| {
            let changed = transaction.execute(
                "UPDATE tasks SET status = 'completed', completed_at = ?2, trashed_at = NULL, today = 0, updated_at = ?2 WHERE id = ?1 AND status != 'trashed'",
                params![id, format_date(now)],
            )?;
            ensure_changed(changed, "task", id)
        })
    }

    pub fn reopen_task(&self, id: &str) -> Result<Task> {
        self.update_task_state(id, |transaction, now| {
            let changed = transaction.execute(
                "UPDATE tasks SET status = 'active', completed_at = NULL, updated_at = ?2 WHERE id = ?1 AND status = 'completed'",
                params![id, format_date(now)],
            )?;
            ensure_changed(changed, "task", id)
        })
    }

    pub fn trash_task(&self, id: &str) -> Result<Task> {
        self.update_task_state(id, |transaction, now| {
            let changed = transaction.execute(
                "UPDATE tasks SET previous_status = status, status = 'trashed', trashed_at = ?2, today = 0, updated_at = ?2 WHERE id = ?1 AND status != 'trashed'",
                params![id, format_date(now)],
            )?;
            ensure_changed(changed, "task", id)
        })
    }

    pub fn restore_task(&self, id: &str) -> Result<Task> {
        self.update_task_state(id, |transaction, now| {
            let changed = transaction.execute(
                "UPDATE tasks SET status = COALESCE(previous_status, 'active'), previous_status = NULL, trashed_at = NULL, updated_at = ?2 WHERE id = ?1 AND status = 'trashed'",
                params![id, format_date(now)],
            )?;
            ensure_changed(changed, "task", id)
        })
    }

    pub fn create_project(&self, input: CreateProject) -> Result<Project> {
        validate_required("project name", &input.name)?;
        let mut connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let transaction = connection.transaction()?;
        let id = format!("project_{}", Uuid::new_v4());
        let now = Utc::now();
        transaction.execute(
            "INSERT INTO projects (id, name, color, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)",
            params![id, input.name.trim(), input.color, format_date(now)],
        )?;
        let project = get_project_from(&transaction, &id)?;
        transaction.commit()?;
        Ok(project)
    }

    pub fn list_projects(&self, include_archived: bool) -> Result<Vec<Project>> {
        let connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let where_clause = if include_archived {
            ""
        } else {
            " WHERE archived_at IS NULL"
        };
        let sql =
            format!("SELECT {PROJECT_COLUMNS} FROM projects{where_clause} ORDER BY created_at, id");
        let mut statement = connection.prepare(&sql)?;
        let rows = statement.query_map([], project_from_row)?;
        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(Into::into)
    }

    pub fn update_project(&self, id: &str, input: UpdateProject) -> Result<Project> {
        let mut connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let transaction = connection.transaction()?;
        let mut project = get_project_from(&transaction, id)?;
        if let Some(name) = input.name {
            validate_required("project name", &name)?;
            project.name = name.trim().to_owned();
        }
        if let Some(color) = input.color {
            project.color = color;
        }
        project.updated_at = Utc::now();
        transaction.execute(
            "UPDATE projects SET name = ?2, color = ?3, updated_at = ?4 WHERE id = ?1",
            params![
                id,
                project.name,
                project.color,
                format_date(project.updated_at)
            ],
        )?;
        let updated = get_project_from(&transaction, id)?;
        transaction.commit()?;
        Ok(updated)
    }

    pub fn archive_project(&self, id: &str) -> Result<Project> {
        let mut connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let transaction = connection.transaction()?;
        let now = Utc::now();
        let changed = transaction.execute(
            "UPDATE projects SET archived_at = ?2, updated_at = ?2 WHERE id = ?1 AND archived_at IS NULL",
            params![id, format_date(now)],
        )?;
        ensure_changed(changed, "project", id)?;
        let project = get_project_from(&transaction, id)?;
        transaction.commit()?;
        Ok(project)
    }

    pub fn get_preferences(&self) -> Result<Preferences> {
        let connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        connection
            .query_row(
                "SELECT reduced_motion, vault_path FROM preferences WHERE id = 1",
                [],
                |row| {
                    Ok(Preferences {
                        reduced_motion: row.get(0)?,
                        vault_path: row.get(1)?,
                    })
                },
            )
            .map_err(Into::into)
    }

    pub fn set_preferences(&self, preferences: Preferences) -> Result<Preferences> {
        let mut connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let transaction = connection.transaction()?;
        transaction.execute(
            "UPDATE preferences SET reduced_motion = ?1, vault_path = ?2 WHERE id = 1",
            params![preferences.reduced_motion, preferences.vault_path],
        )?;
        let saved = transaction.query_row(
            "SELECT reduced_motion, vault_path FROM preferences WHERE id = 1",
            [],
            |row| {
                Ok(Preferences {
                    reduced_motion: row.get(0)?,
                    vault_path: row.get(1)?,
                })
            },
        )?;
        transaction.commit()?;
        Ok(saved)
    }

    fn update_task_state(
        &self,
        id: &str,
        update: impl FnOnce(&Transaction<'_>, DateTime<Utc>) -> Result<()>,
    ) -> Result<Task> {
        let mut connection = self.connection.lock().map_err(|_| PersistenceError::Lock)?;
        let transaction = connection.transaction()?;
        update(&transaction, Utc::now())?;
        let task = get_task_from(&transaction, id)?;
        transaction.commit()?;
        Ok(task)
    }
}

fn migrate(connection: &Connection) -> Result<()> {
    connection.execute_batch(
        "BEGIN;
         CREATE TABLE IF NOT EXISTS projects (
             id TEXT PRIMARY KEY,
             name TEXT NOT NULL,
             color TEXT,
             created_at TEXT NOT NULL,
             updated_at TEXT NOT NULL,
             archived_at TEXT
         );
         CREATE TABLE IF NOT EXISTS tasks (
             id TEXT PRIMARY KEY,
             title TEXT NOT NULL,
             notes TEXT,
             status TEXT NOT NULL CHECK (status IN ('inbox', 'active', 'completed', 'trashed')),
             previous_status TEXT CHECK (previous_status IS NULL OR previous_status IN ('inbox', 'active', 'completed')),
             project_id TEXT REFERENCES projects(id),
             due_at TEXT,
             category TEXT,
             energy TEXT CHECK (energy IS NULL OR energy IN ('low', 'medium', 'high')),
             estimated_focus_minutes INTEGER CHECK (estimated_focus_minutes IS NULL OR estimated_focus_minutes > 0),
             external_session_references TEXT NOT NULL DEFAULT '[]',
             today INTEGER NOT NULL DEFAULT 0 CHECK (today IN (0, 1)),
             created_at TEXT NOT NULL,
             updated_at TEXT NOT NULL,
             completed_at TEXT,
             trashed_at TEXT
         );
         CREATE INDEX IF NOT EXISTS tasks_status_idx ON tasks(status);
         CREATE INDEX IF NOT EXISTS tasks_today_idx ON tasks(today) WHERE today = 1;
         CREATE INDEX IF NOT EXISTS tasks_project_idx ON tasks(project_id);
         CREATE TABLE IF NOT EXISTS preferences (
             id INTEGER PRIMARY KEY CHECK (id = 1),
             reduced_motion INTEGER NOT NULL DEFAULT 0 CHECK (reduced_motion IN (0, 1)),
             vault_path TEXT
         );
         INSERT OR IGNORE INTO preferences (id) VALUES (1);
         PRAGMA user_version = 1;
         COMMIT;",
    )?;
    Ok(())
}

fn query_tasks(connection: &Connection, template: &str) -> Result<Vec<Task>> {
    let sql = template.replace("{columns}", TASK_COLUMNS);
    let mut statement = connection.prepare(&sql)?;
    let rows = statement.query_map([], task_from_row)?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
        .map_err(Into::into)
}

fn get_task_from(connection: &Connection, id: &str) -> Result<Task> {
    let sql = format!("SELECT {TASK_COLUMNS} FROM tasks WHERE id = ?1");
    connection
        .query_row(&sql, [id], task_from_row)
        .optional()?
        .ok_or_else(|| PersistenceError::NotFound {
            entity: "task",
            id: id.to_owned(),
        })
}

fn task_from_row(row: &Row<'_>) -> rusqlite::Result<Task> {
    let status_value: String = row.get(3)?;
    let energy_value: Option<String> = row.get(7)?;
    let references: String = row.get(9)?;
    Ok(Task {
        id: row.get(0)?,
        title: row.get(1)?,
        notes: row.get(2)?,
        status: TaskStatus::parse(&status_value).ok_or_else(|| invalid_column(3, "status"))?,
        project_id: row.get(4)?,
        due_at: parse_optional_date(row.get(5)?).map_err(to_sql_conversion)?,
        category: row.get(6)?,
        energy: energy_value
            .map(|value| EnergyLevel::parse(&value).ok_or_else(|| invalid_column(7, "energy")))
            .transpose()?,
        estimated_focus_minutes: row.get(8)?,
        external_session_references: serde_json::from_str(&references)
            .map_err(to_sql_conversion)?,
        today: row.get(10)?,
        created_at: parse_date(&row.get::<_, String>(11)?).map_err(to_sql_conversion)?,
        updated_at: parse_date(&row.get::<_, String>(12)?).map_err(to_sql_conversion)?,
        completed_at: parse_optional_date(row.get(13)?).map_err(to_sql_conversion)?,
        trashed_at: parse_optional_date(row.get(14)?).map_err(to_sql_conversion)?,
    })
}

fn get_project_from(connection: &Connection, id: &str) -> Result<Project> {
    let sql = format!("SELECT {PROJECT_COLUMNS} FROM projects WHERE id = ?1");
    connection
        .query_row(&sql, [id], project_from_row)
        .optional()?
        .ok_or_else(|| PersistenceError::NotFound {
            entity: "project",
            id: id.to_owned(),
        })
}

fn project_from_row(row: &Row<'_>) -> rusqlite::Result<Project> {
    Ok(Project {
        id: row.get(0)?,
        name: row.get(1)?,
        color: row.get(2)?,
        created_at: parse_date(&row.get::<_, String>(3)?).map_err(to_sql_conversion)?,
        updated_at: parse_date(&row.get::<_, String>(4)?).map_err(to_sql_conversion)?,
        archived_at: parse_optional_date(row.get(5)?).map_err(to_sql_conversion)?,
    })
}

fn validate_project(transaction: &Transaction<'_>, id: Option<&str>) -> Result<()> {
    if let Some(id) = id {
        let exists = transaction
            .query_row(
                "SELECT 1 FROM projects WHERE id = ?1 AND archived_at IS NULL",
                [id],
                |_| Ok(()),
            )
            .optional()?
            .is_some();
        if !exists {
            return Err(PersistenceError::NotFound {
                entity: "project",
                id: id.to_owned(),
            });
        }
    }
    Ok(())
}

fn validate_required(field: &str, value: &str) -> Result<()> {
    if value.trim().is_empty() {
        return Err(PersistenceError::Validation(format!(
            "{field} cannot be empty"
        )));
    }
    Ok(())
}

fn validate_focus_minutes(minutes: Option<u32>) -> Result<()> {
    if minutes == Some(0) {
        return Err(PersistenceError::Validation(
            "estimated focus minutes must be greater than zero".into(),
        ));
    }
    Ok(())
}

fn ensure_changed(changed: usize, entity: &'static str, id: &str) -> Result<()> {
    if changed == 0 {
        return Err(PersistenceError::NotFound {
            entity,
            id: id.to_owned(),
        });
    }
    Ok(())
}

fn format_date(value: DateTime<Utc>) -> String {
    value.to_rfc3339()
}

fn format_optional_date(value: Option<DateTime<Utc>>) -> Option<String> {
    value.map(format_date)
}

fn parse_date(value: &str) -> std::result::Result<DateTime<Utc>, chrono::ParseError> {
    DateTime::parse_from_rfc3339(value).map(|date| date.with_timezone(&Utc))
}

fn parse_optional_date(
    value: Option<String>,
) -> std::result::Result<Option<DateTime<Utc>>, chrono::ParseError> {
    value.map(|date| parse_date(&date)).transpose()
}

fn invalid_column(index: usize, column: &'static str) -> rusqlite::Error {
    rusqlite::Error::InvalidColumnType(index, column.into(), rusqlite::types::Type::Text)
}

fn to_sql_conversion(error: impl std::error::Error + Send + Sync + 'static) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(error))
}
