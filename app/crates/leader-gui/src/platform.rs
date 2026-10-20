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

/// Last window size in logical pixels (written on exit), if any.
pub fn saved_size() -> Option<(f64, f64)> {
    let text = std::fs::read_to_string(state_file()?).ok()?;
    let mut it = text.split_whitespace().map(|n| n.parse::<f64>().ok());
    let (w, h) = (it.next()??, it.next()??);
    (w >= 200.0 && h >= 120.0).then_some((w, h))
}

pub fn save_size(w: f64, h: f64) {
    let Some(path) = state_file() else { return };
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(path, format!("{} {}\n", w.round(), h.round()));
}
