pub mod domain;
pub mod persistence;

use domain::{CreateProject, CreateTask, Preferences, Project, Task, UpdateProject, UpdateTask};
use persistence::Database;
use tauri::{Manager, State};

struct AppState {
    database: Database,
}

type CommandResult<T> = Result<T, String>;

fn command_error(error: persistence::PersistenceError) -> String {
    error.to_string()
}

#[tauri::command]
fn create_task(state: State<'_, AppState>, input: CreateTask) -> CommandResult<Task> {
    state.database.create_task(input).map_err(command_error)
}

#[tauri::command]
fn get_task(state: State<'_, AppState>, id: String) -> CommandResult<Task> {
    state.database.get_task(&id).map_err(command_error)
}

#[tauri::command]
fn list_tasks(state: State<'_, AppState>) -> CommandResult<Vec<Task>> {
    state.database.list_tasks().map_err(command_error)
}

#[tauri::command]
fn list_today(state: State<'_, AppState>) -> CommandResult<Vec<Task>> {
    state.database.list_today().map_err(command_error)
}

#[tauri::command]
fn update_task(state: State<'_, AppState>, id: String, input: UpdateTask) -> CommandResult<Task> {
    state
        .database
        .update_task(&id, input)
        .map_err(command_error)
}

#[tauri::command]
fn set_task_today(state: State<'_, AppState>, id: String, today: bool) -> CommandResult<Task> {
    state.database.set_today(&id, today).map_err(command_error)
}

#[tauri::command]
fn complete_task(state: State<'_, AppState>, id: String) -> CommandResult<Task> {
    state.database.complete_task(&id).map_err(command_error)
}

#[tauri::command]
fn reopen_task(state: State<'_, AppState>, id: String) -> CommandResult<Task> {
    state.database.reopen_task(&id).map_err(command_error)
}

#[tauri::command]
fn trash_task(state: State<'_, AppState>, id: String) -> CommandResult<Task> {
    state.database.trash_task(&id).map_err(command_error)
}

#[tauri::command]
fn restore_task(state: State<'_, AppState>, id: String) -> CommandResult<Task> {
    state.database.restore_task(&id).map_err(command_error)
}

#[tauri::command]
fn create_project(state: State<'_, AppState>, input: CreateProject) -> CommandResult<Project> {
    state.database.create_project(input).map_err(command_error)
}

#[tauri::command]
fn list_projects(
    state: State<'_, AppState>,
    include_archived: bool,
) -> CommandResult<Vec<Project>> {
    state
        .database
        .list_projects(include_archived)
        .map_err(command_error)
}

#[tauri::command]
fn update_project(
    state: State<'_, AppState>,
    id: String,
    input: UpdateProject,
) -> CommandResult<Project> {
    state
        .database
        .update_project(&id, input)
        .map_err(command_error)
}

#[tauri::command]
fn archive_project(state: State<'_, AppState>, id: String) -> CommandResult<Project> {
    state.database.archive_project(&id).map_err(command_error)
}

#[tauri::command]
fn get_preferences(state: State<'_, AppState>) -> CommandResult<Preferences> {
    state.database.get_preferences().map_err(command_error)
}

#[tauri::command]
fn set_preferences(
    state: State<'_, AppState>,
    preferences: Preferences,
) -> CommandResult<Preferences> {
    state
        .database
        .set_preferences(preferences)
        .map_err(command_error)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let app_data_dir = app.path().app_data_dir()?;
            let database = Database::open(app_data_dir.join("mind-space.sqlite3"))?;
            app.manage(AppState { database });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            create_task,
            get_task,
            list_tasks,
            list_today,
            update_task,
            set_task_today,
            complete_task,
            reopen_task,
            trash_task,
            restore_task,
            create_project,
            list_projects,
            update_project,
            archive_project,
            get_preferences,
            set_preferences,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
