use chrono::{TimeZone, Utc};
use mind_space_lib::domain::{
    CreateProject, CreateTask, EnergyLevel, Preferences, TaskStatus, UpdateProject, UpdateTask,
};
use mind_space_lib::persistence::Database;
use tempfile::tempdir;

fn open_temp_database() -> (tempfile::TempDir, Database) {
    let directory = tempdir().expect("temporary directory");
    let database = Database::open(directory.path().join("mind-space.sqlite3")).expect("database");
    (directory, database)
}

#[test]
fn new_tasks_default_to_inbox_with_stable_ids_and_survive_reopen() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("mind-space.sqlite3");

    let created = {
        let database = Database::open(&path).expect("database");
        database
            .create_task(CreateTask {
                title: "Read chapter".into(),
                ..CreateTask::default()
            })
            .expect("create task")
    };

    assert!(created.id.starts_with("task_"));
    assert_eq!(created.id.len(), 41);
    assert_eq!(created.status, TaskStatus::Inbox);
    assert!(!created.today);

    let reopened = Database::open(&path).expect("reopen database");
    assert_eq!(reopened.get_task(&created.id).expect("saved task"), created);
}

#[test]
fn task_details_can_be_edited_and_today_is_explicit() {
    let (_directory, database) = open_temp_database();
    let project = database
        .create_project(CreateProject {
            name: "Coursework".into(),
            color: Some("#C56A3D".into()),
        })
        .expect("create project");
    let task = database
        .create_task(CreateTask {
            title: "Draft essay".into(),
            ..CreateTask::default()
        })
        .expect("create task");
    let due = Utc.with_ymd_and_hms(2026, 10, 12, 17, 0, 0).unwrap();

    let edited = database
        .update_task(
            &task.id,
            UpdateTask {
                title: Some("Draft final essay".into()),
                notes: Some(Some("Use primary sources".into())),
                project_id: Some(Some(project.id.clone())),
                due_at: Some(Some(due)),
                category: Some(Some("study".into())),
                energy: Some(Some(EnergyLevel::High)),
                estimated_focus_minutes: Some(Some(50)),
                external_session_references: Some(vec!["focus_session_1".into()]),
            },
        )
        .expect("edit task");

    assert_eq!(edited.title, "Draft final essay");
    assert_eq!(edited.notes.as_deref(), Some("Use primary sources"));
    assert_eq!(edited.project_id.as_deref(), Some(project.id.as_str()));
    assert_eq!(edited.due_at, Some(due));
    assert_eq!(edited.category.as_deref(), Some("study"));
    assert_eq!(edited.energy, Some(EnergyLevel::High));
    assert_eq!(edited.estimated_focus_minutes, Some(50));
    assert_eq!(edited.external_session_references, ["focus_session_1"]);

    assert!(
        database
            .set_today(&task.id, true)
            .expect("add to today")
            .today
    );
    assert_eq!(database.list_today().expect("today tasks").len(), 1);
    assert!(
        !database
            .set_today(&task.id, false)
            .expect("remove from today")
            .today
    );
    assert!(database.list_today().expect("empty today").is_empty());
}

#[test]
fn tasks_can_be_completed_reopened_trashed_and_restored() {
    let (_directory, database) = open_temp_database();
    let task = database
        .create_task(CreateTask {
            title: "Submit assignment".into(),
            ..CreateTask::default()
        })
        .expect("create task");

    let completed = database.complete_task(&task.id).expect("complete task");
    assert_eq!(completed.status, TaskStatus::Completed);
    assert!(completed.completed_at.is_some());

    let reopened = database.reopen_task(&task.id).expect("reopen task");
    assert_eq!(reopened.status, TaskStatus::Active);
    assert!(reopened.completed_at.is_none());

    let trashed = database.trash_task(&task.id).expect("trash task");
    assert_eq!(trashed.status, TaskStatus::Trashed);
    assert!(trashed.trashed_at.is_some());
    assert!(database.list_tasks().expect("visible tasks").is_empty());

    let restored = database.restore_task(&task.id).expect("restore task");
    assert_eq!(restored.status, TaskStatus::Active);
    assert!(restored.trashed_at.is_none());
}

#[test]
fn projects_can_be_created_updated_listed_and_archived() {
    let (_directory, database) = open_temp_database();
    let project = database
        .create_project(CreateProject {
            name: "Personal".into(),
            color: None,
        })
        .expect("create project");

    let updated = database
        .update_project(
            &project.id,
            UpdateProject {
                name: Some("Home".into()),
                color: Some(Some("#224466".into())),
            },
        )
        .expect("update project");
    assert_eq!(updated.name, "Home");
    assert_eq!(updated.color.as_deref(), Some("#224466"));
    let active_projects = database.list_projects(false).expect("projects");
    assert_eq!(active_projects.len(), 1);
    assert_eq!(active_projects.first(), Some(&updated));

    let archived = database
        .archive_project(&project.id)
        .expect("archive project");
    assert!(archived.archived_at.is_some());
    assert!(database
        .list_projects(false)
        .expect("active projects")
        .is_empty());
    assert_eq!(
        database.list_projects(true).expect("all projects"),
        [archived]
    );
}

#[test]
fn preferences_are_persisted() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("mind-space.sqlite3");
    let expected = Preferences {
        reduced_motion: true,
        vault_path: Some("/Users/example/Obsidian".into()),
    };

    {
        let database = Database::open(&path).expect("database");
        assert_eq!(
            database.get_preferences().expect("defaults"),
            Preferences::default()
        );
        database
            .set_preferences(expected.clone())
            .expect("save preferences");
    }

    let reopened = Database::open(path).expect("reopen database");
    assert_eq!(reopened.get_preferences().expect("preferences"), expected);
}
