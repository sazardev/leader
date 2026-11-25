use crate::model::{ActivityItem, Filter, Model, Snapshot, elapsed_ms, format_elapsed, one_line, progress_text};
use crate::reader::{ReadOutcome, SnapshotPoller, unix_ms};
use opentui::prelude::*;
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::{Duration, SystemTime};

const REFRESH_INTERVAL: Duration = Duration::from_millis(500);

#[derive(Clone)]
pub struct ActivityUi {
    model: Rc<RefCell<Model>>,
    clock: Rc<Cell<u64>>,
    root: View,
    header: View,
    summary: Text,
    status: Text,
    table_panel: View,
    table: Table,
    detail_panel: View,
    details: Text,
    footer: Text,
}

impl ActivityUi {
    pub fn build(app: &App, poller: Option<SnapshotPoller>, initial: Option<Snapshot>, now_ms: u64) -> Self {
        let theme = app.theme();
        let model = Rc::new(RefCell::new(match initial {
            Some(snapshot) => Model::with_snapshot(snapshot, now_ms),
            None => Model::default(),
        }));
        let clock = Rc::new(Cell::new(now_ms));
        let root = app.root();
        let header = View::new(app).row().justify(Justify::SpaceBetween).height(1);
        let title = Text::new(app, "Leader Activity").fg(theme.accent).bold().wrap(WrapMode::None);
        let summary = Text::new(app, "").wrap(WrapMode::None);
        let status = Text::new(app, "").fg(theme.muted).wrap(WrapMode::None).height(1);
        let table = Table::new(app)
            .set_columns(columns(app.size().0))
            .fg(theme.foreground)
            .header_colors(theme.muted, theme.surface)
            .selected_colors(theme.highlight_fg, theme.highlight_bg)
            .stripe_color(theme.surface)
            .striped(true)
            .grow(1.0);
        let table_panel = View::new(app)
            .border(BorderStyle::Rounded)
            .border_color(theme.border)
            .title(" Activity ")
            .title_color(theme.muted)
            .padding_x(1)
            .min_height(3)
            .grow(1.0)
            .child(&table);
        let details = Text::new(app, "").wrap(WrapMode::Word);
        let detail_panel = View::new(app)
            .border(BorderStyle::Rounded)
            .border_color(theme.border)
            .title(" Details ")
            .title_color(theme.muted)
            .padding_x(1)
            .child(&details);
        let footer = Text::new(app, "").fg(theme.muted).wrap(WrapMode::None).height(1);

        root.add(&header);
        header.add(&title).add(&summary);
        root.add(&status).add(&table_panel).add(&detail_panel).add(&footer);

        let ui = Self { model, clock, root, header, summary, status, table_panel, table, detail_panel, details, footer };
        ui.apply_layout(app);
        ui.refresh(app, now_ms);
        ui.install_handlers(app, poller);
        ui
    }

    pub fn model_handle(&self) -> Rc<RefCell<Model>> {
        Rc::clone(&self.model)
    }

    pub fn refresh_now(&self, app: &App, poller: &SnapshotPoller) {
        poller.poll(&app.proxy());
    }

    pub fn refresh(&self, app: &App, now_ms: u64) {
        self.clock.set(now_ms);
        let theme = app.theme();
        let (summary, status, rows, selected, detail_lines) = {
            let model = self.model.borrow();
            let items = model.visible_items();
            let rows = items.iter().map(|item| row(item, now_ms)).collect::<Vec<_>>();
            let selected = model.selected_index();
            let detail_lines = detail_height(app.size().1).saturating_sub(2) as usize;
            (model.summary(), model.status_text(now_ms), rows, selected, details_text(model.selected_item().as_ref(), now_ms, detail_lines))
        };

        self.summary.set_text(summary_content(summary, theme));
        self.status.set_text(status);
        self.table.set_rows(rows);
        self.table.select(selected);
        self.details.set_text(detail_lines);
        self.footer.set_text(footer_content(self.model.borrow().filter(), self.model.borrow().follow_newest(), theme));
    }

    pub fn apply_outcome(&self, outcome: &ReadOutcome) {
        match &outcome.result {
            Ok(snapshot) => self.model.borrow_mut().apply_snapshot(snapshot.clone(), outcome.read_at),
            Err(error) => self.model.borrow_mut().apply_error(error, outcome.read_at),
        }
    }

    fn install_handlers(&self, app: &App, poller: Option<SnapshotPoller>) {
        let table = self.table.clone();
        let details = self.details.clone();
        let model = Rc::clone(&self.model);
        let clock = Rc::clone(&self.clock);
        table.on_change(move |cx, index| {
            model.borrow_mut().select(index);
            let lines = detail_height(cx.size().1).saturating_sub(2) as usize;
            let text = details_text(model.borrow().selected_item().as_ref(), clock.get(), lines);
            details.set_text(text);
        });

        let ui = self.clone();
        let key_poller = poller.clone();
        app.on_key(move |cx, key| {
            let handled = if key.matches("q") || key.matches("escape") {
                cx.quit();
                true
            } else if key.matches("1") {
                ui.model.borrow_mut().set_filter(Filter::All);
                true
            } else if key.matches("2") {
                ui.model.borrow_mut().set_filter(Filter::Running);
                true
            } else if key.matches("3") {
                ui.model.borrow_mut().set_filter(Filter::Done);
                true
            } else if key.matches("f") {
                ui.model.borrow_mut().toggle_follow_newest();
                true
            } else if key.matches("r") {
                if let Some(poller) = &key_poller {
                    poller.poll(&cx.proxy());
                }
                true
            } else {
                false
            };
            if handled {
                ui.refresh(cx, unix_ms(SystemTime::now()));
            }
        });

        let resized = self.clone();
        app.on_resize(move |cx, _width, _height| {
            resized.apply_layout(cx);
            resized.refresh(cx, unix_ms(SystemTime::now()));
        });

        let messaged = self.clone();
        app.on_message(move |cx, outcome: &ReadOutcome| {
            messaged.apply_outcome(outcome);
            messaged.refresh(cx, outcome.read_at);
        });

        if let Some(poller) = poller {
            let proxy = app.proxy();
            let timer_ui = self.clone();
            app.set_interval(REFRESH_INTERVAL, move |cx| {
                poller.poll(&proxy);
                timer_ui.refresh(cx, unix_ms(SystemTime::now()));
            });
        }
        self.table.focus();
    }

    fn apply_layout(&self, app: &App) {
        let (width, height) = app.size();
        let roomy = width >= 60 && height >= 18;
        self.root.padding(if roomy { 1 } else { 0 });
        self.root.gap(if height >= 20 { 1 } else { 0 });
        self.header.direction(if width < 60 { FlexDirection::Column } else { FlexDirection::Row }).height(if width < 60 { 2 } else { 1 });
        self.header.visible(height >= 3);
        self.status.visible(height >= 7);
        self.footer.visible(height >= 5);
        self.detail_panel.height(detail_height(height));
        self.table_panel.padding_x(if width >= 50 { 1 } else { 0 });
        self.table.show_header(height >= 9);
        self.table.set_columns(columns(width));
    }
}

fn columns(width: u16) -> Vec<Column> {
    let wide = width >= 90;
    vec![
        Column::new("State").width(ColumnWidth::Cells(if wide { 9 } else { 7 })),
        Column::new("Task").width(ColumnWidth::Fill(1.2)),
        Column::new("Detail").width(ColumnWidth::Fill(if wide { 2.0 } else { 1.0 })),
        Column::new("Elapsed").width(ColumnWidth::Cells(if wide { 10 } else { 7 })).align(Alignment::Right),
        Column::new("Progress").width(ColumnWidth::Cells(if wide { 9 } else { 7 })).align(Alignment::Right),
    ]
}

fn row(item: &ActivityItem, now_ms: u64) -> Vec<String> {
    vec![item.state_label(), one_line(&item.name, 80), item.detail(), format_elapsed(elapsed_ms(item, now_ms)), progress_text(item)]
}

fn summary_content(summary: crate::model::Summary, theme: Theme) -> Content {
    vec![
        "Running ".fg(theme.muted),
        summary.running.to_string().fg(theme.success).bold(),
        "   Done ".fg(theme.muted),
        summary.done.to_string().fg(theme.success).bold(),
        "   Failed ".fg(theme.muted),
        summary.failed.to_string().fg(theme.error).bold(),
    ]
    .into()
}

fn footer_content(filter: Filter, follow_newest: bool, theme: Theme) -> Content {
    let mut spans = Vec::new();
    for (number, candidate) in [(1, Filter::All), (2, Filter::Running), (3, Filter::Done)] {
        if candidate == filter {
            spans.push(format!("[{number} {}]", candidate.label()).fg(theme.accent).bold());
        } else {
            spans.push(format!(" {number} {} ", candidate.label()).fg(theme.muted));
        }
    }
    spans.push("  ".into());
    spans.push(if follow_newest { "f newest:on".fg(theme.success) } else { "f newest:off".fg(theme.warning) });
    spans.push("   r refresh   q quit".fg(theme.muted));
    spans.into()
}

fn detail_height(terminal_height: u16) -> u16 {
    match terminal_height {
        0..=9 => 3,
        10..=17 => 4,
        _ => 6,
    }
}

fn details_text(item: Option<&ActivityItem>, now_ms: u64, max_lines: usize) -> String {
    let Some(item) = item else {
        return "No activity selected.".to_owned();
    };
    if max_lines <= 1 {
        return format!("{} · {} · {} #{}", one_line(&item.name, 60), item.state_label(), one_line(&item.id, 40), item.seq);
    }

    let header = format!("{} · {} · {} #{}", one_line(&item.name, 60), item.state_label(), one_line(&item.id, 40), item.seq);
    let mut lines = vec![header];
    if max_lines >= 4 {
        if let Some(title) = &item.title {
            lines.push(format!("title: {}", one_line(title, 160)));
        }
        if let Some(message) = &item.message {
            lines.push(format!("message: {}", one_line(message, 160)));
        }
    }
    let mut detail = Vec::new();
    for value in [&item.title, &item.message, &item.target].into_iter().flatten().map(|value| one_line(value, 80)) {
        if !detail.contains(&value) {
            detail.push(value);
        }
    }
    lines.push(if detail.is_empty() { "No detail.".to_owned() } else { detail.join(" · ") });
    if max_lines >= 3 {
        let finished = item.finished_at.map(|at| format!(" · finished {}", format_elapsed(now_ms.saturating_sub(at)))).unwrap_or_default();
        lines.push(format!("elapsed {} · progress {}{finished}", format_elapsed(elapsed_ms(item, now_ms)), progress_text(item)));
    }
    lines.truncate(max_lines);
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::ActivityItem;
    use crate::reader::SnapshotPoller;
    use opentui::testing::TestApp;
    use serde_json::json;
    use std::fs;

    fn item(seq: u64, name: &str, state: &str) -> ActivityItem {
        ActivityItem {
            id: format!("job-{seq}"),
            seq,
            name: name.to_owned(),
            state: state.to_owned(),
            started_at: 1_000,
            updated_at: 5_000,
            finished_at: (state != "running").then_some(5_000),
            title: Some(format!("{name} title")),
            message: Some(format!("{name} message")),
            target: Some("src/main.rs".to_owned()),
            percent: Some(50.0),
        }
    }

    fn snapshot() -> Snapshot {
        Snapshot {
            version: 1,
            pid: 42,
            cwd: "/project".to_owned(),
            updated_at: 5_000,
            running: vec![item(3, "Build", "running")],
            events: vec![item(2, "Tests", "done"), item(1, "Lint", "error")],
        }
    }

    fn test_app(width: u16, height: u16) -> TestApp {
        TestApp::with_options(width, height, AppOptions::default().with_theme(Theme::dark()))
    }

    #[test]
    fn test_app_renders_summary_table_and_selected_details() {
        let app = test_app(110, 26);
        let ui = ActivityUi::build(app.app(), None, Some(snapshot()), 10_000);
        let text = app.text();
        assert!(text.contains("Leader Activity"));
        assert!(text.contains("Running 1"));
        assert!(text.contains("Done 1"));
        assert!(text.contains("Failed 1"));
        assert!(text.contains("State"));
        assert!(text.contains("Task"));
        assert!(text.contains("Detail"));
        assert!(text.contains("Elapsed"));
        assert!(text.contains("Progress"));
        assert!(text.contains("Build"));
        assert!(text.contains("Build title"));
        assert!(text.contains("src/main.rs"));
        assert_eq!(ui.model_handle().borrow().selected_item().unwrap().name, "Build");
    }

    #[test]
    fn test_app_filters_navigates_and_toggles_follow() {
        let app = test_app(100, 24);
        let ui = ActivityUi::build(app.app(), None, Some(snapshot()), 10_000);
        app.press("2");
        assert_eq!(ui.model_handle().borrow().filter(), Filter::Running);
        assert!(app.text().contains("Build"));
        assert!(!app.text().contains("Tests"));

        app.press("3");
        assert_eq!(ui.model_handle().borrow().filter(), Filter::Done);
        assert!(app.text().contains("Tests"));
        assert!(!app.text().contains("Build"));

        app.press("f");
        assert!(!ui.model_handle().borrow().follow_newest());
        assert!(app.text().contains("f newest:off"));
        app.press("j");
        assert_eq!(ui.model_handle().borrow().selected_item().unwrap().name, "Lint");
        assert!(app.text().contains("Lint message"));

        app.press("1");
        assert_eq!(ui.model_handle().borrow().filter(), Filter::All);
        app.press("r");
        assert!(!app.is_quitting());
    }

    #[test]
    fn test_app_quit_keys_exit() {
        let app = test_app(80, 20);
        let _ui = ActivityUi::build(app.app(), None, Some(snapshot()), 10_000);
        app.press("escape");
        assert!(app.is_quitting());

        let app = test_app(80, 20);
        let _ui = ActivityUi::build(app.app(), None, Some(snapshot()), 10_000);
        app.press("q");
        assert!(app.is_quitting());
    }

    #[test]
    fn test_app_layout_survives_a_narrow_resize() {
        let app = test_app(110, 26);
        let _ui = ActivityUi::build(app.app(), None, Some(snapshot()), 10_000);
        app.resize(42, 12);
        let text = app.text();
        assert!(text.contains("Leader Activity"), "{text}");
        assert!(text.contains("Build"), "{text}");
    }

    #[test]
    fn interval_polls_atomic_replacements_off_the_ui_thread() {
        let app = test_app(100, 24);
        let path = std::env::temp_dir().join(format!(
            "leader-activity-ui-{}-{}.json",
            std::process::id(),
            std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
        ));
        let mut initial = snapshot();
        initial.events.clear();
        fs::write(&path, serde_json::to_vec(&initial).unwrap()).unwrap();
        let ui = ActivityUi::build(app.app(), Some(SnapshotPoller::new(path.clone())), Some(initial), 10_000);

        let mut updated = snapshot();
        updated.running.clear();
        updated.events.insert(0, item(4, "Package", "done"));
        let temporary = path.with_extension("tmp");
        fs::write(&temporary, serde_json::to_vec(&updated).unwrap()).unwrap();
        let _ = fs::remove_file(&path);
        fs::rename(temporary, &path).unwrap();

        let model = ui.model_handle();
        app.advance(REFRESH_INTERVAL);
        let received = app.wait_until(Duration::from_secs(3), || model.borrow().visible_items().iter().any(|item| item.name == "Package"));
        let _ = fs::remove_file(path);
        assert!(received, "the 500 ms interval did not deliver the new snapshot");
        assert!(app.text().contains("Package"));
    }

    #[test]
    fn snapshot_fixture_has_the_expected_shape() {
        let value = json!({
            "version": 1, "pid": 1, "cwd": "/tmp", "updated_at": 1,
            "running": [], "events": []
        });
        let parsed: Snapshot = serde_json::from_value(value).unwrap();
        assert_eq!(parsed.version, 1);
    }
}
