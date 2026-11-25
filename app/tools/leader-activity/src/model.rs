use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Snapshot {
    pub version: u32,
    pub pid: u32,
    pub cwd: String,
    pub updated_at: u64,
    pub running: Vec<ActivityItem>,
    pub events: Vec<ActivityItem>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActivityItem {
    pub id: String,
    pub seq: u64,
    pub name: String,
    pub state: String,
    pub started_at: u64,
    pub updated_at: u64,
    #[serde(default)]
    pub finished_at: Option<u64>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub target: Option<String>,
    #[serde(default)]
    pub percent: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    Running,
    Done,
    Failed,
}

impl ActivityItem {
    pub fn outcome(&self) -> Outcome {
        if self.state.eq_ignore_ascii_case("running") {
            Outcome::Running
        } else if matches!(self.state.to_ascii_lowercase().as_str(), "done" | "success" | "succeeded" | "completed") {
            Outcome::Done
        } else {
            Outcome::Failed
        }
    }

    pub fn state_label(&self) -> String {
        match self.outcome() {
            Outcome::Running => "running".to_owned(),
            Outcome::Done => "done".to_owned(),
            Outcome::Failed => {
                let state = self.state.to_ascii_lowercase();
                if matches!(state.as_str(), "error" | "failed" | "failure") { "failed".to_owned() } else { one_line(&self.state, 12) }
            }
        }
    }

    pub fn detail(&self) -> String {
        let mut parts = Vec::new();
        for value in [&self.title, &self.message, &self.target].into_iter().flatten().map(|text| one_line(text, 160)) {
            if !parts.contains(&value) {
                parts.push(value);
            }
        }
        if parts.is_empty() { "—".to_owned() } else { parts.join(" · ") }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Filter {
    All,
    Running,
    Done,
}

impl Filter {
    pub fn label(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Running => "running",
            Self::Done => "done",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Summary {
    pub running: usize,
    pub done: usize,
    pub failed: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ItemKey {
    id: String,
    seq: u64,
}

impl ActivityItem {
    fn key(&self) -> ItemKey {
        ItemKey { id: self.id.clone(), seq: self.seq }
    }
}

#[derive(Debug, Clone)]
pub struct Model {
    snapshot: Option<Snapshot>,
    filter: Filter,
    follow_newest: bool,
    selected: Option<usize>,
    selected_key: Option<ItemKey>,
    status: String,
    last_checked_at: Option<u64>,
}

impl Default for Model {
    fn default() -> Self {
        Self {
            snapshot: None,
            filter: Filter::All,
            follow_newest: true,
            selected: None,
            selected_key: None,
            status: "waiting for snapshot".to_owned(),
            last_checked_at: None,
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
        self.snapshot = Some(snapshot);
        self.status = "live".to_owned();
        self.last_checked_at = Some(now_ms);
        self.reconcile_selection();
    }

    pub fn apply_error(&mut self, error: &str, now_ms: u64) {
        self.status = one_line(error, 180);
        self.last_checked_at = Some(now_ms);
    }

    pub fn filter(&self) -> Filter {
        self.filter
    }

    pub fn set_filter(&mut self, filter: Filter) {
        if self.filter != filter {
            self.filter = filter;
            self.selected = None;
            self.selected_key = None;
            self.reconcile_selection();
        }
    }

    pub fn follow_newest(&self) -> bool {
        self.follow_newest
    }

    pub fn toggle_follow_newest(&mut self) {
        self.follow_newest = !self.follow_newest;
        self.reconcile_selection();
    }

    pub fn select(&mut self, index: usize) {
        let items = self.visible_items();
        if let Some(item) = items.get(index) {
            self.selected = Some(index);
            self.selected_key = Some(item.key());
        }
    }

    pub fn selected_index(&self) -> Option<usize> {
        self.selected
    }

    pub fn selected_item(&self) -> Option<ActivityItem> {
        let index = self.selected?;
        self.visible_items().get(index).cloned()
    }

    pub fn visible_items(&self) -> Vec<ActivityItem> {
        let Some(snapshot) = &self.snapshot else {
            return Vec::new();
        };
        let mut items = match self.filter {
            Filter::All => {
                let mut items = snapshot.events.clone();
                for running in &snapshot.running {
                    if !items.iter().any(|item| item.key() == running.key()) {
                        items.push(running.clone());
                    }
                }
                items
            }
            Filter::Running => snapshot.running.clone(),
            Filter::Done => snapshot.events.iter().filter(|item| item.outcome() != Outcome::Running).cloned().collect(),
        };
        newest_first(&mut items);
        items
    }

    pub fn summary(&self) -> Summary {
        let Some(snapshot) = &self.snapshot else {
            return Summary::default();
        };
        let mut running = snapshot.running.clone();
        newest_first(&mut running);
        let mut finished = snapshot.events.iter().filter(|item| item.outcome() != Outcome::Running).cloned().collect::<Vec<_>>();
        newest_first(&mut finished);
        Summary {
            running: running.len(),
            done: finished.iter().filter(|item| item.outcome() == Outcome::Done).count(),
            failed: finished.iter().filter(|item| item.outcome() == Outcome::Failed).count(),
        }
    }

    pub fn status_text(&self, now_ms: u64) -> String {
        let Some(snapshot) = &self.snapshot else {
            return format!("no snapshot · {}", self.status);
        };
        let cwd = if snapshot.cwd.is_empty() { "cwd ?" } else { snapshot.cwd.as_str() };
        format!(
            "{} · pid {} · updated {} · {}",
            one_line(cwd, 100),
            snapshot.pid,
            format_elapsed(now_ms.saturating_sub(snapshot.updated_at)),
            self.status
        )
    }

    fn reconcile_selection(&mut self) {
        let items = self.visible_items();
        if items.is_empty() {
            self.selected = None;
            self.selected_key = None;
            return;
        }
        let index = if self.follow_newest {
            Some(0)
        } else if let Some(key) = &self.selected_key {
            items.iter().position(|item| item.key() == *key)
        } else {
            self.selected.map(|index| index.min(items.len() - 1)).or(Some(0))
        };
        self.selected = index;
        self.selected_key = index.map(|index| items[index].key());
    }
}

fn newest_first(items: &mut Vec<ActivityItem>) {
    items.sort_by(|a, b| b.seq.cmp(&a.seq).then_with(|| b.updated_at.cmp(&a.updated_at)).then_with(|| a.id.cmp(&b.id)));
    items.dedup_by(|a, b| a.key() == b.key());
}

pub fn elapsed_ms(item: &ActivityItem, now_ms: u64) -> u64 {
    let end = match item.outcome() {
        Outcome::Running => now_ms,
        Outcome::Done | Outcome::Failed => item.finished_at.unwrap_or(item.updated_at),
    };
    end.saturating_sub(item.started_at)
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

pub fn progress_text(item: &ActivityItem) -> String {
    match item.percent {
        Some(percent) if percent.is_finite() => {
            let percent = percent.clamp(0.0, 100.0);
            if percent.fract() == 0.0 { format!("{percent:.0}%") } else { format!("{percent:.1}%") }
        }
        Some(_) => "—".to_owned(),
        None if item.outcome() == Outcome::Done => "100%".to_owned(),
        None => "—".to_owned(),
    }
}

pub(crate) fn one_line(text: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }
    let mut output = String::new();
    let mut count = 0usize;
    let mut pending_space = false;
    for character in text.chars() {
        if character.is_whitespace() {
            pending_space = !output.is_empty();
            continue;
        }
        if character.is_control() {
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

    fn item(seq: u64, state: &str, started_at: u64, updated_at: u64) -> ActivityItem {
        ActivityItem {
            id: format!("job-{seq}"),
            seq,
            name: format!("Task {seq}"),
            state: state.to_owned(),
            started_at,
            updated_at,
            finished_at: None,
            title: Some(format!("Title {seq}")),
            message: None,
            target: Some(format!("src/{seq}.rs")),
            percent: None,
        }
    }

    fn snapshot(running: Vec<ActivityItem>, events: Vec<ActivityItem>) -> Snapshot {
        Snapshot { version: 1, pid: 42, cwd: "/project".to_owned(), updated_at: 10_000, running, events }
    }

    #[test]
    fn parses_schema_and_optional_fields() {
        let value = serde_json::json!({
            "version": 1,
            "pid": 42,
            "cwd": "/project",
            "updated_at": 10000,
            "running": [{
                "id": "build", "seq": 2, "name": "Build", "state": "running",
                "started_at": 9000, "updated_at": 10000, "percent": 37.5
            }],
            "events": []
        });
        let parsed: Snapshot = serde_json::from_value(value).unwrap();
        assert_eq!(parsed.running[0].message, None);
        assert_eq!(parsed.running[0].percent, Some(37.5));
    }

    #[test]
    fn all_filter_deduplicates_running_events_and_sorts_newest_first() {
        let running = item(3, "running", 8_000, 10_000);
        let old = item(1, "done", 1_000, 2_000);
        let model = Model::with_snapshot(snapshot(vec![running.clone()], vec![old, running]), 10_000);
        let visible = model.visible_items();
        assert_eq!(visible.len(), 2);
        assert_eq!(visible[0].seq, 3);
        assert_eq!(visible[1].seq, 1);
        assert_eq!(model.selected_index(), Some(0));
        assert_eq!(model.summary(), Summary { running: 1, done: 1, failed: 0 });
    }

    #[test]
    fn running_and_done_filters_use_the_right_sides_of_the_feed() {
        let running = item(3, "running", 8_000, 10_000);
        let done = item(2, "done", 4_000, 7_000);
        let failed = item(1, "error", 1_000, 3_000);
        let mut model = Model::with_snapshot(snapshot(vec![running], vec![done.clone(), failed.clone()]), 10_000);

        model.set_filter(Filter::Running);
        assert_eq!(model.visible_items()[0].seq, 3);
        model.set_filter(Filter::Done);
        assert_eq!(model.visible_items().iter().map(|item| item.seq).collect::<Vec<_>>(), vec![2, 1]);
        assert_eq!(model.summary(), Summary { running: 1, done: 1, failed: 1 });
        assert_eq!(done.state_label(), "done");
        assert_eq!(failed.state_label(), "failed");
    }

    #[test]
    fn following_newest_and_pinning_a_selection_are_pure_state_transitions() {
        let first = item(1, "running", 1_000, 2_000);
        let mut model = Model::with_snapshot(snapshot(vec![first.clone()], vec![first]), 2_000);
        model.toggle_follow_newest();
        assert!(!model.follow_newest());

        let second = item(2, "done", 3_000, 4_000);
        model.apply_snapshot(snapshot(Vec::new(), vec![second, item(1, "done", 1_000, 2_000)]), 4_000);
        assert_eq!(model.selected_item().unwrap().seq, 1);

        model.toggle_follow_newest();
        assert_eq!(model.selected_item().unwrap().seq, 2);
        model.select(1);
        assert_eq!(model.selected_item().unwrap().seq, 1);
    }

    #[test]
    fn changing_filter_clears_a_selection_that_no_longer_exists() {
        let done = item(1, "done", 1_000, 2_000);
        let mut model = Model::with_snapshot(snapshot(Vec::new(), vec![done]), 2_000);
        model.set_filter(Filter::Running);
        assert_eq!(model.selected_index(), None);
        assert!(model.visible_items().is_empty());
    }

    #[test]
    fn detail_combines_title_message_and_target() {
        let item = ActivityItem {
            id: "job".to_owned(),
            seq: 1,
            name: "Build".to_owned(),
            state: "done".to_owned(),
            started_at: 1_000,
            updated_at: 2_000,
            finished_at: Some(2_000),
            title: Some("Compiled\npackage".to_owned()),
            message: Some("all targets".to_owned()),
            target: Some("src/main.rs".to_owned()),
            percent: None,
        };
        assert_eq!(item.detail(), "Compiled package · all targets · src/main.rs");
    }

    #[test]
    fn elapsed_uses_clock_for_running_and_finished_at_for_terminal_items() {
        let mut running = item(1, "running", 1_000, 9_000);
        assert_eq!(elapsed_ms(&running, 12_500), 11_500);
        running.finished_at = Some(3_000);
        running.state = "done".to_owned();
        assert_eq!(elapsed_ms(&running, 12_500), 2_000);

        let mut future = item(2, "running", 20_000, 20_000);
        assert_eq!(elapsed_ms(&future, 10_000), 0);
        future.finished_at = None;
        future.state = "error".to_owned();
        future.updated_at = 21_000;
        assert_eq!(elapsed_ms(&future, 10_000), 1_000);
    }

    #[test]
    fn formats_elapsed_and_clamps_progress() {
        assert_eq!(format_elapsed(999), "0s");
        assert_eq!(format_elapsed(60_000), "1m 00s");
        assert_eq!(format_elapsed(3_661_000), "1h 01m");
        assert_eq!(format_elapsed(90_061_000), "1d 01h");

        let mut task = item(1, "running", 0, 0);
        task.percent = Some(150.0);
        assert_eq!(progress_text(&task), "100%");
        task.percent = Some(-2.0);
        assert_eq!(progress_text(&task), "0%");
        task.percent = Some(12.34);
        assert_eq!(progress_text(&task), "12.3%");
        task.percent = Some(f64::NAN);
        assert_eq!(progress_text(&task), "—");
        task.percent = None;
        task.state = "done".to_owned();
        assert_eq!(progress_text(&task), "100%");
    }

    #[test]
    fn display_text_strips_controls_and_truncates_by_characters() {
        assert_eq!(one_line("  build\n\tjob\x1b[31m  ", 20), "build job[31m");
        assert_eq!(one_line("abcdef", 4), "abc…");
        assert_eq!(one_line("αβγδε", 4), "αβγ…");
        assert_eq!(one_line("anything", 0), "");
    }
}
