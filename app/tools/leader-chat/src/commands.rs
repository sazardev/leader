use opentui::prelude::AppProxy;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const COMMAND_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    Send,
    Stop,
    New,
    History,
    SelectSession,
    SetModel,
    SetProfile,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Command {
    pub version: u32,
    pub id: String,
    pub action: Action,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
}

impl Command {
    fn new(action: Action) -> Self {
        Self { version: COMMAND_VERSION, id: String::new(), action, text: None, session_id: None, value: None }
    }

    pub fn send(text: impl Into<String>) -> Self {
        let mut command = Self::new(Action::Send);
        command.text = Some(text.into());
        command
    }

    pub fn stop() -> Self {
        Self::new(Action::Stop)
    }

    pub fn new_session() -> Self {
        Self::new(Action::New)
    }

    pub fn history() -> Self {
        Self::new(Action::History)
    }

    pub fn select_session(session_id: impl Into<String>) -> Self {
        let mut command = Self::new(Action::SelectSession);
        command.session_id = Some(session_id.into());
        command
    }

    pub fn set_model(value: impl Into<String>) -> Self {
        let mut command = Self::new(Action::SetModel);
        command.value = Some(value.into());
        command
    }

    pub fn set_profile(value: impl Into<String>) -> Self {
        let mut command = Self::new(Action::SetProfile);
        command.value = Some(value.into());
        command
    }
}

#[derive(Debug)]
pub struct WriteOutcome {
    pub id: String,
    pub result: Result<(), String>,
}

#[derive(Debug, Clone)]
pub struct CommandWriter {
    inner: Arc<WriterInner>,
}

#[derive(Debug)]
struct WriterInner {
    path: Arc<PathBuf>,
    queue: Mutex<VecDeque<Command>>,
    outstanding: AtomicUsize,
    busy: AtomicBool,
    sequence: AtomicU64,
    app: Mutex<Option<AppProxy>>,
}

impl CommandWriter {
    pub fn new(path: PathBuf) -> Self {
        Self {
            inner: Arc::new(WriterInner {
                path: Arc::new(path),
                queue: Mutex::new(VecDeque::new()),
                outstanding: AtomicUsize::new(0),
                busy: AtomicBool::new(false),
                sequence: AtomicU64::new(0),
                app: Mutex::new(None),
            }),
        }
    }

    pub fn bind(&self, app: AppProxy) {
        *self.inner.app.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(app);
    }

    /// Queues one command and starts a bounded background writer. The returned
    /// id is also sent back in [`WriteOutcome`] once the atomic rename finishes.
    pub fn submit(&self, mut command: Command) -> Result<String, String> {
        let sequence = self.inner.sequence.fetch_add(1, Ordering::Relaxed);
        let id = format!(
            "{}-{}-{sequence}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |duration| duration.as_millis())
        );
        command.id = id.clone();
        self.inner.queue.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).push_back(command);
        self.inner.outstanding.fetch_add(1, Ordering::AcqRel);
        if let Err(error) = self.pump() {
            self.remove(&id);
            return Err(error);
        }
        Ok(id)
    }

    pub fn pending(&self) -> usize {
        self.inner.outstanding.load(Ordering::Acquire)
    }

    pub fn flush(&self, timeout: Duration) -> bool {
        let deadline = std::time::Instant::now().checked_add(timeout);
        while self.pending() > 0 {
            if deadline.is_some_and(|deadline| std::time::Instant::now() >= deadline) {
                return false;
            }
            thread::sleep(Duration::from_millis(1));
        }
        true
    }

    fn remove(&self, id: &str) {
        self.inner.queue.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).retain(|command| command.id != id);
        self.inner.outstanding.fetch_sub(1, Ordering::AcqRel);
    }

    fn pump(&self) -> Result<(), String> {
        if self.inner.busy.compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire).is_err() {
            return Ok(());
        }
        let writer = self.clone();
        let worker = thread::Builder::new().name("leader-chat-commands".to_owned()).spawn(move || writer.run());
        if worker.is_err() {
            self.inner.busy.store(false, Ordering::Release);
            return Err("cannot start the command writer thread".to_owned());
        }
        Ok(())
    }

    fn run(&self) {
        loop {
            let command = self.inner.queue.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).pop_front();
            let Some(command) = command else {
                self.inner.busy.store(false, Ordering::Release);
                let queued = !self.inner.queue.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).is_empty();
                if !queued || self.inner.busy.compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire).is_err() {
                    return;
                }
                continue;
            };

            let id = command.id.clone();
            let result = write_atomic(&self.inner.path, &command);
            self.inner.outstanding.fetch_sub(1, Ordering::AcqRel);
            if let Some(app) = self.inner.app.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).as_ref().cloned() {
                let _ = app.send(WriteOutcome { id, result: result.clone() });
            }

            // One shared command slot has no ACK. The consumer removes the file
            // after handling it; wait for that before publishing another queued
            // command so a fast second action cannot overwrite an unread first.
            if result.is_ok() {
                while self.inner.path.exists() {
                    thread::sleep(Duration::from_millis(10));
                }
            }
        }
    }
}

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

pub(crate) fn write_atomic(path: &Path, command: &Command) -> Result<(), String> {
    let bytes = serde_json::to_vec(command).map_err(|error| format!("cannot encode command: {error}"))?;
    let parent = path.parent().filter(|parent| !parent.as_os_str().is_empty()).unwrap_or_else(|| Path::new("."));
    let name = path.file_name().ok_or_else(|| format!("invalid command path: {}", path.display()))?;
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |duration| duration.as_nanos());
    let temporary = parent.join(format!(
        ".{}.{}.{stamp}.{}.tmp",
        name.to_string_lossy(),
        std::process::id(),
        NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
    ));

    let mut created = false;
    let result = (|| {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
            .map_err(|error| format!("cannot create {}: {error}", temporary.display()))?;
        created = true;
        file.write_all(&bytes).and_then(|()| file.sync_all()).map_err(|error| format!("cannot write {}: {error}", temporary.display()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            file.set_permissions(fs::Permissions::from_mode(0o600))
                .map_err(|error| format!("cannot secure {}: {error}", temporary.display()))?;
        }
        drop(file);
        fs::rename(&temporary, path).map_err(|error| format!("cannot replace {}: {error}", path.display()))?;
        Ok(())
    })();
    if result.is_err() && created {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::fs;

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "leader-chat-command-test-{}-{}",
                std::process::id(),
                NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn commands_serialize_with_flat_optional_fields() {
        let value = serde_json::to_value(Command::send("hello\nworld")).unwrap();
        assert_eq!(
            value,
            json!({
                "version": 1,
                "id": "",
                "action": "send",
                "text": "hello\nworld"
            })
        );
        let value = serde_json::to_value(Command::select_session("session-2")).unwrap();
        assert_eq!(value["action"], "select_session");
        assert_eq!(value["session_id"], "session-2");
        assert!(value.get("text").is_none());
        assert!(value.get("value").is_none());
    }

    #[test]
    fn every_action_uses_the_protocol_spelling() {
        let cases = [
            (Command::send("x"), "send"),
            (Command::stop(), "stop"),
            (Command::new_session(), "new"),
            (Command::history(), "history"),
            (Command::select_session("s"), "select_session"),
            (Command::set_model("m"), "set_model"),
            (Command::set_profile("p"), "set_profile"),
        ];
        for (command, expected) in cases {
            assert_eq!(serde_json::to_value(command).unwrap()["action"], expected);
        }
    }

    #[test]
    fn atomic_writer_replaces_an_existing_command_with_valid_json() {
        let dir = TempDir::new();
        let path = dir.0.join("commands.json");
        fs::write(&path, b"old").unwrap();
        let mut command = Command::stop();
        command.id = "test-command".to_owned();
        write_atomic(&path, &command).unwrap();
        let parsed: Command = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(parsed, command);
        assert_eq!(fs::read_dir(&dir.0).unwrap().count(), 1);
    }

    #[test]
    fn writer_flushes_a_queued_command_before_returning() {
        let dir = TempDir::new();
        let path = dir.0.join("commands.json");
        let writer = CommandWriter::new(path.clone());
        writer.submit(Command::send("flush me")).unwrap();
        assert!(writer.flush(Duration::from_secs(2)));
        let command: Command = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(command.action, Action::Send);
        assert_eq!(command.text.as_deref(), Some("flush me"));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn writer_waits_for_the_consumer_before_replacing_the_slot() {
        let dir = TempDir::new();
        let path = dir.0.join("commands.json");
        let writer = CommandWriter::new(path.clone());
        writer.submit(Command::send("first")).unwrap();
        let deadline = std::time::Instant::now() + Duration::from_secs(2);
        while !path.exists() && std::time::Instant::now() < deadline {
            thread::sleep(Duration::from_millis(5));
        }
        let first: Command = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(first.text.as_deref(), Some("first"));

        writer.submit(Command::send("second")).unwrap();
        thread::sleep(Duration::from_millis(50));
        let still_first: Command = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(still_first.text.as_deref(), Some("first"), "an unread command was overwritten");

        fs::remove_file(&path).unwrap();
        assert!(writer.flush(Duration::from_secs(2)));
        let second: Command = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(second.text.as_deref(), Some("second"));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn atomic_writer_reports_a_missing_parent_without_leaving_a_temp_file() {
        let dir = TempDir::new();
        let path = dir.0.join("missing").join("commands.json");
        assert!(write_atomic(&path, &Command::history()).unwrap_err().contains("cannot create"));
        assert_eq!(fs::read_dir(&dir.0).unwrap().count(), 0);
    }
}
