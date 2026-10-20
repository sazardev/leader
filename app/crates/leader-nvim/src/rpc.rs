use std::collections::HashMap;
use std::ffi::OsString;
use std::io::{BufReader, BufWriter, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;

use rmpv::Value;

use crate::event::{self, Event};

#[derive(Debug)]
pub enum RpcError {
    Io(std::io::Error),
    Nvim(String),
    Closed,
}

impl std::fmt::Display for RpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RpcError::Io(e) => write!(f, "io: {e}"),
            RpcError::Nvim(e) => write!(f, "nvim: {e}"),
            RpcError::Closed => write!(f, "nvim closed the connection"),
        }
    }
}

impl std::error::Error for RpcError {}

impl From<std::io::Error> for RpcError {
    fn from(e: std::io::Error) -> Self {
        RpcError::Io(e)
    }
}

/// Serves what Neovim asks the UI (`rpcrequest`/`rpcnotify` on our channel): method, args → reply.
/// Runs on the reader thread; notifications' replies are dropped.
pub type Handler = Box<dyn FnMut(&str, &[Value]) -> Result<Value, Value> + Send>;

/// Called on the reader thread after each `redraw` batch is queued (e.g. to wake the event loop).
pub type Waker = Box<dyn Fn() + Send>;

type Pending = Arc<Mutex<HashMap<u64, Sender<Result<Value, String>>>>>;
type Writer = Arc<Mutex<BufWriter<ChildStdin>>>;

/// How to start Neovim.
#[derive(Debug, Clone)]
pub struct Spawn {
    pub program: OsString,
    pub args: Vec<OsString>,
    pub env: Vec<(OsString, OsString)>,
}

impl Default for Spawn {
    fn default() -> Self {
        Spawn { program: "nvim".into(), args: Vec::new(), env: Vec::new() }
    }
}

/// A running embedded Neovim. Requests block on their reply; UI events arrive on `events()`.
pub struct Nvim {
    child: Child,
    writer: Writer,
    pending: Pending,
    next_id: u64,
    events: Receiver<Vec<Event>>,
}

fn write_msg(writer: &Writer, msg: &Value) -> Result<(), RpcError> {
    let mut out = writer.lock().unwrap();
    rmpv::encode::write_value(&mut *out, msg).map_err(|e| RpcError::Nvim(e.to_string()))?;
    out.flush()?;
    Ok(())
}

impl Nvim {
    /// Starts `nvim --embed` plus `spec.args`. Neovim waits for `attach` before reading its config.
    pub fn spawn(spec: Spawn, mut handler: Handler, waker: Waker) -> Result<Nvim, RpcError> {
        let mut child = Command::new(&spec.program)
            .arg("--embed")
            .args(&spec.args)
            .envs(spec.env.iter().map(|(k, v)| (k, v)))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()?;
        let writer: Writer = Arc::new(Mutex::new(BufWriter::new(child.stdin.take().expect("piped stdin"))));
        let stdout = child.stdout.take().expect("piped stdout");
        let pending: Pending = Arc::default();
        let (tx, events) = mpsc::channel();

        let reply_to = Arc::clone(&pending);
        let answer = Arc::clone(&writer);
        thread::Builder::new().name("nvim-rpc".into()).spawn(move || {
            let mut reader = BufReader::with_capacity(1 << 16, stdout);
            while let Ok(msg) = rmpv::decode::read_value(&mut reader) {
                let Value::Array(mut parts) = msg else { continue };
                match parts.first().and_then(Value::as_u64) {
                    Some(1) if parts.len() == 4 => {
                        let id = parts[1].as_u64().unwrap_or(0);
                        let result = parts.pop().unwrap_or(Value::Nil);
                        let error = parts.pop().unwrap_or(Value::Nil);
                        let out = if error.is_nil() { Ok(result) } else { Err(error.to_string()) };
                        if let Some(waiter) = reply_to.lock().unwrap().remove(&id) {
                            let _ = waiter.send(out);
                        }
                    }
                    Some(2) if parts.len() == 3 => {
                        let params = parts.pop().unwrap_or(Value::Nil);
                        let method = parts[1].as_str().unwrap_or_default();
                        if method == "redraw" {
                            if tx.send(event::parse_redraw(&params)).is_err() {
                                break;
                            }
                            waker();
                        } else {
                            let _ = handler(method, params.as_array().map(Vec::as_slice).unwrap_or(&[]));
                        }
                    }
                    Some(0) if parts.len() == 4 => {
                        let params = parts.pop().unwrap_or(Value::Nil);
                        let method = parts[2].as_str().unwrap_or_default().to_string();
                        let (error, result) = match handler(&method, params.as_array().map(Vec::as_slice).unwrap_or(&[])) {
                            Ok(v) => (Value::Nil, v),
                            Err(e) => (e, Value::Nil),
                        };
                        let reply = Value::Array(vec![1.into(), parts[1].clone(), error, result]);
                        let _ = write_msg(&answer, &reply);
                    }
                    _ => {}
                }
            }
            // Neovim went away: fail whoever still waits, then wake the UI so it sees the closed channel.
            for (_, waiter) in reply_to.lock().unwrap().drain() {
                let _ = waiter.send(Err("closed".into()));
            }
            drop(tx);
            waker();
        })?;

        Ok(Nvim { child, writer, pending, next_id: 1, events })
    }

    pub fn events(&self) -> &Receiver<Vec<Event>> {
        &self.events
    }

    pub fn request(&mut self, method: &str, params: Vec<Value>) -> Result<Value, RpcError> {
        let id = self.next_id;
        self.next_id += 1;
        let (tx, rx) = mpsc::channel();
        self.pending.lock().unwrap().insert(id, tx);
        write_msg(&self.writer, &Value::Array(vec![0.into(), id.into(), method.into(), Value::Array(params)]))?;
        match rx.recv() {
            Ok(Ok(v)) => Ok(v),
            Ok(Err(e)) if e == "closed" => Err(RpcError::Closed),
            Ok(Err(e)) => Err(RpcError::Nvim(e)),
            Err(_) => Err(RpcError::Closed),
        }
    }

    /// Fire and forget: never blocks on Neovim, so input stays instant.
    pub fn notify(&self, method: &str, params: Vec<Value>) -> Result<(), RpcError> {
        write_msg(&self.writer, &Value::Array(vec![2.into(), method.into(), Value::Array(params)]))
    }

    /// Attaches as the UI with the extensions the app draws itself.
    pub fn attach(&mut self, cols: u32, rows: u32) -> Result<(), RpcError> {
        let opts = Value::Map(vec![
            ("rgb".into(), true.into()),
            ("ext_linegrid".into(), true.into()),
            ("ext_multigrid".into(), true.into()),
            ("ext_hlstate".into(), false.into()),
        ]);
        self.request("nvim_ui_attach", vec![cols.into(), rows.into(), opts])?;
        Ok(())
    }

    pub fn input(&self, keys: &str) -> Result<(), RpcError> {
        self.notify("nvim_input", vec![keys.into()])
    }

    pub fn try_resize(&self, cols: u32, rows: u32) -> Result<(), RpcError> {
        self.notify("nvim_ui_try_resize", vec![cols.into(), rows.into()])
    }

    /// The channel id Neovim gave us (for `rpcrequest(chan, …)` from Lua).
    pub fn channel(&mut self) -> Result<u64, RpcError> {
        let info = self.request("nvim_get_api_info", vec![])?;
        Ok(info.as_array().and_then(|a| a.first()).and_then(Value::as_u64).unwrap_or(0))
    }

    pub fn exec_lua(&mut self, code: &str, args: Vec<Value>) -> Result<Value, RpcError> {
        self.request("nvim_exec_lua", vec![code.into(), Value::Array(args)])
    }
}

impl Drop for Nvim {
    fn drop(&mut self) {
        // Normally Neovim has already quit. If the window died first, stop it: unsaved work stays in swap files.
        if let Ok(None) = self.child.try_wait() {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}
