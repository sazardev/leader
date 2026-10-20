//! What the app needs from the machine before any window or GPU exists: a display and the real
//! GPU on WSL (WSLg sessions started from a plain shell often miss the variables).
use std::env;
use std::path::Path;

/// The application id: what Wayland and X11 call the window, what the `.desktop` file and the AppStream metadata are
/// named after, so a launcher pairs the window with its icon and menu entry (`io.github.sazardev.Leader.desktop`).
pub const APP_ID: &str = "io.github.sazardev.Leader";

/// The 128×128 RGBA window icon (assets/make-icons.sh): X11 and Windows take it from the program, Wayland from the
/// `.desktop` file.
pub const WINDOW_ICON: &[u8] = include_bytes!("../../../assets/window-icon-128.rgba");

pub fn window_icon() -> Option<winit::window::Icon> {
    winit::window::Icon::from_rgba(WINDOW_ICON.to_vec(), 128, 128).ok()
}

/// Is there no Neovim config at all? Then the first launch runs `leader-setup` in the window's own terminal instead of
/// opening a bare editor. Another config (the person's own) is left alone.
pub fn config_missing() -> bool {
    let base =
        env::var_os("XDG_CONFIG_HOME").map(std::path::PathBuf::from).or_else(|| env::var_os("HOME").map(|h| Path::new(&h).join(".config")));
    let Some(dir) = base.map(|b| b.join("nvim")) else { return false };
    match std::fs::read_dir(&dir) {
        Ok(mut entries) => entries.next().is_none(),
        Err(_) => true,
    }
}

/// Says something to a person who started the app from a menu (no terminal to print to): stderr, and a desktop
/// notification when `notify-send` exists.
pub fn tell(title: &str, body: &str) {
    eprintln!("leader: {title}. {body}");
    if on_path("notify-send") {
        let _ = std::process::Command::new("notify-send").args(["--app-name=Leader", "--icon=leader", title, body]).status();
    }
}

/// Is `name` an executable somewhere on PATH?
pub fn on_path(name: &str) -> bool {
    env::var_os("PATH").is_some_and(|paths| {
        env::split_paths(&paths).any(|dir| {
            let p = dir.join(name);
            p.is_file()
        })
    })
}

pub fn is_wsl() -> bool {
    Path::new("/proc/sys/fs/binfmt_misc/WSLInterop").exists()
        || std::fs::read_to_string("/proc/version").is_ok_and(|v| v.to_lowercase().contains("microsoft"))
}

/// Fills in the display and GPU variables WSLg provides. Must run before any thread starts.
pub fn prepare_env() {
    if !is_wsl() {
        return;
    }
    let set = |key: &str, value: &str| {
        if env::var_os(key).is_none() {
            // SAFETY: called first thing in main, before any other thread exists.
            unsafe { env::set_var(key, value) };
        }
    };
    if Path::new("/mnt/wslg/runtime-dir/wayland-0").exists() {
        // An absolute path works whatever XDG_RUNTIME_DIR says.
        set("WAYLAND_DISPLAY", "/mnt/wslg/runtime-dir/wayland-0");
    }
    if Path::new("/tmp/.X11-unix/X0").exists() {
        set("DISPLAY", ":0");
    }
    // Mesa's d3d12 driver = the Windows GPU through /dev/dxg (otherwise llvmpipe, software).
    if Path::new("/dev/dxg").exists() && Path::new("/usr/lib/wsl/lib/libd3d12.so").exists() {
        set("GALLIUM_DRIVER", "d3d12");
    }
}

/// Backends worth trying here: WSL has no Vulkan driver for the GPU, only GL through d3d12.
pub fn backends() -> wgpu::Backends {
    if env::var_os("WGPU_BACKEND").is_some() {
        return wgpu::Backends::all().with_env();
    }
    if is_wsl() { wgpu::Backends::GL } else { wgpu::Backends::VULKAN | wgpu::Backends::GL }
}

fn state_file() -> Option<std::path::PathBuf> {
    state_path("window")
}

fn state_path(name: &str) -> Option<std::path::PathBuf> {
    let base = env::var_os("XDG_STATE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| Path::new(&h).join(".local/state")))?;
    Some(base.join("leader").join(name))
}

/// What the last run measured about the editor's text: the display scale and one cell, in physical pixels. With it the
/// next start knows how many columns and rows its window will have before any window or font exists, so Neovim can
/// start reading its config at once instead of waiting ~45 ms for them (the real size is applied when they are ready).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Cell {
    pub scale: f32,
    pub width: f32,
    pub height: f32,
}

impl Cell {
    pub fn parse(text: &str) -> Option<Cell> {
        let v: Vec<f32> = text.split_whitespace().filter_map(|w| w.parse().ok()).collect();
        match v.as_slice() {
            [scale, width, height] if *scale > 0.0 && *width >= 2.0 && *height >= 4.0 => {
                Some(Cell { scale: *scale, width: *width, height: *height })
            }
            _ => None,
        }
    }

    pub fn text(&self) -> String {
        format!("{} {} {}\n", self.scale, self.width, self.height)
    }
}

pub fn cached_cell() -> Option<Cell> {
    state_path("cell").and_then(|p| std::fs::read_to_string(p).ok()).and_then(|t| Cell::parse(&t))
}

/// Remembers the cell for the next start (written only when it changed).
pub fn save_cell(cell: &Cell) {
    if cached_cell().as_ref() == Some(cell) {
        return;
    }
    let Some(path) = state_path("cell") else { return };
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(path, cell.text());
}

/// How the window was when it closed: its size (logical px), where it was (physical px, when the system says) and
/// whether it was maximized. The file holds only what the person wants kept (settings.gui.window).
#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct Saved {
    pub size: Option<(f64, f64)>,
    pub position: Option<(i32, i32)>,
    pub maximized: bool,
}

impl Saved {
    /// First line `W H` (the old format), then `pos X Y` and `max` when kept.
    pub fn parse(text: &str) -> Saved {
        let mut saved = Saved::default();
        for (i, line) in text.lines().enumerate() {
            let words: Vec<&str> = line.split_whitespace().collect();
            match words.as_slice() {
                ["pos", x, y] => saved.position = x.parse().ok().zip(y.parse().ok()),
                ["max"] => saved.maximized = true,
                [w, h] if i == 0 => {
                    saved.size = w.parse::<f64>().ok().zip(h.parse::<f64>().ok()).filter(|(w, h)| *w >= 200.0 && *h >= 120.0)
                }
                _ => {}
            }
        }
        saved
    }

    pub fn text(&self) -> String {
        let mut out = String::new();
        if let Some((w, h)) = self.size {
            out.push_str(&format!("{} {}\n", w.round(), h.round()));
        } else {
            out.push_str("-\n");
        }
        if let Some((x, y)) = self.position {
            out.push_str(&format!("pos {x} {y}\n"));
        }
        if self.maximized {
            out.push_str("max\n");
        }
        out
    }
}

pub fn saved_window() -> Saved {
    state_file().and_then(|p| std::fs::read_to_string(p).ok()).map(|t| Saved::parse(&t)).unwrap_or_default()
}

pub fn save_window(saved: &Saved) {
    let Some(path) = state_file() else { return };
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(path, saved.text());
}

#[cfg(test)]
mod tests {
    use super::{Cell, Saved};

    #[test]
    fn cell_round_trips_and_rejects_nonsense() {
        let c = Cell { scale: 1.25, width: 10.0, height: 21.0 };
        assert_eq!(Cell::parse(&c.text()), Some(c));
        assert_eq!(Cell::parse(""), None);
        assert_eq!(Cell::parse("1 0 0"), None, "a zero-size cell would divide by zero");
        assert_eq!(Cell::parse("x y z"), None);
        assert_eq!(Cell::parse("1 10"), None);
    }

    #[test]
    fn saved_window_round_trips() {
        let s = Saved { size: Some((1200.0, 800.0)), position: Some((-1910, 40)), maximized: true };
        assert_eq!(Saved::parse(&s.text()), s);
        let none = Saved::default();
        assert_eq!(Saved::parse(&none.text()), none);
    }

    #[test]
    fn saved_window_reads_the_old_file() {
        assert_eq!(Saved::parse("1440 900\n").size, Some((1440.0, 900.0)));
        assert_eq!(Saved::parse("10 10\n").size, None, "too small to be a window");
    }
}
