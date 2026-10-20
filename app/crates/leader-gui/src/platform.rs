//! What the app needs from the machine before any window or GPU exists: a display and the real
//! GPU on WSL (WSLg sessions started from a plain shell often miss the variables).
use std::env;
use std::path::Path;

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
    let base = env::var_os("XDG_STATE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|h| Path::new(&h).join(".local/state")))?;
    Some(base.join("leader").join("window"))
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
    use super::Saved;

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
