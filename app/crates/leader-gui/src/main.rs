//! Leader: Neovim with the Leader config in its own GPU window.
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

use std::time::Instant;

use winit::event_loop::{ControlFlow, EventLoop};

use crate::app::{App, UserEvent};

const HELP: &str = "leader — the Leader editor in its own window

usage: leader [nvim arguments…]

environment:
  LEADER_NVIM    nvim binary to run (default: nvim on PATH)
  LEADER_FONT    font before the config sets guifont, e.g. \"Iosevka:h13\"
  LEADER_TIMING  print startup timings to stderr
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

fn main() {
    let started = Instant::now();
    platform::prepare_env();
    let mut args: Vec<_> = std::env::args_os().skip(1).collect();
    match args.first().and_then(|a| a.to_str()) {
        Some("--help" | "-h") => return println!("{HELP}"),
        Some("--version" | "-V") => return println!("leader {}", env!("CARGO_PKG_VERSION")),
        _ => {}
    }
    // Neovim is what runs inside the window: without it there is nothing to draw, and a menu launch has no terminal to say so
    if std::env::var_os("LEADER_NVIM").is_none() && !platform::on_path("nvim") {
        platform::tell(
            "Neovim is not installed",
            "Leader needs Neovim 0.11 or newer: install it with your package manager (pacman -S neovim, apt install neovim, brew install neovim) and open Leader again.",
        );
        std::process::exit(1);
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
    let mut app = match App::new(event_loop.create_proxy(), args, font_job, started) {
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
