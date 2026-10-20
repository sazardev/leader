//! Attaches to a headless Neovim, opens a file and prints the composed screen.
//! `cargo run -p leader-nvim --example dump -- path/to/file`
use std::time::{Duration, Instant};

use leader_nvim::{Nvim, Screen, Spawn};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let file = std::env::args().nth(1);
    let started = Instant::now();
    let spec = Spawn { args: vec!["--headless".into(), "-u".into(), "NONE".into()], ..Default::default() };
    let mut nvim = Nvim::spawn(spec, Box::new(|_, _| Ok(rmpv::Value::Nil)), Box::new(|| {}))?;
    nvim.attach(60, 12)?;
    if let Some(f) = &file {
        nvim.request("nvim_command", vec![format!("edit {f}").into()])?;
    }

    let mut screen = Screen::default();
    let mut first_flush = None;
    let deadline = Instant::now() + Duration::from_millis(500);
    while let Ok(batch) = nvim.events().recv_timeout(deadline.saturating_duration_since(Instant::now())) {
        for ev in batch {
            if screen.apply(ev) && first_flush.is_none() {
                first_flush = Some(started.elapsed());
            }
        }
    }

    // Compose every layer onto one canvas, like the GUI does.
    let mut canvas = vec![vec![' '; 60]; 12];
    for layer in screen.layers() {
        for r in 0..layer.grid.height {
            for (c, cell) in layer.grid.row(r).iter().enumerate() {
                let (y, x) = ((layer.row as i64 + r as i64) as usize, (layer.col as i64 + c as i64) as usize);
                if let (Some(line), Some(ch)) = (canvas.get_mut(y), cell.text.chars().next()) {
                    if let Some(slot) = line.get_mut(x) {
                        *slot = ch;
                    }
                }
            }
        }
    }
    for line in canvas {
        println!("{}", line.into_iter().collect::<String>().trim_end());
    }
    eprintln!(
        "layers {:?}, cursor {:?}, first flush after {:?}",
        screen.layers().iter().map(|l| l.id).collect::<Vec<_>>(),
        screen.cursor_position(),
        first_flush
    );
    Ok(())
}
