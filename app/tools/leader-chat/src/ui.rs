use crate::commands::{Action, Command, CommandWriter, WriteOutcome};
use crate::model::{Model, Overlay, Snapshot, transcript_markdown};
use crate::reader::{ReadOutcome, SnapshotPoller, unix_ms};
use opentui::prelude::*;
use opentui::widget::ScrollEdge;
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::{Duration, SystemTime};

const REFRESH_INTERVAL: Duration = Duration::from_millis(100);

#[derive(Clone)]
struct PendingSend {
    id: String,
    text: String,
}

#[derive(Clone)]
pub struct ChatUi {
    model: Rc<RefCell<Model>>,
    pulse: Rc<Cell<usize>>,
    transcript_source: Rc<RefCell<String>>,
    pending: Rc<RefCell<Option<PendingSend>>>,
    root: View,
    header: View,
    session_title: Text,
    activity: Text,
    metadata: Text,
    transcript_panel: View,
    transcript_scroll: ScrollBox,
    transcript: Markdown,
    status: Text,
    composer_panel: View,
    composer: Textarea,
    overlay: View,
    overlay_panel: View,
    overlay_title: Text,
    overlay_select: Select,
    overlay_empty: Text,
    footer: Text,
}

impl ChatUi {
    pub fn build(app: &App, poller: Option<SnapshotPoller>, initial: Option<Snapshot>, writer: CommandWriter, now_ms: u64) -> Self {
        writer.bind(app.proxy());
        let theme = app.theme();
        let model = Rc::new(RefCell::new(match initial {
            Some(snapshot) => Model::with_snapshot(snapshot, now_ms),
            None => Model::default(),
        }));
        let pulse = Rc::new(Cell::new(0));
        let transcript_source = Rc::new(RefCell::new(String::new()));
        let root = app.root().column();

        let header = View::new(app).row().justify(Justify::SpaceBetween).height(1).shrink(0.0);
        let brand = Text::new(app, "Leader Chat").fg(theme.accent).bold().wrap(WrapMode::None);
        let session_title = Text::new(app, "").bold().wrap(WrapMode::None);
        let activity = Text::new(app, "").wrap(WrapMode::None);
        header.add(&brand).add(&session_title).add(&activity);

        let metadata = Text::new(app, "").fg(theme.muted).wrap(WrapMode::None).height(1).shrink(0.0);

        let transcript_scroll =
            ScrollBox::new(app).sticky(true).sticky_start(ScrollEdge::Bottom).scrollbar_colors(theme.thumb, theme.track).grow(1.0);
        let transcript = Markdown::new(app).conceal(true);
        transcript_scroll.content_view().add(&transcript);
        let transcript_panel = View::new(app)
            .border(BorderStyle::Rounded)
            .border_color(theme.border)
            .title(" Transcript ")
            .title_color(theme.muted)
            .padding_x(1)
            .min_height(3)
            .grow(1.0)
            .child(&transcript_scroll);

        let status = Text::new(app, "").fg(theme.muted).wrap(WrapMode::None).height(1).shrink(0.0);
        let composer = Textarea::new(app)
            .placeholder("Write a message… (Enter adds a line)")
            .placeholder_color(theme.muted)
            .colors(theme.foreground, theme.input_bg)
            .focused_colors(theme.foreground, theme.input_focused_bg)
            .wrap(WrapMode::Word)
            .height(1);
        let composer_panel = View::new(app)
            .border(BorderStyle::Rounded)
            .border_color(theme.border)
            .title(" Message ")
            .title_color(theme.muted)
            .highlight_focus()
            .padding_x(1)
            .height(3)
            .shrink(0.0)
            .child(&composer);

        let overlay_panel = View::new(app)
            .column()
            .border(BorderStyle::Rounded)
            .border_color(theme.focus)
            .bg(theme.background)
            .padding_x(1)
            .width(Length::Percent(80.0))
            .max_width(78)
            .height(Length::Percent(70.0))
            .max_height(22);
        let overlay_title = Text::new(app, "").bold().fg(theme.accent).height(1).shrink(0.0);
        let overlay_select = Select::new(app)
            .show_description(true)
            .show_scroll_indicator(true)
            .wrap_selection(false)
            .colors(theme.foreground, theme.background)
            .focused_colors(theme.foreground, theme.background)
            .selected_colors(theme.highlight_fg, theme.highlight_bg)
            .description_colors(theme.muted, theme.foreground)
            .grow(1.0);
        let overlay_empty = Text::new(app, "").fg(theme.muted).wrap(WrapMode::Word).grow(1.0);
        let overlay_hint = Text::new(app, "j/k move · Enter select · Esc close").fg(theme.muted).height(1).shrink(0.0);
        overlay_panel.add(&overlay_title).add(&overlay_select).add(&overlay_empty).add(&overlay_hint);
        let overlay = View::new(app)
            .absolute()
            .position(Edge::All, 0)
            .justify(Justify::Center)
            .align_items(Align::Center)
            .z_index(20)
            .visible(false)
            .child(&overlay_panel);

        let footer = Text::new(app, "").fg(theme.muted).wrap(WrapMode::Word).height(2).shrink(0.0);

        root.add(&header).add(&metadata).add(&transcript_panel).add(&status).add(&composer_panel).add(&footer).add(&overlay);

        let ui = Self {
            model,
            pulse,
            transcript_source,
            pending: Rc::new(RefCell::new(None)),
            root,
            header,
            session_title,
            activity,
            metadata,
            transcript_panel,
            transcript_scroll,
            transcript,
            status,
            composer_panel,
            composer,
            overlay,
            overlay_panel,
            overlay_title,
            overlay_select,
            overlay_empty,
            footer,
        };
        ui.apply_layout(app);
        ui.refresh(app, now_ms);
        app.focus(&ui.composer);
        ui.install_handlers(app, poller, writer);
        ui
    }

    pub fn model_handle(&self) -> Rc<RefCell<Model>> {
        Rc::clone(&self.model)
    }

    pub fn composer_handle(&self) -> Textarea {
        self.composer.clone()
    }

    pub fn refresh_now(&self, app: &App, poller: &SnapshotPoller) {
        poller.poll(&app.proxy());
    }

    pub fn apply_outcome(&self, outcome: &ReadOutcome) {
        match &outcome.result {
            Ok(snapshot) => self.model.borrow_mut().apply_snapshot(snapshot.clone(), outcome.read_at),
            Err(error) => self.model.borrow_mut().apply_read_error(error, outcome.read_at),
        }
    }

    pub fn apply_write_outcome(&self, outcome: &WriteOutcome) {
        match &outcome.result {
            Ok(()) => self.model.borrow_mut().set_command_status(format!("command {} sent", outcome.id)),
            Err(error) => self.model.borrow_mut().set_command_error(error),
        }
    }

    pub fn refresh(&self, app: &App, now_ms: u64) {
        let theme = app.theme();
        let (title, activity, metadata, status, markdown, overlay, entries, has_error, ack) = {
            let model = self.model.borrow();
            (
                model.header_title(),
                activity_content(model.running(), model.snapshot().map_or(0, |snapshot| snapshot.messages.len()), theme),
                model.metadata(),
                model.status_text(now_ms),
                transcript_markdown(model.snapshot(), self.pulse.get()),
                model.overlay(),
                model.overlay_entries(),
                model.has_error(),
                model.snapshot().and_then(|snapshot| snapshot.ack.clone()),
            )
        };

        self.session_title.set_text(title);
        self.activity.set_text(activity);
        self.metadata.set_text(metadata);
        self.status.set_text(status);
        self.status.fg(if has_error { theme.warning } else { theme.muted });
        self.footer.set_text(footer_content(theme));

        if let Some(ack) = ack {
            let matches = self.pending.borrow().as_ref().is_some_and(|pending| pending.id == ack.id);
            if matches {
                let pending = self.pending.borrow_mut().take();
                if let Some(pending) = pending
                    && self.composer.text() == pending.text
                {
                    if ack.ok {
                        self.composer.set_text("");
                    } else {
                        self.composer.set_text(&pending.text);
                    }
                }
            }
        }

        if *self.transcript_source.borrow() != markdown {
            self.transcript.set_markdown(&markdown);
            self.transcript_scroll.scroll_to_bottom();
            *self.transcript_source.borrow_mut() = markdown;
        }

        if let Some(overlay) = overlay {
            self.overlay_title.set_text(format!("Select {}", overlay.title().to_ascii_lowercase()));
            self.overlay_panel.title(format!(" {} ", overlay.title()));
            let options = entries
                .iter()
                .map(|entry| {
                    let label = if entry.current { format!("● {}", entry.label) } else { entry.label.clone() };
                    SelectOption::new(label, entry.detail.clone())
                })
                .collect::<Vec<_>>();
            self.overlay_select.options(options);
            self.overlay_select.visible(!entries.is_empty());
            self.overlay_empty.set_text(overlay.empty_text());
            self.overlay_empty.visible(entries.is_empty());
            self.overlay.visible(true);
        } else {
            self.overlay.visible(false);
        }

        self.resize_composer(app);
    }

    fn submit(&self, app: &App, writer: &CommandWriter, command: Command, clear_draft: bool) {
        let label = match command.action {
            Action::Send => "send",
            Action::Stop => "stop",
            Action::New => "new session",
            Action::History => "history",
            Action::SelectSession => "select session",
            Action::SetModel => "set model",
            Action::SetProfile => "set profile",
        };
        let action = command.action;
        let draft = if action == Action::Send { command.text.clone().unwrap_or_default() } else { String::new() };
        match writer.submit(command) {
            Ok(id) => {
                if action == Action::Send {
                    *self.pending.borrow_mut() = Some(PendingSend { id: id.clone(), text: draft });
                } else if clear_draft {
                    self.composer.set_text("");
                }
                self.model.borrow_mut().set_command_status(format!("{label} queued ({id})"));
            }
            Err(error) => self.model.borrow_mut().set_command_error(error),
        }
        self.refresh(app, unix_ms(SystemTime::now()));
    }

    fn install_handlers(&self, app: &App, poller: Option<SnapshotPoller>, writer: CommandWriter) {
        let messaged = self.clone();
        app.on_message(move |cx, outcome: &ReadOutcome| {
            messaged.apply_outcome(outcome);
            messaged.refresh(cx, outcome.read_at);
        });

        let written = self.clone();
        app.on_message(move |cx, outcome: &WriteOutcome| {
            written.apply_write_outcome(outcome);
            written.refresh(cx, unix_ms(SystemTime::now()));
        });

        let resized = self.clone();
        app.on_resize(move |cx, _width, _height| {
            resized.apply_layout(cx);
            resized.refresh(cx, unix_ms(SystemTime::now()));
        });

        let changed = self.clone();
        self.composer.on_change(move |cx, _text| {
            changed.resize_composer(cx);
        });

        let selected_ui = self.clone();
        let selected_writer = writer.clone();
        self.overlay_select.on_select(move |cx, index, _option| {
            let command = selected_ui.model.borrow().command_for_overlay(index);
            if let Some(command) = command {
                selected_ui.model.borrow_mut().close_overlay();
                selected_ui.submit(cx, &selected_writer, command, false);
                cx.focus(&selected_ui.composer);
            }
        });

        let captured = self.clone();
        let captured_writer = writer.clone();
        app.on_key_capture(move |cx, key| {
            if key.matches("escape") {
                if captured.model.borrow().overlay().is_some() {
                    captured.model.borrow_mut().close_overlay();
                    captured.refresh(cx, unix_ms(SystemTime::now()));
                    cx.focus(&captured.composer);
                    cx.stop_propagation();
                }
                return;
            }
            if key.matches("ctrl+s") {
                if captured.model.borrow().overlay().is_some() {
                    captured.model.borrow_mut().set_command_status("close the picker before sending");
                } else {
                    let text = captured.composer.text();
                    if text.trim().is_empty() {
                        captured.model.borrow_mut().set_command_status("write a message first");
                    } else {
                        captured.submit(cx, &captured_writer, Command::send(text), true);
                    }
                }
                cx.stop_propagation();
                captured.refresh(cx, unix_ms(SystemTime::now()));
                return;
            }
            if key.matches("ctrl+g") {
                if captured.model.borrow().overlay().is_some() {
                    captured.model.borrow_mut().close_overlay();
                    captured.refresh(cx, unix_ms(SystemTime::now()));
                    cx.focus(&captured.composer);
                    cx.stop_propagation();
                }
                return;
            }
            if key.matches("ctrl+q") {
                cx.quit();
                cx.stop_propagation();
                return;
            }
            if key.matches("ctrl+c") {
                if captured.model.borrow().running() {
                    captured.submit(cx, &captured_writer, Command::stop(), false);
                } else {
                    captured.model.borrow_mut().set_command_status("nothing is streaming");
                }
                cx.stop_propagation();
                captured.refresh(cx, unix_ms(SystemTime::now()));
                return;
            }
            if key.matches("ctrl+n") {
                captured.model.borrow_mut().close_overlay();
                captured.submit(cx, &captured_writer, Command::new_session(), true);
                cx.focus(&captured.composer);
                cx.stop_propagation();
                return;
            }
            if key.matches("ctrl+h") {
                let opening = captured.model.borrow().overlay() != Some(Overlay::History);
                if opening {
                    captured.model.borrow_mut().open_overlay(Overlay::History);
                    captured.submit(cx, &captured_writer, Command::history(), false);
                    captured.focus_overlay(cx);
                } else {
                    captured.model.borrow_mut().close_overlay();
                    captured.refresh(cx, unix_ms(SystemTime::now()));
                    cx.focus(&captured.composer);
                }
                cx.stop_propagation();
                return;
            }
            if key.matches("ctrl+m") {
                captured.model.borrow_mut().open_overlay(Overlay::Models);
                cx.stop_propagation();
                captured.refresh(cx, unix_ms(SystemTime::now()));
                captured.focus_overlay(cx);
                return;
            }
            if key.matches("ctrl+p") {
                captured.model.borrow_mut().open_overlay(Overlay::Profiles);
                cx.stop_propagation();
                captured.refresh(cx, unix_ms(SystemTime::now()));
                captured.focus_overlay(cx);
            }
        });

        let proxy = app.proxy();
        let timer_ui = self.clone();
        app.set_interval(REFRESH_INTERVAL, move |cx| {
            if let Some(poller) = &poller {
                poller.poll(&proxy);
            }
            timer_ui.pulse.set(timer_ui.pulse.get().wrapping_add(1));
            timer_ui.refresh(cx, unix_ms(SystemTime::now()));
        });
    }

    fn focus_overlay(&self, app: &App) {
        let model = self.model.borrow();
        if model.overlay().is_some() && !model.overlay_entries().is_empty() {
            app.focus(&self.overlay_select);
        } else {
            app.focus(&self.composer);
        }
    }

    fn resize_composer(&self, app: &App) {
        let (_width, height) = app.size();
        let lines = self.composer.text().lines().count().max(self.composer.cursor().0 as usize + 1).clamp(1, 5) as u16;
        let lines = if height < 12 { 1 } else { lines };
        self.composer.height(lines);
        self.composer_panel.height(lines + 2);
    }

    fn apply_layout(&self, app: &App) {
        let (width, height) = app.size();
        let roomy = width >= 60 && height >= 16;
        self.root.padding(if roomy { 1 } else { 0 });
        self.root.gap(if height >= 20 { 1 } else { 0 });
        self.header.visible(height >= 2);
        self.session_title.visible(width >= 60);
        self.activity.visible(width >= 36);
        self.metadata.visible(height >= 5);
        self.status.visible(height >= 7);
        self.footer.visible(height >= 4);
        self.footer.height(if width >= 112 {
            1
        } else if width >= 64 {
            2
        } else {
            3
        });
        self.transcript_panel.padding_x(if width >= 50 { 1 } else { 0 });
        self.overlay_panel.width(width.saturating_sub(4).clamp(12, 78));
        self.overlay_panel.height(height.saturating_sub(6).clamp(5, 22));
    }
}

fn activity_content(running: bool, messages: usize, theme: Theme) -> Content {
    let mut spans = Vec::new();
    if running {
        spans.push("● streaming".fg(theme.success).bold());
    } else {
        spans.push("○ idle".fg(theme.muted));
    }
    spans.push(format!("  {messages} messages").fg(theme.muted));
    spans.into()
}

fn footer_content(theme: Theme) -> Content {
    vec![
        "Ctrl-S".fg(theme.accent).bold(),
        " send  ".into(),
        "Ctrl-C".fg(theme.accent).bold(),
        " stop  ".into(),
        "Ctrl-N".fg(theme.accent).bold(),
        " new  ".into(),
        "Ctrl-H".fg(theme.accent).bold(),
        " history  ".into(),
        "Ctrl-Q".fg(theme.accent).bold(),
        " exit    ".into(),
        "Ctrl-M".fg(theme.muted).bold(),
        " model  ".into(),
        "Ctrl-P".fg(theme.muted).bold(),
        " profile".into(),
    ]
    .into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{HistoryEntry, Message, ModelOption, Profile, Session};
    use opentui::testing::TestApp;
    use serde_json::json;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "leader-chat-ui-test-{}-{}",
                std::process::id(),
                NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn state_path(&self) -> PathBuf {
            self.0.join("state.json")
        }

        fn command_path(&self) -> PathBuf {
            self.0.join("commands.json")
        }

        fn write_state(&self, snapshot: &Snapshot) {
            let temporary = self.0.join("state.json.tmp");
            fs::write(&temporary, serde_json::to_vec(snapshot).unwrap()).unwrap();
            let _ = fs::remove_file(self.state_path());
            fs::rename(temporary, self.state_path()).unwrap();
        }

        fn command(&self) -> Command {
            let command: Command = serde_json::from_slice(&fs::read(self.command_path()).unwrap()).unwrap();
            // Leader's consumer removes the slot after handling it; mirror that here so the writer can publish the next command.
            fs::remove_file(self.command_path()).unwrap();
            command
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn snapshot() -> Snapshot {
        Snapshot {
            version: 1,
            pid: 42,
            cwd: "/project".to_owned(),
            updated_at: 10_000,
            session: Session {
                id: "session-1".to_owned(),
                title: "Refactor the parser".to_owned(),
                model: "model-a".to_owned(),
                profile: "profile-a".to_owned(),
                effort: Some("high".to_owned()),
                running: true,
            },
            messages: vec![
                Message {
                    id: "message-1".to_owned(),
                    role: "user".to_owned(),
                    text: "Please **check** this.".to_owned(),
                    thinking: None,
                    at: 8_000,
                    state: Some("done".to_owned()),
                    usage: None,
                    error: None,
                },
                Message {
                    id: "message-2".to_owned(),
                    role: "assistant".to_owned(),
                    text: "Hello **world**\n\n```rust\nfn main() {}\n```".to_owned(),
                    thinking: Some("Considering the parser.".to_owned()),
                    at: 9_000,
                    state: Some("streaming".to_owned()),
                    usage: Some(json!({"input": 12, "output": 4})),
                    error: None,
                },
            ],
            profiles: vec![Profile { id: "profile-a".to_owned(), label: "Careful".to_owned() }],
            models: vec![ModelOption { id: "model-a".to_owned(), label: "Model A".to_owned() }],
            history: vec![HistoryEntry {
                id: "session-0".to_owned(),
                title: "Older chat".to_owned(),
                at: 7_000,
                model: "model-a".to_owned(),
            }],
            ack: None,
        }
    }

    fn test_app(width: u16, height: u16) -> TestApp {
        TestApp::with_options(width, height, AppOptions::default().with_theme(Theme::dark()))
    }

    fn setup() -> (TestApp, TempDir, ChatUi, CommandWriter) {
        let app = test_app(110, 36);
        let dir = TempDir::new();
        let writer = CommandWriter::new(dir.command_path());
        let ui = ChatUi::build(app.app(), None, Some(snapshot()), writer.clone(), 10_000);
        (app, dir, ui, writer)
    }

    fn wait_written(app: &TestApp, writer: &CommandWriter) {
        assert!(app.wait_until(Duration::from_secs(3), || writer.pending() == 0), "command writer did not finish");
    }

    #[test]
    fn test_app_renders_transcript_markdown_streaming_and_footer() {
        let (app, _dir, ui, _writer) = setup();
        let _ = app.text();
        ui.transcript_scroll.perform(ScrollAction::Top);
        let text = app.text();
        assert!(text.contains("Leader Chat"), "{text}");
        assert!(text.contains("Refactor the parser"), "{text}");
        assert!(text.contains("● streaming"), "{text}");
        assert!(text.contains("user"), "{text}");
        assert!(text.contains("assistant"), "{text}");
        assert!(text.contains("Please check this."), "{text}");
        assert!(text.contains("Hello world"), "{text}");
        assert!(text.contains("Considering the parser."), "{text}");
        assert!(text.contains("fn main() {}"), "{text}");
        assert!(text.contains("Ctrl-S send"), "{text}");
        assert!(text.contains("Ctrl-C stop"), "{text}");
        assert!(text.contains("Ctrl-N new"), "{text}");
        assert!(text.contains("Ctrl-H history"), "{text}");
        assert!(text.contains("Ctrl-Q exit"), "{text}");
        assert!(ui.model_handle().borrow().running());
    }

    #[test]
    fn test_app_send_keeps_the_draft_until_leader_accepts_it() {
        let (app, dir, ui, writer) = setup();
        app.type_text("hello");
        app.press("ctrl+s");
        assert_eq!(ui.composer_handle().text(), "hello", "the draft stays while the command is in flight");
        wait_written(&app, &writer);
        let command = dir.command();
        assert_eq!(command.action, Action::Send);
        let mut acked = snapshot();
        acked.ack = Some(crate::model::CommandAck { id: command.id, ok: true, error: None });
        ui.model_handle().borrow_mut().apply_snapshot(acked, 11_000);
        ui.refresh(&app, 11_000);
        assert_eq!(ui.composer_handle().text(), "");
    }

    #[test]
    fn test_app_rejected_send_restores_the_draft() {
        let (app, dir, ui, writer) = setup();
        app.type_text("keep me");
        app.press("ctrl+s");
        wait_written(&app, &writer);
        let command = dir.command();
        let mut rejected = snapshot();
        rejected.ack = Some(crate::model::CommandAck { id: command.id, ok: false, error: Some("no backend".to_owned()) });
        ui.model_handle().borrow_mut().apply_snapshot(rejected, 11_000);
        ui.refresh(&app, 11_000);
        assert_eq!(ui.composer_handle().text(), "keep me");
        assert!(app.text().contains("no backend"));
    }

    #[test]
    fn an_old_ack_does_not_consume_a_new_pending_send() {
        let (app, _dir, ui, _writer) = setup();
        app.type_text("new draft");
        let mut old = snapshot();
        old.ack = Some(crate::model::CommandAck { id: "old-command".to_owned(), ok: true, error: None });
        ui.model_handle().borrow_mut().apply_snapshot(old, 11_000);
        ui.refresh(&app, 11_000);
        assert_eq!(ui.composer_handle().text(), "new draft");
    }

    #[test]
    fn test_app_stop_writes_stop_without_quitting() {
        let (app, dir, _ui, writer) = setup();
        app.press("ctrl+c");
        wait_written(&app, &writer);
        let command = dir.command();
        assert_eq!(command.action, Action::Stop);
        assert!(command.text.is_none());
        assert!(!app.is_quitting());
    }

    #[test]
    fn test_app_new_session_writes_new_and_discards_the_draft() {
        let (app, dir, ui, writer) = setup();
        app.type_text("unsent draft");
        app.press("ctrl+n");
        assert_eq!(ui.composer_handle().text(), "");
        wait_written(&app, &writer);
        assert_eq!(dir.command().action, Action::New);
        assert!(!app.is_quitting());
    }

    #[test]
    fn test_app_history_and_pickers_write_selection_commands() {
        let (app, dir, ui, writer) = setup();
        app.press("ctrl+h");
        wait_written(&app, &writer);
        assert_eq!(dir.command().action, Action::History);
        assert!(app.text().contains("Older chat"));
        assert_eq!(ui.model_handle().borrow().overlay(), Some(Overlay::History));

        app.press("enter");
        wait_written(&app, &writer);
        let command = dir.command();
        assert_eq!(command.action, Action::SelectSession);
        assert_eq!(command.session_id.as_deref(), Some("session-0"));
        assert_eq!(ui.model_handle().borrow().overlay(), None);

        app.press("ctrl+m");
        assert!(app.text().contains("Model A"));
        app.press("enter");
        wait_written(&app, &writer);
        let command = dir.command();
        assert_eq!(command.action, Action::SetModel);
        assert_eq!(command.value.as_deref(), Some("model-a"));

        app.press("ctrl+p");
        assert!(app.text().contains("Careful"));
        app.press("enter");
        wait_written(&app, &writer);
        let command = dir.command();
        assert_eq!(command.action, Action::SetProfile);
        assert_eq!(command.value.as_deref(), Some("profile-a"));
    }

    #[test]
    fn test_app_ctrl_g_closes_a_picker() {
        let app = test_app(80, 20);
        let writer = CommandWriter::new(std::env::temp_dir().join("unused-leader-chat-commands.json"));
        let ui = ChatUi::build(app.app(), None, Some(snapshot()), writer, 10_000);
        app.press("ctrl+h");
        assert_eq!(ui.model_handle().borrow().overlay(), Some(Overlay::History));
        app.press("ctrl+g");
        assert_eq!(ui.model_handle().borrow().overlay(), None);
        assert!(!app.is_quitting());
    }

    #[test]
    fn test_app_ctrl_q_exits() {
        let app = test_app(80, 20);
        let writer = CommandWriter::new(std::env::temp_dir().join("unused-leader-chat-commands.json"));
        let _ui = ChatUi::build(app.app(), None, Some(snapshot()), writer, 10_000);
        app.press("ctrl+q");
        assert!(app.is_quitting());
    }

    #[test]
    fn test_app_escape_only_closes_a_picker() {
        let app = test_app(80, 20);
        let writer = CommandWriter::new(std::env::temp_dir().join("unused-leader-chat-commands.json"));
        let ui = ChatUi::build(app.app(), None, Some(snapshot()), writer, 10_000);
        app.press("escape");
        assert!(!app.is_quitting());
        app.press("ctrl+h");
        assert_eq!(ui.model_handle().borrow().overlay(), Some(Overlay::History));
        app.press("escape");
        assert_eq!(ui.model_handle().borrow().overlay(), None);
        assert!(!app.is_quitting());
    }

    #[test]
    fn interval_polls_atomic_snapshot_replacements_off_the_ui_thread() {
        let app = test_app(100, 26);
        let dir = TempDir::new();
        let mut initial = snapshot();
        initial.messages.clear();
        dir.write_state(&initial);
        let writer = CommandWriter::new(dir.command_path());
        let ui = ChatUi::build(app.app(), Some(SnapshotPoller::new(dir.state_path())), Some(initial), writer, 10_000);

        let mut updated = snapshot();
        updated.messages[1].text = "A freshly streamed **answer**.".to_owned();
        dir.write_state(&updated);
        app.advance(REFRESH_INTERVAL);
        let received = app.wait_until(Duration::from_secs(3), || {
            ui.model_handle()
                .borrow()
                .snapshot()
                .is_some_and(|snapshot| snapshot.messages.get(1).is_some_and(|message| message.text.contains("freshly streamed")))
        });
        assert!(received, "the 100 ms interval did not deliver the new snapshot");
        assert!(app.text().contains("A freshly streamed answer."));
    }

    #[test]
    fn test_app_polling_does_not_steal_focus_from_the_transcript() {
        let (app, _dir, ui, _writer) = setup();
        app.press("tab");
        assert_eq!(app.focused().map(|widget| widget.id()), Some(ui.transcript_scroll.id()));
        app.advance(REFRESH_INTERVAL);
        assert_eq!(app.focused().map(|widget| widget.id()), Some(ui.transcript_scroll.id()));
    }

    #[test]
    fn test_app_survives_a_narrow_resize() {
        let (app, _dir, _ui, _writer) = setup();
        app.resize(42, 12);
        let text = app.text();
        assert!(text.contains("Leader Chat"), "{text}");
        assert!(text.contains("Ctrl-S"), "{text}");
    }
}
