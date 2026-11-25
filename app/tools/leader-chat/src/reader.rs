use crate::model::{SNAPSHOT_VERSION, Snapshot};
use opentui::prelude::AppProxy;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

pub const MAX_SNAPSHOT_BYTES: u64 = 16 * 1024 * 1024;

pub fn unix_ms(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH).map_or(0, |duration| duration.as_millis().min(u64::MAX as u128) as u64)
}

pub fn read_snapshot(path: &Path) -> Result<Snapshot, String> {
    let file = File::open(path).map_err(|error| format!("cannot open {}: {error}", path.display()))?;
    let size = file.metadata().map_err(|error| format!("cannot stat {}: {error}", path.display()))?.len();
    if size > MAX_SNAPSHOT_BYTES {
        return Err(format!("snapshot is too large ({size} bytes; limit is {MAX_SNAPSHOT_BYTES})"));
    }

    let mut bytes = Vec::with_capacity(size.min(64 * 1024) as usize);
    file.take(MAX_SNAPSHOT_BYTES + 1).read_to_end(&mut bytes).map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    if bytes.len() as u64 > MAX_SNAPSHOT_BYTES {
        return Err(format!("snapshot exceeds {MAX_SNAPSHOT_BYTES} bytes"));
    }

    let snapshot: Snapshot = serde_json::from_slice(&bytes).map_err(|error| format!("invalid JSON in {}: {error}", path.display()))?;
    if snapshot.version != SNAPSHOT_VERSION {
        return Err(format!("unsupported snapshot version {} (expected {SNAPSHOT_VERSION})", snapshot.version));
    }
    Ok(snapshot)
}

#[derive(Debug)]
pub struct ReadOutcome {
    pub result: Result<Snapshot, String>,
    pub read_at: u64,
}

#[derive(Debug, Clone)]
pub struct SnapshotPoller {
    path: Arc<PathBuf>,
    in_flight: Arc<AtomicBool>,
}

impl SnapshotPoller {
    pub fn new(path: PathBuf) -> Self {
        Self { path: Arc::new(path), in_flight: Arc::new(AtomicBool::new(false)) }
    }

    /// Keep file I/O off OpenTUI's UI thread. A 100 ms timer coalesces reads
    /// while one bounded worker is in flight; failures are retried next tick.
    pub fn poll(&self, app: &AppProxy) {
        if self.in_flight.compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire).is_err() {
            return;
        }
        let path = Arc::clone(&self.path);
        let in_flight = Arc::clone(&self.in_flight);
        let proxy = app.clone();
        let worker = thread::Builder::new().name("leader-chat-snapshot".to_owned()).spawn(move || {
            let result = read_snapshot(&path);
            let outcome = ReadOutcome { result, read_at: unix_ms(SystemTime::now()) };
            let _ = proxy.send(outcome);
            in_flight.store(false, Ordering::Release);
        });
        if worker.is_err() {
            self.in_flight.store(false, Ordering::Release);
            let _ = app.send(ReadOutcome {
                result: Err("cannot start the snapshot reader thread".to_owned()),
                read_at: unix_ms(SystemTime::now()),
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};
    use std::fs;
    use std::sync::atomic::AtomicU64;

    static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "leader-chat-reader-test-{}-{}",
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

    fn write_atomic(dir: &TempDir, value: &Value) -> PathBuf {
        let path = dir.0.join("state.json");
        let temporary = dir.0.join("state.json.tmp");
        fs::write(&temporary, serde_json::to_vec(value).unwrap()).unwrap();
        let _ = fs::remove_file(&path);
        fs::rename(temporary, &path).unwrap();
        path
    }

    fn valid_snapshot() -> Value {
        json!({
            "version": 1,
            "pid": 7,
            "cwd": "/project",
            "updated_at": 1000,
            "session": {
                "id": "session-1",
                "title": "Chat",
                "model": "model-a",
                "profile": "profile-a",
                "running": false
            },
            "messages": [],
            "profiles": [],
            "models": [],
            "history": []
        })
    }

    #[test]
    fn reads_an_atomically_replaced_snapshot() {
        let dir = TempDir::new();
        let path = write_atomic(&dir, &valid_snapshot());
        assert_eq!(read_snapshot(&path).unwrap().session.id, "session-1");

        let mut changed = valid_snapshot();
        changed["session"]["id"] = json!("session-2");
        write_atomic(&dir, &changed);
        assert_eq!(read_snapshot(&path).unwrap().session.id, "session-2");
    }

    #[test]
    fn reports_missing_malformed_and_unsupported_snapshots() {
        let dir = TempDir::new();
        let missing = dir.0.join("missing.json");
        assert!(read_snapshot(&missing).unwrap_err().contains("cannot open"));

        let malformed = dir.0.join("malformed.json");
        fs::write(&malformed, b"{\"version\":").unwrap();
        assert!(read_snapshot(&malformed).unwrap_err().contains("invalid JSON"));

        let mut unsupported = valid_snapshot();
        unsupported["version"] = json!(2);
        let path = write_atomic(&dir, &unsupported);
        assert!(read_snapshot(&path).unwrap_err().contains("version 2"));
    }

    #[test]
    fn refuses_an_oversized_snapshot_without_reading_it_all() {
        let dir = TempDir::new();
        let path = dir.0.join("large.json");
        let file = File::create(&path).unwrap();
        file.set_len(MAX_SNAPSHOT_BYTES + 1).unwrap();
        assert!(read_snapshot(&path).unwrap_err().contains("too large"));
    }

    #[test]
    fn converts_epoch_milliseconds_without_panicking_before_the_epoch() {
        assert_eq!(unix_ms(UNIX_EPOCH - std::time::Duration::from_secs(1)), 0);
        assert_eq!(unix_ms(UNIX_EPOCH + std::time::Duration::from_millis(123)), 123);
    }
}
