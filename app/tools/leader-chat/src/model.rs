use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const SNAPSHOT_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Snapshot {
    pub version: u32,
    pub pid: u32,
    pub cwd: String,
    pub updated_at: u64,
    pub session: Session,
    pub messages: Vec<Message>,
    pub profiles: Vec<Profile>,
    pub models: Vec<ModelOption>,
    pub history: Vec<HistoryEntry>,
    #[serde(default)]
    pub ack: Option<CommandAck>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommandAck {
    pub id: String,
    pub ok: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Session {
    pub id: String,
    pub title: String,
    pub model: String,
    pub profile: String,
    #[serde(default)]
    pub effort: Option<String>,
    pub running: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub role: String,
    pub text: String,
    #[serde(default)]
    pub thinking: Option<String>,
    pub at: u64,
    #[serde(default)]
    pub state: Option<String>,
    #[serde(default)]
    pub usage: Option<Value>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Profile {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelOption {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub id: String,
    pub title: String,
    pub at: u64,
    pub model: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Overlay {
    History,
    Models,
    Profiles,
}

impl Overlay {
    pub fn title(self) -> &'static str {
        match self {
            Self::History => "History",
            Self::Models => "Model",
            Self::Profiles => "Profile",
        }
    }

    pub fn empty_text(self) -> &'static str {
        match self {
            Self::History => "No saved sessions.",
            Self::Models => "No models advertised by Leader.",
            Self::Profiles => "No profiles advertised by Leader.",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OverlayEntry {
    pub id: String,
    pub label: String,
    pub detail: String,
    pub current: bool,
}

#[derive(Debug, Clone)]
pub struct Model {
    snapshot: Option<Snapshot>,
    status: String,
    read_error: Option<String>,
    command_status: Option<String>,
    command_error: Option<String>,
    last_ack: Option<String>,
    last_read_at: Option<u64>,
    overlay: Option<Overlay>,
}

impl Default for Model {
    fn default() -> Self {
        Self {
            snapshot: None,
            status: "waiting for snapshot".to_owned(),
            read_error: None,
            command_status: None,
            command_error: None,
            last_ack: None,
            last_read_at: None,
            overlay: None,
        }
    }
}

impl Model {
    pub fn with_snapshot(snapshot: Snapshot, now_ms: u64) -> Self {
        let mut model = Self::default();
        model.apply_snapshot(snapshot, now_ms);
        model
    }

    pub fn apply_snapshot(&mut self, snapshot: Snapshot, now_ms: u64) {
        if let Some(ack) = &snapshot.ack
            && self.last_ack.as_deref() != Some(ack.id.as_str())
        {
            self.last_ack = Some(ack.id.clone());
            if ack.ok {
                self.set_command_status(format!("command {} accepted", ack.id));
            } else {
                self.set_command_error(ack.error.clone().unwrap_or_else(|| "command rejected".to_owned()));
            }
        }
        self.snapshot = Some(snapshot);
        self.status = "live".to_owned();
        self.read_error = None;
        self.last_read_at = Some(now_ms);
    }

    pub fn apply_read_error(&mut self, error: &str, now_ms: u64) {
        self.status = one_line(error, 180);
        self.read_error = Some(self.status.clone());
        self.last_read_at = Some(now_ms);
    }

    pub fn set_command_status(&mut self, status: impl Into<String>) {
        self.command_status = Some(one_line(&status.into(), 120));
        self.command_error = None;
    }

    pub fn set_command_error(&mut self, error: impl Into<String>) {
        self.command_error = Some(one_line(&error.into(), 180));
        self.command_status = None;
    }

    pub fn snapshot(&self) -> Option<&Snapshot> {
        self.snapshot.as_ref()
    }

    pub fn session(&self) -> Option<&Session> {
        self.snapshot.as_ref().map(|snapshot| &snapshot.session)
    }

    pub fn running(&self) -> bool {
        self.session().is_some_and(|session| session.running)
    }

    pub fn overlay(&self) -> Option<Overlay> {
        self.overlay
    }

    pub fn open_overlay(&mut self, overlay: Overlay) {
        self.overlay = Some(overlay);
    }

    pub fn close_overlay(&mut self) {
        self.overlay = None;
    }

    pub fn has_error(&self) -> bool {
        self.read_error.is_some() || self.command_error.is_some()
    }

    pub fn header_title(&self) -> String {
        self.session()
            .map(|session| if session.title.trim().is_empty() { "New chat".to_owned() } else { one_line(&session.title, 72) })
            .unwrap_or_else(|| "Leader Chat".to_owned())
    }

    pub fn metadata(&self) -> String {
        let Some(snapshot) = &self.snapshot else {
            return "waiting for Leader…".to_owned();
        };
        let session = &snapshot.session;
        let model = model_label_for(&snapshot.models, &session.model);
        let profile = profile_label_for(&snapshot.profiles, &session.profile);
        let effort = session.effort.as_deref().map(|effort| format!(" · {effort}")).unwrap_or_default();
        let cwd = if snapshot.cwd.is_empty() { "cwd ?".to_owned() } else { one_line(&snapshot.cwd, 90) };
        format!("{} · {model} · {profile}{effort} · {cwd}", one_line(&session.id, 48))
    }

    pub fn status_text(&self, now_ms: u64) -> String {
        let mut parts = Vec::new();
        if let Some(snapshot) = &self.snapshot {
            parts.push("live".to_owned());
            parts.push(format!("updated {}", format_elapsed(now_ms.saturating_sub(snapshot.updated_at))));
            parts.push(format!("{} messages", snapshot.messages.len()));
        } else {
            parts.push(self.status.clone());
        }
        if let Some(last_read_at) = self.last_read_at {
            parts.push(format!("read {}", format_elapsed(now_ms.saturating_sub(last_read_at))));
        }
        if let Some(read_error) = &self.read_error {
            parts.push(format!("read error: {read_error}"));
        }
        if let Some(command_status) = &self.command_status {
            parts.push(command_status.clone());
        }
        if let Some(command_error) = &self.command_error {
            parts.push(command_error.clone());
        }
        one_line(&parts.join(" · "), 240)
    }

    pub fn overlay_entries(&self) -> Vec<OverlayEntry> {
        let Some(overlay) = self.overlay else {
            return Vec::new();
        };
        let Some(snapshot) = &self.snapshot else {
            return Vec::new();
        };
        match overlay {
            Overlay::History => snapshot
                .history
                .iter()
                .map(|entry| OverlayEntry {
                    id: entry.id.clone(),
                    label: if entry.title.trim().is_empty() { entry.id.clone() } else { one_line(&entry.title, 64) },
                    detail: format!(
                        "{} · {} · {}",
                        one_line(&entry.id, 40),
                        model_label_for(&snapshot.models, &entry.model),
                        format_clock(entry.at)
                    ),
                    current: entry.id == snapshot.session.id,
                })
                .collect(),
            Overlay::Models => snapshot
                .models
                .iter()
                .map(|entry| OverlayEntry {
                    id: entry.id.clone(),
                    label: one_line(&entry.label, 64),
                    detail: one_line(&entry.id, 80),
                    current: entry.id == snapshot.session.model,
                })
                .collect(),
            Overlay::Profiles => snapshot
                .profiles
                .iter()
                .map(|entry| OverlayEntry {
                    id: entry.id.clone(),
                    label: one_line(&entry.label, 64),
                    detail: one_line(&entry.id, 80),
                    current: entry.id == snapshot.session.profile,
                })
                .collect(),
        }
    }

    pub fn command_for_overlay(&self, index: usize) -> Option<crate::commands::Command> {
        let entry = self.overlay_entries().get(index)?.clone();
        match self.overlay? {
            Overlay::History => Some(crate::commands::Command::select_session(entry.id)),
            Overlay::Models => Some(crate::commands::Command::set_model(entry.id)),
            Overlay::Profiles => Some(crate::commands::Command::set_profile(entry.id)),
        }
    }
}

pub fn transcript_markdown(snapshot: Option<&Snapshot>, pulse: usize) -> String {
    let Some(snapshot) = snapshot else {
        return "*Waiting for a Leader chat snapshot…*".to_owned();
    };
    if snapshot.messages.is_empty() {
        return "*No messages yet. Write the first one below.*".to_owned();
    }

    let mut lines = Vec::new();
    let last = snapshot.messages.len() - 1;
    for (index, message) in snapshot.messages.iter().enumerate() {
        let normalized_role = message.role.to_ascii_lowercase();
        let role = normalized_role.as_str();
        let mut heading = format!("### {role} · {}", format_clock(message.at));
        if let Some(state) = message.state.as_deref().filter(|state| !state.trim().is_empty()) {
            heading.push_str(" · ");
            heading.push_str(&one_line(state, 24));
        }
        if index == last && role == "assistant" && snapshot.session.running {
            heading.push_str(" · streaming");
        }
        lines.push(one_line(&heading, 160));

        if let Some(thinking) = message.thinking.as_deref().map(display_text).filter(|thinking| !thinking.trim().is_empty()) {
            lines.push("**Thinking**".to_owned());
            lines.extend(thinking.lines().map(|line| format!("> {line}")));
        }

        let text = display_text(&message.text);
        if text.trim().is_empty() {
            if index == last && role == "assistant" && snapshot.session.running {
                lines.push(format!("*streaming{}*", ".".repeat(pulse % 3 + 1)));
            } else {
                lines.push("*(empty message)*".to_owned());
            }
        } else {
            lines.push(text);
        }

        if let Some(error) = message.error.as_deref().filter(|error| !error.trim().is_empty()) {
            lines.push(format!("> **Error:** {}", one_line(&display_text(error), 240)));
        }
        if let Some(usage) = message.usage.as_ref().filter(|usage| !usage.is_null()) {
            let usage = serde_json::to_string(usage).unwrap_or_else(|_| "unknown".to_owned());
            lines.push(format!("*usage: {}*", one_line(&usage, 180)));
        }
        lines.push(String::new());
    }
    lines.join("\n")
}

fn model_label_for(entries: &[ModelOption], id: &str) -> String {
    entries.iter().find(|entry| entry.id == id).map(|entry| entry.label.as_str()).filter(|label| !label.is_empty()).unwrap_or(id).to_owned()
}

fn profile_label_for(entries: &[Profile], id: &str) -> String {
    entries.iter().find(|entry| entry.id == id).map(|entry| entry.label.as_str()).filter(|label| !label.is_empty()).unwrap_or(id).to_owned()
}

pub fn format_clock(at: u64) -> String {
    if at == 0 {
        return "--:--".to_owned();
    }
    let seconds = (at / 1_000) % 86_400;
    format!("{:02}:{:02}", seconds / 3_600, (seconds % 3_600) / 60)
}

pub fn format_elapsed(milliseconds: u64) -> String {
    let seconds = milliseconds / 1_000;
    match seconds {
        0..=59 => format!("{seconds}s"),
        60..=3_599 => format!("{}m {:02}s", seconds / 60, seconds % 60),
        3_600..=86_399 => format!("{}h {:02}m", seconds / 3_600, (seconds % 3_600) / 60),
        _ => format!("{}d {:02}h", seconds / 86_400, (seconds % 86_400) / 3_600),
    }
}

pub(crate) fn display_text(text: &str) -> String {
    text.replace("\r\n", "\n")
        .replace('\r', "\n")
        .chars()
        .filter(|character| !character.is_control() || matches!(character, '\n' | '\t'))
        .collect()
}

pub(crate) fn one_line(text: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }
    let mut output = String::new();
    let mut count = 0usize;
    let mut pending_space = false;
    for character in display_text(text).chars() {
        if character.is_whitespace() {
            pending_space = !output.is_empty();
            continue;
        }
        if count == max_chars {
            output.pop();
            output.push('…');
            break;
        }
        if pending_space {
            output.push(' ');
            count += 1;
            pending_space = false;
            if count == max_chars {
                output.pop();
                output.push('…');
                break;
            }
        }
        output.push(character);
        count += 1;
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn snapshot() -> Snapshot {
        serde_json::from_value(json!({
            "version": 1,
            "pid": 42,
            "cwd": "/project",
            "updated_at": 10_000,
            "session": {
                "id": "session-1",
                "title": "Refactor the parser",
                "model": "model-a",
                "profile": "profile-a",
                "effort": "high",
                "running": true
            },
            "messages": [{
                "id": "message-1",
                "role": "assistant",
                "text": "Hello **world**\n\n```rust\nfn main() {}\n```",
                "thinking": "First line\nSecond line",
                "at": 9_000,
                "state": "streaming",
                "usage": {"input": 12, "output": 4},
                "error": "example error"
            }],
            "profiles": [{"id": "profile-a", "label": "Careful"}],
            "models": [{"id": "model-a", "label": "Model A"}],
            "history": [{"id": "session-0", "title": "Older chat", "at": 8_000, "model": "model-a"}]
        }))
        .unwrap()
    }

    #[test]
    fn parses_the_full_schema_and_optional_fields() {
        let parsed = snapshot();
        assert_eq!(parsed.version, SNAPSHOT_VERSION);
        assert_eq!(parsed.session.effort.as_deref(), Some("high"));
        assert_eq!(parsed.messages[0].thinking.as_deref(), Some("First line\nSecond line"));
        assert_eq!(parsed.messages[0].usage, Some(json!({"input": 12, "output": 4})));

        let mut value = serde_json::to_value(&parsed).unwrap();
        value["session"].as_object_mut().unwrap().remove("effort");
        value["messages"][0].as_object_mut().unwrap().remove("thinking");
        let parsed: Snapshot = serde_json::from_value(value).unwrap();
        assert_eq!(parsed.session.effort, None);
        assert_eq!(parsed.messages[0].thinking, None);
    }

    #[test]
    fn metadata_resolves_model_and_profile_labels() {
        let model = Model::with_snapshot(snapshot(), 10_000);
        assert_eq!(model.header_title(), "Refactor the parser");
        assert!(model.running());
        let metadata = model.metadata();
        assert!(metadata.contains("session-1"), "{metadata}");
        assert!(metadata.contains("Model A"), "{metadata}");
        assert!(metadata.contains("Careful"), "{metadata}");
        assert!(metadata.contains("high"), "{metadata}");
    }

    #[test]
    fn overlays_keep_ids_and_build_the_matching_commands() {
        let mut model = Model::with_snapshot(snapshot(), 10_000);
        model.open_overlay(Overlay::History);
        let entries = model.overlay_entries();
        assert_eq!(entries[0].id, "session-0");
        assert_eq!(model.command_for_overlay(0).unwrap().action, crate::commands::Action::SelectSession);

        model.open_overlay(Overlay::Models);
        assert_eq!(model.command_for_overlay(0).unwrap().value.as_deref(), Some("model-a"));
        model.open_overlay(Overlay::Profiles);
        assert_eq!(model.command_for_overlay(0).unwrap().value.as_deref(), Some("profile-a"));
    }

    #[test]
    fn command_ack_changes_status_once() {
        let mut model = Model::with_snapshot(snapshot(), 10_000);
        let mut snapshot = snapshot();
        snapshot.ack = Some(crate::model::CommandAck { id: "cmd-1".to_owned(), ok: false, error: Some("busy".to_owned()) });
        model.apply_snapshot(snapshot.clone(), 10_100);
        assert!(model.status_text(10_100).contains("busy"));
        model.apply_snapshot(snapshot, 10_200);
        assert!(model.status_text(10_200).contains("busy"));
    }

    #[test]
    fn transcript_keeps_markdown_and_adds_thinking_errors_and_usage() {
        let markdown = transcript_markdown(Some(&snapshot()), 2);
        assert!(markdown.contains("### assistant · 00:00 · streaming"));
        assert!(markdown.contains("Hello **world**"));
        assert!(markdown.contains("```rust\nfn main() {}"));
        assert!(markdown.contains("**Thinking**"));
        assert!(markdown.contains("> First line\n> Second line"));
        assert!(markdown.contains("**Error:** example error"));
        assert!(markdown.contains("usage:"));
    }

    #[test]
    fn read_errors_preserve_the_last_valid_snapshot() {
        let mut model = Model::with_snapshot(snapshot(), 10_000);
        model.apply_read_error("invalid JSON", 11_000);
        assert_eq!(model.snapshot().unwrap().session.id, "session-1");
        assert!(model.has_error());
        assert!(model.status_text(11_000).contains("invalid JSON"));
    }

    #[test]
    fn formats_clock_elapsed_and_safe_display_text() {
        assert_eq!(format_clock(0), "--:--");
        assert_eq!(format_clock(3_661_000), "01:01");
        assert_eq!(format_elapsed(60_000), "1m 00s");
        assert_eq!(format_elapsed(3_661_000), "1h 01m");
        assert_eq!(display_text("a\r\nb\x1b[31m"), "a\nb[31m");
        assert_eq!(one_line("αβγδε", 4), "αβγ…");
    }
}
