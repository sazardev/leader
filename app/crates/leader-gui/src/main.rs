//! Leader: Neovim with the Leader config. In a terminal it is `nvim` itself (same arguments, same TTY, same exit
//! code); launched from the desktop menu (or with `--gui`) it opens Neovim in its own GPU window.
//! `leader [nvim args…]` — files, `+cmd`, `-d` … go straight to Neovim.
mod app;
mod appbar;
mod boxdraw;
mod clipboard;
mod font;
mod input;
mod platform;
mod renderer;
mod scene;
#[cfg(unix)]
mod single;

use std::time::Instant;

use winit::event_loop::{ControlFlow, EventLoop};

use crate::app::{App, UserEvent};

const HELP: &str = "leader — Neovim with the Leader config: in a terminal it is nvim
itself, from the desktop menu (or with --gui) it opens its own window

usage: leader [--gui] [--reuse] [nvim arguments…]

  In a terminal (stdin or stdout is a TTY) leader is nvim: every argument goes to nvim exactly as typed,
  with the same terminal, signals and exit code. Launched without a terminal (the applications menu) it
  opens the GPU window instead. Files, +cmd and -d work in both.

  --gui, --window  open the GPU window even from a terminal (same as LEADER_GUI=1)
  --reuse, -r      open the files in the window that is already running (instant: no new window, no new Neovim);
                   starts a window as usual when none is. Same as LEADER_REUSE=1.

environment:
  LEADER_NVIM    nvim binary to run (default: nvim on PATH)
  LEADER_GUI     1: always open the window, even in a terminal
  LEADER_FONT    font before the config sets guifont, e.g. \"Iosevka:h13\"
  LEADER_TIMING  print startup timings to stderr
  LEADER_REUSE   1: always behave like --reuse
  LEADER_SOCKET  where windows listen for --reuse (default: the runtime folder)
  WGPU_BACKEND   force a GPU backend (vulkan, gl)

window keys:
  F10               app menu              Ctrl+Shift+P      command palette
  Ctrl+Shift+O      open a project
  F11               fullscreen            Ctrl+Shift+Enter  maximize
  Ctrl+Shift+M      minimize              Ctrl+Shift+N      new window
  Ctrl+Shift+H      home (start screen)   Ctrl+Shift+R      recent files
  Ctrl+Shift+W      welcome and checks    Ctrl+Shift+V      paste
  Ctrl+= / - / 0    font size

first launch without a Neovim config runs `leader-setup` in the window (installs Leader's config).";

/// Is the user at a terminal? A launch from the applications menu has no TTY on stdin or stdout; a shell does.
fn at_terminal() -> bool {
    use std::io::IsTerminal;
    std::io::stdin().is_terminal() || std::io::stdout().is_terminal()
}

/// Terminal or window? In a terminal `leader` is `nvim` itself (exec: the same process, so the TTY, job control
/// and exit code are nvim's own, exactly like typing `nvim`); everywhere else it is the GPU window.
/// `--gui`/`--window`, `LEADER_GUI`, `--reuse`, `LEADER_REUSE` and `LEADER_SNAPSHOT` (the tests) always window.
fn use_terminal(terminal: bool, force_window: bool) -> bool {
    terminal && !force_window
}

fn env_flag(name: &str) -> bool {
    std::env::var_os(name).is_some_and(|v| v != "0")
}

/// Runs Neovim in the terminal, replacing this process: `leader file.go` is `nvim file.go`.
fn exec_nvim(args: &[std::ffi::OsString]) -> ! {
    let bin = std::env::var_os("LEADER_NVIM").unwrap_or_else(|| "nvim".into());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        let err = std::process::Command::new(&bin).args(args).exec();
        eprintln!("leader: cannot run nvim: {err}");
        std::process::exit(1);
    }
    #[cfg(not(unix))]
    {
        match std::process::Command::new(&bin).args(args).status() {
            Ok(status) => std::process::exit(status.code().unwrap_or(1)),
            Err(e) => {
                eprintln!("leader: cannot run nvim: {e}");
                std::process::exit(1);
            }
        }
    }
}

fn main() {
    let started = Instant::now();
    platform::prepare_env();
    let mut args: Vec<_> = std::env::args_os().skip(1).collect();
    match args.first().and_then(|a| a.to_str()) {
        Some("--help" | "-h") => return println!("{HELP}"),
        Some("--version" | "-V") => return println!("leader {}", env!("CARGO_PKG_VERSION")),
        _ => {}
    }
    // `--reuse`: hand the files to the window that is already running and leave before anything is built
    let flagged = args.iter().any(|a| a == "--reuse" || a == "-r");
    args.retain(|a| a != "--reuse" && a != "-r");
    #[cfg(unix)]
    if (flagged || std::env::var_os("LEADER_REUSE").is_some_and(|v| v != "0"))
        && std::env::var_os("LEADER_SNAPSHOT").is_none()
        && let Ok(cwd) = std::env::current_dir()
        && single::forward(&cwd, &args)
    {
        return;
    }
    #[cfg(not(unix))]
    let _ = flagged;
    // `--gui`/`--window` (and their env forms) force the window from a terminal; `--reuse` already means a window.
    let gui_flag = args.iter().any(|a| a == "--gui" || a == "--window");
    args.retain(|a| a != "--gui" && a != "--window");
    let force_window = gui_flag
        || env_flag("LEADER_GUI")
        || flagged
        || env_flag("LEADER_REUSE")
        || std::env::var_os("LEADER_SNAPSHOT").is_some();
    // Neovim is what runs inside the window: without it there is nothing to draw, and a menu launch has no terminal to say so
    if std::env::var_os("LEADER_NVIM").is_none() && !platform::on_path("nvim") {
        platform::tell(
            "Neovim is not installed",
            "Leader needs Neovim 0.11 or newer: install it with your package manager (pacman -S neovim, apt install neovim, brew install neovim) and open Leader again.",
        );
        std::process::exit(1);
    }
    // In a terminal, leader is nvim itself: replace this process so every argument, the TTY and the exit code
    // behave exactly like typing `nvim`. Only a launch without a terminal (the menu) opens the window.
    if use_terminal(at_terminal(), force_window) {
        exec_nvim(&args);
    }
    // First launch with no Neovim config at all: the window's own terminal runs the setup (it asks what it needs), then
    // Leader opens as itself the next time. Someone else's config is left alone.
    if args.is_empty() && platform::config_missing() && platform::on_path("leader-setup") {
        args.push("+terminal leader-setup".into());
    }
    // The font database loads while the window and the GPU start.
    let font_job = std::thread::Builder::new().name("fonts".into()).spawn(font::load_system).expect("font thread");
    let event_loop = match EventLoop::<UserEvent>::with_user_event().build() {
        Ok(l) => l,
        Err(e) => {
            eprintln!("leader: no display: {e}");
            std::process::exit(1);
        }
    };
    event_loop.set_control_flow(ControlFlow::Wait);
    // The graphics driver takes ~100 ms to load: start it now, while the window, the fonts and Neovim come up.
    let display = event_loop.owned_display_handle();
    let instance_job = std::thread::Builder::new()
        .name("gpu-instance".into())
        .spawn(move || renderer::Renderer::create_instance(display, platform::backends()))
        .expect("gpu instance thread");
    // This window takes the files a later `leader --reuse` hands over (never a snapshot run: tests must not hijack it)
    #[cfg(unix)]
    if std::env::var_os("LEADER_SNAPSHOT").is_none() {
        let proxy = event_loop.create_proxy();
        single::serve(move |request| {
            let _ = proxy.send_event(UserEvent::Open(request));
        });
    }
    let mut app = match App::new(event_loop.create_proxy(), args, font_job, instance_job, started) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("leader: {e}");
            std::process::exit(1);
        }
    };
    if let Err(e) = event_loop.run_app(&mut app) {
        eprintln!("leader: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::use_terminal;

    #[test]
    fn in_a_terminal_leader_is_nvim() {
        assert!(use_terminal(true, false), "typed in a shell it is nvim itself");
        assert!(!use_terminal(true, true), "--gui forces the window");
        assert!(!use_terminal(false, false), "a menu launch opens the window");
        assert!(!use_terminal(false, true), "no terminal anyway opens the window");
    }
}
