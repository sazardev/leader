//! Opening files in a window that is already running: `leader --reuse file` hands its folder and paths to the window
//! that owns the socket and exits before building a window or starting Neovim, so it is instant. Opt-in (the flag or
//! `LEADER_REUSE=1`): a plain `leader` always opens its own window.
//!
//! The socket is private to the user (`$XDG_RUNTIME_DIR`, else the state folder). A request is the folder and the
//! arguments separated by NUL bytes, then the end of the stream; the window answers `ok`. A socket nobody listens on
//! (a window that crashed) is replaced by the next window.
use std::ffi::OsString;
use std::io::{Read, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::time::Duration;

/// What a later `leader --reuse …` asks of this window.
#[derive(Debug, PartialEq, Eq)]
pub struct Request {
    /// Where it was run: relative paths are relative to this.
    pub cwd: PathBuf,
    pub args: Vec<OsString>,
}

/// The longest request taken (a command line, not a file).
const MAX_REQUEST: u64 = 1 << 20;
const ANSWER: &[u8] = b"ok\n";

pub fn encode(cwd: &Path, args: &[OsString]) -> Vec<u8> {
    let mut out = cwd.as_os_str().as_bytes().to_vec();
    for a in args {
        out.push(0);
        out.extend_from_slice(a.as_bytes());
    }
    out
}

pub fn decode(bytes: &[u8]) -> Option<Request> {
    let mut parts = bytes.split(|b| *b == 0);
    let cwd = parts.next().filter(|c| !c.is_empty())?;
    Some(Request {
        cwd: PathBuf::from(OsString::from_vec(cwd.to_vec())),
        args: parts.filter(|a| !a.is_empty()).map(|a| OsString::from_vec(a.to_vec())).collect(),
    })
}

/// The socket's place: the runtime folder when there is one, else the state folder (both are the user's own).
pub fn socket_path() -> Option<PathBuf> {
    // an explicit place (tests, or two separate sets of windows)
    if let Some(p) = std::env::var_os("LEADER_SOCKET").map(PathBuf::from) {
        return Some(p);
    }
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).filter(|d| d.is_dir()).or_else(|| {
        std::env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".local/state")))
            .map(|s| s.join("leader"))
    })?;
    let _ = std::fs::create_dir_all(&dir);
    Some(dir.join("leader.sock"))
}

/// Hands the request to the window listening on `path`. True only once that window answered.
pub fn forward_to(path: &Path, cwd: &Path, args: &[OsString]) -> bool {
    let Ok(mut stream) = UnixStream::connect(path) else { return false };
    let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(500)));
    if stream.write_all(&encode(cwd, args)).is_err() || stream.shutdown(std::net::Shutdown::Write).is_err() {
        return false;
    }
    let mut answer = [0u8; 3];
    stream.read_exact(&mut answer).is_ok() && answer == *ANSWER
}

pub fn forward(cwd: &Path, args: &[OsString]) -> bool {
    socket_path().is_some_and(|p| forward_to(&p, cwd, args))
}

/// Listens on `path` and calls `handler` for every request, on its own thread. Returns false (and listens to nothing)
/// when another window already owns the socket.
pub fn serve_at(path: &Path, handler: impl Fn(Request) + Send + 'static) -> bool {
    if path.exists() {
        if UnixStream::connect(path).is_ok() {
            return false;
        }
        let _ = std::fs::remove_file(path); // a window that crashed left it
    }
    let Ok(listener) = UnixListener::bind(path) else { return false };
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    let spawned = std::thread::Builder::new().name("single".into()).spawn(move || {
        for stream in listener.incoming().flatten() {
            let mut stream = stream;
            let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
            let mut bytes = Vec::new();
            if (&stream).take(MAX_REQUEST).read_to_end(&mut bytes).is_err() {
                continue;
            }
            if let Some(request) = decode(&bytes) {
                handler(request);
                let _ = stream.write_all(ANSWER);
            }
        }
    });
    spawned.is_ok()
}

pub fn serve(handler: impl Fn(Request) + Send + 'static) -> Option<PathBuf> {
    let path = socket_path()?;
    serve_at(&path, handler).then_some(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    fn temp_socket(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("leader-single-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("leader.sock")
    }

    #[test]
    fn requests_round_trip() {
        let args = vec![OsString::from("src/main.rs"), OsString::from("my file.txt"), OsString::from("+12")];
        let got = decode(&encode(Path::new("/work/app"), &args)).unwrap();
        assert_eq!(got, Request { cwd: PathBuf::from("/work/app"), args });
        let bare = decode(&encode(Path::new("/work/app"), &[])).unwrap();
        assert!(bare.args.is_empty(), "no arguments just raises the window");
        assert_eq!(decode(b""), None, "a request without a folder is nothing");
    }

    #[test]
    fn a_window_receives_what_is_forwarded_and_answers() {
        let path = temp_socket("receives");
        let (tx, rx) = mpsc::channel();
        assert!(serve_at(&path, move |r| tx.send(r).unwrap()));
        let args = vec![OsString::from("a.go"), OsString::from("b.go")];
        assert!(forward_to(&path, Path::new("/p"), &args), "the window answered");
        let got = rx.recv_timeout(Duration::from_secs(2)).unwrap();
        assert_eq!(got, Request { cwd: PathBuf::from("/p"), args });
    }

    #[test]
    fn nobody_listening_is_not_a_delivery() {
        let path = temp_socket("nobody");
        assert!(!forward_to(&path, Path::new("/p"), &[]), "no socket");
        // a leftover file from a window that crashed is no listener either
        drop(UnixListener::bind(&path).unwrap());
        assert!(!forward_to(&path, Path::new("/p"), &[]), "stale socket");
    }

    #[test]
    fn a_stale_socket_is_replaced_and_a_live_one_is_respected() {
        let path = temp_socket("stale");
        drop(UnixListener::bind(&path).unwrap());
        let (tx, rx) = mpsc::channel();
        assert!(serve_at(&path, move |r| tx.send(r).unwrap()), "takes over the crashed window's socket");
        assert!(!serve_at(&path, |_| {}), "a second window does not steal a live socket");
        assert!(forward_to(&path, Path::new("/q"), &[OsString::from("x")]));
        assert_eq!(rx.recv_timeout(Duration::from_secs(2)).unwrap().args, vec![OsString::from("x")]);
    }

    #[test]
    fn the_socket_is_private() {
        let path = temp_socket("private");
        assert!(serve_at(&path, |_| {}));
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }
}
