use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TaskStatus {
    Inbox,
    Active,
    Completed,
    Trashed,
}

impl TaskStatus {
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Inbox => "inbox",
            Self::Active => "active",
            Self::Completed => "completed",
            Self::Trashed => "trashed",
        }
    }

    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "inbox" => Some(Self::Inbox),
            "active" => Some(Self::Active),
            "completed" => Some(Self::Completed),
            "trashed" => Some(Self::Trashed),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EnergyLevel {
    Low,
    Medium,
    High,
}

impl EnergyLevel {
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
        }
    }

    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "low" => Some(Self::Low),
            "medium" => Some(Self::Medium),
            "high" => Some(Self::High),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    pub id: String,
    pub title: String,
    pub notes: Option<String>,
    pub status: TaskStatus,
    pub project_id: Option<String>,
    pub due_at: Option<DateTime<Utc>>,
    pub category: Option<String>,
    pub energy: Option<EnergyLevel>,
    pub estimated_focus_minutes: Option<u32>,
    pub external_session_references: Vec<String>,
    pub today: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub trashed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateTask {
    pub title: String,
    pub notes: Option<String>,
    pub project_id: Option<String>,
    pub due_at: Option<DateTime<Utc>>,
    pub category: Option<String>,
    pub energy: Option<EnergyLevel>,
    pub estimated_focus_minutes: Option<u32>,
    #[serde(default)]
    pub external_session_references: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateTask {
    pub title: Option<String>,
    pub notes: Option<Option<String>>,
    pub project_id: Option<Option<String>>,
    pub due_at: Option<Option<DateTime<Utc>>>,
    pub category: Option<Option<String>>,
    pub energy: Option<Option<EnergyLevel>>,
    pub estimated_focus_minutes: Option<Option<u32>>,
    pub external_session_references: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub archived_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateProject {
    pub name: String,
    pub color: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateProject {
    pub name: Option<String>,
    pub color: Option<Option<String>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Preferences {
    pub reduced_motion: bool,
    pub vault_path: Option<String>,
}
