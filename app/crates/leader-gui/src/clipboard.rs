//! The system clipboard, served to Neovim over RPC (`vim.g.clipboard` calls back into the app),
//! so `"+y`/`"+p` work with no wl-copy, xclip or OSC 52.
use std::sync::{Arc, Mutex};

use rmpv::Value;

#[derive(Default)]
struct State {
    board: Option<arboard::Clipboard>,
    /// What we copied last and its register type, to give `V`/block yanks back as such.
    last: Option<(String, String)>,
}

#[derive(Clone, Default)]
pub struct Clipboard(Arc<Mutex<State>>);

/// Installed before the config loads; `core.clipboard` leaves it alone when `vim.g.leader_gui` is set.
pub const SETUP_LUA: &str = r#"
local chan = ...
vim.g.leader_gui = true
vim.g.leader_gui_channel = chan
local function copy(lines, regtype) vim.rpcnotify(chan, "leader_clipboard_set", lines, regtype) end
local function paste() return vim.rpcrequest(chan, "leader_clipboard_get") end
vim.g.clipboard = {
  name = "Leader",
  copy = { ["+"] = copy, ["*"] = copy },
  paste = { ["+"] = paste, ["*"] = paste },
  cache_enabled = 0,
}
-- The generic default guifont tells the app that nothing was chosen yet.
return vim.api.nvim_get_option_info2("guifont", {}).default
"#;

impl Clipboard {
    fn with<T>(&self, f: impl FnOnce(&mut State) -> T) -> T {
        let mut s = self.0.lock().unwrap();
        if s.board.is_none() {
            s.board = arboard::Clipboard::new().ok();
        }
        f(&mut s)
    }

    pub fn text(&self) -> Option<String> {
        self.with(|s| s.board.as_mut()?.get_text().ok())
    }

    pub fn set(&self, args: &[Value]) {
        let lines: Vec<&str> =
            args.first().and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
        let regtype = args.get(1).and_then(Value::as_str).unwrap_or("v").to_string();
        let mut text = lines.join("\n");
        if regtype == "V" {
            text.push('\n');
        }
        self.with(|s| {
            if let Some(b) = s.board.as_mut() {
                let _ = b.set_text(text.clone());
            }
            s.last = Some((text, regtype));
        });
    }

    /// `[lines, regtype]` for the paste provider.
    pub fn get(&self) -> Value {
        let (text, last) = self.with(|s| (s.board.as_mut().and_then(|b| b.get_text().ok()), s.last.clone()));
        let text = text.unwrap_or_default();
        let regtype = match last {
            Some((t, r)) if t == text => r,
            _ if text.ends_with('\n') => "V".into(),
            _ => "v".into(),
        };
        let body = if regtype == "V" { text.strip_suffix('\n').unwrap_or(&text) } else { &text };
        let lines = body.split('\n').map(|l| Value::from(l.strip_suffix('\r').unwrap_or(l))).collect();
        Value::Array(vec![Value::Array(lines), regtype.into()])
    }
}
