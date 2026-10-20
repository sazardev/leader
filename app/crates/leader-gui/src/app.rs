//! The window: winit events in, Neovim events in, frames out. Nothing runs between events
//! (no render loop, no polling): a frame is drawn when Neovim flushes or the window changes.
use std::ffi::OsString;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::TryRecvError;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use cosmic_text::FontSystem;
use leader_nvim::screen::parse_guifont;
use leader_nvim::{Nvim, Screen, Spawn};
use rmpv::Value;
use winit::application::ApplicationHandler;
use winit::dpi::{LogicalSize, PhysicalPosition};
use winit::event::{ElementState, MouseButton, MouseScrollDelta, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow, EventLoopProxy};
use winit::keyboard::{Key, ModifiersState, NamedKey};
use winit::window::{CursorIcon, ResizeDirection, Window, WindowId};

use crate::appbar::{self, Bar, Hit};
use crate::clipboard::{self, Clipboard};
use crate::font::{self, Fonts};
use crate::renderer::Renderer;
use crate::scene::View;
use crate::{input, platform};

pub enum UserEvent {
    /// Neovim queued redraw batches (or closed).
    Nvim,
    /// The GPU finished starting on its own thread (it overlaps with Neovim reading its config).
    Gpu(Box<Result<Renderer, String>>),
    /// The config sent the app bar's state (`leader_appbar`).
    Appbar(Value),
    /// A window command from the config's menus (`leader_window`).
    Window(String),
}

#[derive(Default)]
struct Mouse {
    pos: PhysicalPosition<f64>,
    /// Button held and the grid the press landed on (drags stay on it).
    pressed: Option<(&'static str, u64)>,
    last: Option<(u64, u32, u32)>,
    /// Last cell a hover ("move") event was sent for: one event per cell, not per pixel.
    hovered: Option<(u64, u32, u32)>,
    /// A hover sent and not drawn yet: while it is, a faster pointer only moves `hover_next`, sent once Neovim has
    /// drawn (or after `HOVER_WAIT`), so a sweep across a list costs one hover per frame, not one per cell crossed.
    hover_sent: Option<Instant>,
    hover_next: Option<(u64, u32, u32)>,
    scroll: (f64, f64),
    /// A window button or path part held down (acts on release over the same one).
    button: Option<Hit>,
    /// Last press on the bar's empty space (a second one soon after = double click).
    bar_click: Option<Instant>,
    icon: Option<CursorIcon>,
}

/// How long a hover may wait for Neovim to draw the previous one before the pointer's newest cell goes anyway.
const HOVER_WAIT: Duration = Duration::from_millis(40);

pub struct App {
    proxy: EventLoopProxy<UserEvent>,
    started: Instant,
    timing: bool,
    font_job: Option<JoinHandle<FontSystem>>,
    nvim: Nvim,
    pending: Arc<AtomicBool>,
    clipboard: Clipboard,
    screen: Screen,
    fonts: Option<Fonts>,
    window: Option<Arc<Window>>,
    renderer: Option<Renderer>,
    grid: (u32, u32),
    origin: (f32, f32),
    mods: ModifiersState,
    focused: bool,
    mouse: Mouse,
    bar: Bar,
    guifont: String,
    /// Neovim's built-in `guifont` (a generic list): seeing it means nobody chose a font, keep ours.
    default_guifont: String,
    title: Option<String>,
    first_frame: bool,
    first_flush: bool,
    blink: Blink,
    /// Started by LEADER_SNAPSHOT (a test): nothing is saved.
    scripted: bool,
    /// The window as it was when last neither maximized nor fullscreen (what "remember size/position" keeps).
    normal: platform::Saved,
    /// Last input sent and not drawn yet (LEADER_TIMING prints input → frame latency).
    input_at: Option<Instant>,
    /// `LEADER_SNAPSHOT=out.png`: keys to type after the first frame, then a PNG of the window and quit.
    snapshot: Option<Snapshot>,
}

/// Cursor blinking like Neovim's TUI: shown for `blinkwait` after any change, then on/off.
#[derive(Default)]
struct Blink {
    on: bool,
    next: Option<Instant>,
    /// Cursor and mode last time it was reset: other redraws (statusline timers, LSP progress) keep the rhythm.
    seen: Option<(u64, u32, u32, usize)>,
}

impl Blink {
    fn timings(screen: &Screen) -> Option<(u64, u64, u64)> {
        let m = screen.current_mode()?;
        (m.blinkwait > 0 && m.blinkon > 0 && m.blinkoff > 0).then_some((m.blinkwait as u64, m.blinkon as u64, m.blinkoff as u64))
    }

    /// The cursor moved or something was typed: show it and start over.
    fn reset(&mut self, screen: &Screen, focused: bool) {
        self.on = true;
        self.next = Self::timings(screen).filter(|_| focused).map(|(wait, _, _)| Instant::now() + Duration::from_millis(wait));
    }

    /// Flips when due; true if the cursor changed.
    fn tick(&mut self, screen: &Screen) -> bool {
        let Some(next) = self.next else { return false };
        if Instant::now() < next {
            return false;
        }
        let Some((_, on, off)) = Self::timings(screen) else {
            self.on = true;
            self.next = None;
            return true;
        };
        self.on = !self.on;
        self.next = Some(Instant::now() + Duration::from_millis(if self.on { on } else { off }));
        true
    }
}

struct Snapshot {
    path: std::path::PathBuf,
    keys: Option<String>,
    delay: std::time::Duration,
    /// When the keys are typed (after the config's lazy plugins loaded), then when the PNG is taken.
    keys_at: Option<Instant>,
    at: Option<Instant>,
}

impl App {
    pub fn new(
        proxy: EventLoopProxy<UserEvent>,
        args: Vec<OsString>,
        font_job: JoinHandle<FontSystem>,
        started: Instant,
    ) -> Result<App, String> {
        let pending = Arc::new(AtomicBool::new(false));
        let clipboard = Clipboard::default();
        let served = clipboard.clone();
        let bar_proxy = proxy.clone();
        let handler = Box::new(move |method: &str, args: &[Value]| match method {
            // the config's menus ask the window for what only it can do (fullscreen, zoom, a new window…)
            "leader_window" => {
                let name = args.first().and_then(Value::as_str).unwrap_or_default().to_string();
                let _ = bar_proxy.send_event(UserEvent::Window(name));
                Ok(Value::Nil)
            }
            "leader_appbar" => {
                let _ = bar_proxy.send_event(UserEvent::Appbar(args.first().cloned().unwrap_or(Value::Nil)));
                Ok(Value::Nil)
            }
            "leader_clipboard_set" => {
                served.set(args);
                Ok(Value::Nil)
            }
            "leader_clipboard_get" => Ok(served.get()),
            other => Err(Value::from(format!("leader: unknown method {other}"))),
        });
        let wake = Arc::clone(&pending);
        let wake_proxy = proxy.clone();
        let waker = Box::new(move || {
            if !wake.swap(true, Ordering::AcqRel) {
                let _ = wake_proxy.send_event(UserEvent::Nvim);
            }
        });
        let program = std::env::var_os("LEADER_NVIM").unwrap_or_else(|| "nvim".into());
        let spec = Spawn { program, args, env: Vec::new() };
        let mut nvim = Nvim::spawn(spec, handler, waker).map_err(|e| format!("could not start nvim: {e}"))?;
        // Before attach Neovim has not read its config yet: the clipboard provider goes in first.
        let chan = nvim.channel().map_err(|e| e.to_string())?;
        let default_guifont = nvim.exec_lua(clipboard::SETUP_LUA, vec![chan.into()]).map_err(|e| e.to_string())?;
        let default_guifont = default_guifont.as_str().unwrap_or_default().to_string();
        let timing = std::env::var_os("LEADER_TIMING").is_some();
        let app = App {
            proxy,
            started,
            timing,
            font_job: Some(font_job),
            nvim,
            pending,
            clipboard,
            screen: Screen::default(),
            fonts: None,
            window: None,
            renderer: None,
            grid: (0, 0),
            origin: (0.0, 0.0),
            mods: ModifiersState::empty(),
            focused: true,
            mouse: Mouse::default(),
            bar: Bar::default(),
            guifont: String::new(),
            default_guifont,
            title: None,
            first_frame: true,
            first_flush: true,
            blink: Blink { on: true, next: None, seen: None },
            scripted: std::env::var_os("LEADER_SNAPSHOT").is_some(),
            normal: platform::Saved::default(),
            input_at: None,
            snapshot: std::env::var_os("LEADER_SNAPSHOT").map(|p| Snapshot {
                path: p.into(),
                keys: std::env::var("LEADER_KEYS").ok(),
                delay: std::time::Duration::from_millis(
                    std::env::var("LEADER_SNAPSHOT_MS").ok().and_then(|v| v.parse().ok()).unwrap_or(1500),
                ),
                keys_at: None,
                at: None,
            }),
        };
        app.mark("nvim spawned");
        Ok(app)
    }

    fn mark(&self, what: &str) {
        if self.timing {
            eprintln!("[leader] {:>7.1} ms  {what}", self.started.elapsed().as_secs_f64() * 1000.0);
        }
    }

    /// Cells that fit under the app bar, inside the padding (the bottom one keeps the statusline off the
    /// window edge); leftover pixels are split evenly.
    fn layout(&mut self) -> bool {
        let (Some(window), Some(fonts)) = (&self.window, &self.fonts) else { return false };
        let size = window.inner_size();
        let m = fonts.metrics;
        let scale = fonts.scale;
        let bar = self.bar.height(&m);
        let pad_x = (self.bar.state.pad_x * scale).round();
        let pad_bottom = (self.bar.state.pad_bottom * scale).round();
        let top = bar;
        let (w, h) = (size.width as f32 - 2.0 * pad_x, size.height as f32 - top - pad_bottom);
        let cols = ((w / m.width).floor() as u32).max(1);
        let rows = ((h / m.height).floor() as u32).max(1);
        // Bottom-aligned: the rows' leftover pixels sit between the bar and the editor, where nobody sees them (the bar
        // is the editor's color); the statusline keeps its own height on the window's bottom edge. The columns'
        // leftover is covered by the right edge cells, which stretch (scene.rs).
        self.origin = (pad_x, (size.height as f32 - pad_bottom - rows as f32 * m.height).floor().max(top));
        let changed = (cols, rows) != self.grid;
        self.grid = (cols, rows);
        changed
    }

    fn relayout(&mut self) {
        if self.layout() {
            let _ = self.nvim.try_resize(self.grid.0, self.grid.1);
        }
        self.redraw();
    }

    /// Draws a frame now. Called right on Neovim's flush (no trip through the windowing system's
    /// redraw scheduling, which can add a frame of latency) and on expose/resize.
    fn render(&mut self, event_loop: &ActiveEventLoop) {
        let (Some(renderer), Some(fonts)) = (self.renderer.as_mut(), self.fonts.as_mut()) else { return };
        // Nothing to show until Neovim drew once (no flash of an empty window).
        if self.screen.grids.is_empty() {
            return;
        }
        let width = self.window.as_ref().map(|w| w.inner_size().width as f32).unwrap_or_default();
        let view =
            View { origin: self.origin, focused: self.focused, cursor_on: self.blink.on, bar: Some(&self.bar), width, scale: fonts.scale };
        renderer.render(&self.screen, fonts, &view);
        if let Some(t) = self.input_at.take().filter(|_| self.timing) {
            eprintln!("[leader] input → frame {:.2} ms", t.elapsed().as_secs_f64() * 1000.0);
        }
        if self.first_frame {
            self.first_frame = false;
            self.mark("first frame");
            if let Some(snap) = self.snapshot.as_mut() {
                let now = Instant::now();
                snap.keys_at = snap.keys.as_ref().map(|_| now + snap.delay);
                snap.at = Some(now + snap.delay * if snap.keys.is_some() { 2 } else { 1 });
                event_loop.set_control_flow(winit::event_loop::ControlFlow::WaitUntil(snap.keys_at.or(snap.at).unwrap()));
            }
        }
    }

    /// The size and place to reopen with: only taken while the window is neither maximized nor fullscreen, so
    /// closing a maximized window reopens it maximized over the size it had before.
    fn note_normal(&mut self) {
        let Some(w) = &self.window else { return };
        if w.is_maximized() || w.fullscreen().is_some() || w.is_minimized() == Some(true) {
            return;
        }
        let size = w.inner_size().to_logical::<f64>(w.scale_factor());
        self.normal.size = Some((size.width, size.height));
        if let Ok(p) = w.outer_position() {
            self.normal.position = Some((p.x, p.y));
        }
    }

    fn redraw(&self) {
        if let Some(w) = &self.window {
            w.request_redraw();
        }
    }

    fn apply_font(&mut self, spec: &str) {
        let Some(fonts) = self.fonts.as_mut() else { return };
        let (families, size) = parse_guifont(spec).unwrap_or_default();
        let size = size.unwrap_or(fonts.size);
        let scale = fonts.scale;
        fonts.set(&families, size, scale);
        if let Some(r) = self.renderer.as_mut() {
            r.clear_glyphs();
        }
        self.relayout();
    }

    fn zoom(&mut self, delta: f32) {
        let Some(fonts) = &self.fonts else { return };
        let size = if delta == 0.0 { font::DEFAULT_SIZE } else { (fonts.size + delta).clamp(6.0, 48.0) };
        // Through `guifont`, so Neovim and the window agree on one value.
        let spec = format!("{}:h{size}", fonts.family());
        let _ = self.nvim.notify("nvim_set_option_value", vec!["guifont".into(), spec.into(), Value::Map(vec![])]);
    }

    fn drain_nvim(&mut self, event_loop: &ActiveEventLoop) {
        self.pending.store(false, Ordering::Release);
        let mut flushed = false;
        loop {
            match self.nvim.events().try_recv() {
                Ok(batch) => {
                    for ev in batch {
                        flushed |= self.screen.apply(ev);
                    }
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    event_loop.exit();
                    return;
                }
            }
        }
        if !flushed {
            return;
        }
        self.hover_flush(true);
        if self.first_flush {
            self.first_flush = false;
            self.mark("first flush");
        }
        let c = self.screen.cursor;
        let seen = Some((c.grid, c.row, c.col, self.screen.mode));
        if seen != self.blink.seen || self.input_at.is_some() {
            self.blink.seen = seen;
            self.blink.reset(&self.screen, self.focused);
        }
        if let Some(t) = self.input_at.filter(|_| self.timing) {
            eprintln!("[leader] input → flush {:.2} ms", t.elapsed().as_secs_f64() * 1000.0);
        }
        let spec = self.screen.options.get("guifont").and_then(Value::as_str).unwrap_or_default().to_string();
        if spec != self.guifont {
            self.guifont = spec.clone();
            if !spec.is_empty() && spec != self.default_guifont {
                self.apply_font(&spec);
            }
        }
        // A modal (a float over a good part of the editor: Telescope, the welcome screen, which-key's panel) makes
        // the bar step back; notifications, keycaps and completion menus are too small to count.
        let root = self.screen.grids.get(&1).map(|g| (g.width * g.height) as f32).unwrap_or(1.0);
        let modal = self.screen.layers().iter().any(|l| l.floating && (l.grid.width * l.grid.height) as f32 > root * 0.12);
        self.bar.set_modal(modal);
        if self.screen.title != self.title {
            self.title = self.screen.title.clone();
            if let (Some(w), Some(t)) = (&self.window, &self.title) {
                w.set_title(t);
            }
        }
        self.render(event_loop);
    }

    fn cell_at(&self, pos: PhysicalPosition<f64>) -> Option<(f32, f32)> {
        let m = self.fonts.as_ref()?.metrics;
        let col = ((pos.x as f32 - self.origin.0) / m.width).floor();
        let row = ((pos.y as f32 - self.origin.1) / m.height).floor();
        Some((row.max(0.0), col.max(0.0)))
    }

    fn send_mouse(&self, button: &str, action: &str, grid: u64, row: u32, col: u32) {
        let args = vec![button.into(), action.into(), input::mouse_mods(self.mods).into(), grid.into(), row.into(), col.into()];
        let _ = self.nvim.notify("nvim_input_mouse", args);
    }

    /// Window edge under the pointer, for resizing a window without system decorations.
    fn edge(&self, pos: PhysicalPosition<f64>) -> Option<ResizeDirection> {
        let w = self.window.as_ref()?;
        if !self.bar.state.enabled || w.is_maximized() {
            return None;
        }
        let size = w.inner_size();
        let b = (5.0 * w.scale_factor()).max(3.0);
        let (x, y) = (pos.x, pos.y);
        let (left, right) = (x < b, x > size.width as f64 - b);
        let (top, bottom) = (y < b, y > size.height as f64 - b);
        Some(match (top, bottom, left, right) {
            (true, _, true, _) => ResizeDirection::NorthWest,
            (true, _, _, true) => ResizeDirection::NorthEast,
            (_, true, true, _) => ResizeDirection::SouthWest,
            (_, true, _, true) => ResizeDirection::SouthEast,
            (true, ..) => ResizeDirection::North,
            (_, true, ..) => ResizeDirection::South,
            (_, _, true, _) => ResizeDirection::West,
            (_, _, _, true) => ResizeDirection::East,
            _ => return None,
        })
    }

    fn bar_hit(&self, pos: PhysicalPosition<f64>) -> Hit {
        let (Some(w), Some(f)) = (&self.window, &self.fonts) else { return Hit::Outside };
        self.bar.hit(pos.x as f32, pos.y as f32, w.inner_size().width as f32, &f.metrics, &f.small)
    }

    fn set_icon(&mut self, icon: CursorIcon) {
        if self.mouse.icon != Some(icon) {
            self.mouse.icon = Some(icon);
            if let Some(w) = &self.window {
                w.set_cursor(icon);
            }
        }
    }

    fn press_bar(&mut self, event_loop: &ActiveEventLoop, hit: Hit) {
        let Some(w) = self.window.clone() else { return };
        match hit {
            Hit::Button(appbar::Button::Minimize) => w.set_minimized(true),
            Hit::Button(appbar::Button::Maximize) => w.set_maximized(!w.is_maximized()),
            Hit::Button(appbar::Button::Close) => {
                let _ = self.nvim.notify("nvim_command", vec!["confirm qall".into()]);
            }
            // The config decides what the left side opens (lua/gui/).
            Hit::Path(i) => {
                let code = "require('gui').click(...)";
                let _ = self.nvim.notify("nvim_exec_lua", vec![code.into(), Value::Array(vec![(i as u64).into()])]);
            }
            Hit::Mark => self.action_at("menu", hit),
            Hit::Chip(i) => {
                if let Some(a) = self.bar.state.chips.get(i).and_then(|c| c.action.clone()) {
                    self.action_at(&a, hit);
                }
            }
            Hit::Tool(side, i) => {
                if let Some(action) = self.bar.tool(side, i).map(|t| t.action.clone()) {
                    self.action_at(&action, hit);
                }
            }
            Hit::Drag | Hit::Outside => {}
        }
        self.bar.set_hover(None);
        self.render(event_loop);
    }

    /// Mouse buttons on the bar and the window edges; true when consumed (not for Neovim).
    fn on_chrome(&mut self, event_loop: &ActiveEventLoop, state: ElementState, button: MouseButton) -> bool {
        if button == MouseButton::Right {
            // a right click anywhere on the bar: what it shows, and in which order (the config's customize panel)
            let hit = self.bar_hit(self.mouse.pos);
            if hit != Hit::Outside && state == ElementState::Released && !matches!(hit, Hit::Button(_)) {
                let col = self.fonts.as_ref().map(|f| ((self.mouse.pos.x as f32 - self.origin.0) / f.metrics.width).max(0.0) as u32);
                self.action("customize", col.unwrap_or(0));
            }
            return hit != Hit::Outside;
        }
        if button != MouseButton::Left {
            return self.bar_hit(self.mouse.pos) != Hit::Outside;
        }
        match state {
            ElementState::Pressed => {
                if let Some(dir) = self.edge(self.mouse.pos) {
                    if let Some(w) = &self.window {
                        let _ = w.drag_resize_window(dir);
                    }
                    return true;
                }
                match self.bar_hit(self.mouse.pos) {
                    Hit::Outside => false,
                    hit @ (Hit::Button(_) | Hit::Path(_) | Hit::Mark | Hit::Tool(..) | Hit::Chip(_)) => {
                        self.mouse.button = Some(hit);
                        true
                    }
                    Hit::Drag => {
                        let double = self.mouse.bar_click.is_some_and(|t| t.elapsed() < Duration::from_millis(400));
                        self.mouse.bar_click = if double { None } else { Some(Instant::now()) };
                        if let Some(w) = self.window.clone() {
                            if double {
                                w.set_maximized(!w.is_maximized());
                            } else {
                                let _ = w.drag_window();
                            }
                        }
                        true
                    }
                }
            }
            ElementState::Released => {
                let Some(hit) = self.mouse.button.take() else { return false };
                if self.bar_hit(self.mouse.pos) == hit {
                    self.press_bar(event_loop, hit);
                }
                true
            }
        }
    }

    fn on_button(&mut self, state: ElementState, button: MouseButton) {
        let name = match button {
            MouseButton::Left => "left",
            MouseButton::Right => "right",
            MouseButton::Middle => "middle",
            _ => return,
        };
        let Some((row, col)) = self.cell_at(self.mouse.pos) else { return };
        match state {
            ElementState::Pressed => {
                let Some((grid, r, c)) = self.screen.grid_at(row, col) else { return };
                self.mouse.pressed = Some((name, grid));
                self.mouse.last = Some((grid, r, c));
                self.send_mouse(name, "press", grid, r, c);
            }
            ElementState::Released => {
                if let Some((_, grid)) = self.mouse.pressed.take() {
                    let (r, c) = self.local(grid, row, col);
                    self.send_mouse(name, "release", grid, r, c);
                }
            }
        }
    }

    /// An editor cell relative to a grid (for drags that leave it: clamped at its edges).
    fn local(&self, grid: u64, row: f32, col: f32) -> (u32, u32) {
        let (gr, gc) = self.screen.grid_origin(grid).unwrap_or((0.0, 0.0));
        let g = self.screen.grids.get(&grid);
        let (h, w) = g.map(|g| (g.height.saturating_sub(1), g.width.saturating_sub(1))).unwrap_or((0, 0));
        (((row - gr).max(0.0) as u32).min(h), ((col - gc).max(0.0) as u32).min(w))
    }

    fn on_move(&mut self, event_loop: &ActiveEventLoop, pos: PhysicalPosition<f64>) {
        self.mouse.pos = pos;
        if self.mouse.pressed.is_none() {
            let hit = self.bar_hit(pos);
            let clickable = matches!(hit, Hit::Button(_) | Hit::Path(_) | Hit::Mark | Hit::Tool(..) | Hit::Chip(_));
            if self.bar.set_hover(clickable.then_some(hit)) {
                self.render(event_loop);
            }
            let icon = match self.edge(pos) {
                Some(ResizeDirection::North | ResizeDirection::South) => CursorIcon::NsResize,
                Some(ResizeDirection::East | ResizeDirection::West) => CursorIcon::EwResize,
                Some(ResizeDirection::NorthWest | ResizeDirection::SouthEast) => CursorIcon::NwseResize,
                Some(ResizeDirection::NorthEast | ResizeDirection::SouthWest) => CursorIcon::NeswResize,
                None if clickable => CursorIcon::Pointer,
                None if hit == Hit::Drag => CursorIcon::Default,
                // over a float (menus, pickers, modals) an arrow: those are things to point at, not text to edit
                None if self.over_float(pos) => CursorIcon::Default,
                None => CursorIcon::Text,
            };
            self.set_icon(icon);
            self.hover_nvim(pos, hit);
        }
        let Some((name, grid)) = self.mouse.pressed else { return };
        let Some((row, col)) = self.cell_at(pos) else { return };
        let (r, c) = self.local(grid, row, col);
        if self.mouse.last != Some((grid, r, c)) {
            self.mouse.last = Some((grid, r, c));
            self.send_mouse(name, "drag", grid, r, c);
        }
    }

    fn over_float(&self, pos: PhysicalPosition<f64>) -> bool {
        let Some((row, col)) = self.cell_at(pos) else { return false };
        let Some((grid, ..)) = self.screen.grid_at(row, col) else { return false };
        self.screen.layers().iter().any(|l| l.id == grid && l.floating)
    }

    /// Mouse moves for Neovim, so its menus, pickers and modals can follow the pointer (hover). Only while Neovim
    /// asks for them (`mousemoveevent`, which the config turns on in the windows that use it: other keys waiting, like
    /// which-key's, are never interrupted) and once per cell.
    fn hover_nvim(&mut self, pos: PhysicalPosition<f64>, bar: Hit) {
        let wanted = self.screen.options.get("mousemoveevent").and_then(Value::as_bool).unwrap_or(false);
        if !wanted || bar != Hit::Outside {
            return;
        }
        let Some((row, col)) = self.cell_at(pos) else { return };
        let Some(cell) = self.screen.grid_at(row, col) else { return };
        if self.mouse.hovered != Some(cell) {
            self.mouse.hovered = Some(cell);
            if self.mouse.hover_sent.is_some_and(|t| t.elapsed() < HOVER_WAIT) {
                self.mouse.hover_next = Some(cell);
            } else {
                self.send_hover(cell);
            }
        }
    }

    fn send_hover(&mut self, cell: (u64, u32, u32)) {
        self.mouse.hover_next = None;
        self.mouse.hover_sent = Some(Instant::now());
        self.send_mouse("move", "", cell.0, cell.1, cell.2);
    }

    /// The pointer's latest cell, if a hover waits for the previous one to be drawn.
    fn hover_flush(&mut self, drawn: bool) {
        if drawn {
            self.mouse.hover_sent = None;
        }
        if let Some(cell) = self.mouse.hover_next
            && !self.mouse.hover_sent.is_some_and(|t| t.elapsed() < HOVER_WAIT)
        {
            self.send_hover(cell);
        }
    }

    fn on_wheel(&mut self, delta: MouseScrollDelta) {
        let Some(m) = self.fonts.as_ref().map(|f| f.metrics) else { return };
        let (dx, dy) = match delta {
            MouseScrollDelta::LineDelta(x, y) => (x as f64, y as f64),
            MouseScrollDelta::PixelDelta(p) => (p.x / m.width as f64, p.y / m.height as f64),
        };
        self.mouse.scroll.0 += dx;
        self.mouse.scroll.1 += dy;
        let Some((row, col)) = self.cell_at(self.mouse.pos) else { return };
        let Some((grid, r, c)) = self.screen.grid_at(row, col) else { return };
        while self.mouse.scroll.1.abs() >= 1.0 {
            let up = self.mouse.scroll.1 > 0.0;
            self.mouse.scroll.1 -= self.mouse.scroll.1.signum();
            self.send_mouse("wheel", if up { "up" } else { "down" }, grid, r, c);
        }
        while self.mouse.scroll.0.abs() >= 1.0 {
            let left = self.mouse.scroll.0 > 0.0;
            self.mouse.scroll.0 -= self.mouse.scroll.0.signum();
            self.send_mouse("wheel", if left { "left" } else { "right" }, grid, r, c);
        }
    }

    /// Runs one of the config's app actions (`require("gui").action(name, col)`: menu, projects, home, history,
    /// welcome); `col` is the editor column under the button, where its menu opens.
    fn action(&self, name: &str, col: u32) {
        let _ = self.nvim.notify("nvim_exec_lua", vec!["require('gui').action(...)".into(), Value::Array(vec![name.into(), col.into()])]);
    }

    fn action_at(&self, name: &str, hit: Hit) {
        let col = match (&self.fonts, &self.window) {
            (Some(f), Some(w)) => {
                let x = self.bar.anchor(hit, &f.metrics, &f.small, w.inner_size().width as f32);
                ((x - self.origin.0) / f.metrics.width).max(0.0) as u32
            }
            _ => 0,
        };
        self.action(name, col);
    }

    /// What only the window can do, by name: from the shortcuts and from the config's menus.
    fn window_command(&mut self, name: &str) {
        let Some(w) = self.window.clone() else { return };
        match name {
            "fullscreen" => {
                let full = w.fullscreen().is_some();
                w.set_fullscreen((!full).then_some(winit::window::Fullscreen::Borderless(None)));
            }
            "maximize" => w.set_maximized(!w.is_maximized()),
            "minimize" => w.set_minimized(true),
            // Another window: the same binary, a fresh Neovim in the same folder (or the project the menu named).
            name if name == "new_window" || name.starts_with("new_window:") => {
                if let Ok(exe) = std::env::current_exe() {
                    let mut cmd = std::process::Command::new(exe);
                    if let Some(dir) = name.strip_prefix("new_window:") {
                        cmd.current_dir(dir);
                    }
                    let _ = cmd.spawn();
                }
            }
            // A fresh start (new languages, a changed setting that needs it): a new window in the same project, then
            // this one quits the way the close button does (Neovim asks about unsaved files).
            name if name.starts_with("restart:") => {
                if let Ok(exe) = std::env::current_exe() {
                    let mut cmd = std::process::Command::new(exe);
                    let dir = &name["restart:".len()..];
                    if !dir.is_empty() {
                        cmd.current_dir(dir);
                    }
                    if cmd.spawn().is_ok() {
                        let _ = self.nvim.notify("nvim_command", vec!["confirm qall".into()]);
                    }
                }
            }
            "zoom_in" => self.zoom(1.0),
            "zoom_out" => self.zoom(-1.0),
            "zoom_reset" => self.zoom(0.0),
            _ => {}
        }
    }

    /// Window-level shortcuts every desktop app has; true when consumed.
    fn shortcut(&mut self, key: &Key) -> bool {
        let ctrl = self.mods.control_key();
        let shift = self.mods.shift_key();
        let letter = |k: &str| matches!(key, Key::Character(c) if ctrl && shift && c.eq_ignore_ascii_case(k));
        let command = match key {
            Key::Named(NamedKey::F11) => Some("fullscreen"),
            Key::Named(NamedKey::Enter) if ctrl && shift => Some("maximize"),
            _ if letter("m") => Some("minimize"),
            _ if letter("n") => Some("new_window"),
            _ => None,
        };
        if let Some(c) = command {
            self.window_command(c);
            return true;
        }
        let action = match key {
            Key::Named(NamedKey::F10) => Some("menu"),
            _ if letter("o") => Some("open_project"),
            _ if letter("p") => Some("palette"),
            _ if letter("h") => Some("home"),
            _ if letter("r") => Some("history"),
            _ if letter("w") => Some("welcome"),
            _ => None,
        };
        if let Some(a) = action {
            // under its button when the toolbar has one (the menus open there), else at the left edge
            let hit = if a == "menu" { Hit::Mark } else { self.bar.find(a).unwrap_or(Hit::Outside) };
            self.action_at(a, hit);
            return true;
        }
        match key {
            Key::Character(c) if ctrl && shift && c.eq_ignore_ascii_case("v") => {
                if let Some(text) = self.clipboard.text() {
                    let _ = self.nvim.notify("nvim_paste", vec![text.into(), true.into(), (-1).into()]);
                }
                true
            }
            Key::Character(c) if ctrl && (c == "=" || c == "+") => {
                self.zoom(1.0);
                true
            }
            Key::Character(c) if ctrl && c == "-" => {
                self.zoom(-1.0);
                true
            }
            Key::Character(c) if ctrl && c == "0" => {
                self.zoom(0.0);
                true
            }
            _ => false,
        }
    }
}

impl ApplicationHandler<UserEvent> for App {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }
        // Snapshot runs (tests) always start the same: default size, no saved place.
        let saved = if self.scripted { platform::Saved::default() } else { platform::saved_window() };
        let (width, height) = saved.size.unwrap_or((1180.0, 760.0));
        let mut attrs = Window::default_attributes()
            .with_title("Leader")
            .with_inner_size(LogicalSize::new(width, height))
            .with_maximized(saved.maximized)
            .with_min_inner_size(LogicalSize::new(320.0, 200.0))
            // Our own app bar replaces the system's title bar (settings.gui.appbar.enabled = false brings it back).
            .with_decorations(!self.bar.state.enabled);
        // Back where it was, if that place is still on a screen (a monitor unplugged since would hide the window).
        if let Some((x, y)) = saved.position {
            let visible = event_loop.available_monitors().any(|m| {
                let (p, s) = (m.position(), m.size());
                x >= p.x - 40 && y >= p.y - 10 && x < p.x + s.width as i32 - 80 && y < p.y + s.height as i32 - 40
            });
            if visible {
                attrs = attrs.with_position(winit::dpi::PhysicalPosition::new(x, y));
            }
        }
        #[cfg(target_os = "linux")]
        let attrs = {
            use winit::platform::wayland::WindowAttributesExtWayland;
            WindowAttributesExtWayland::with_name(attrs, "leader", "leader")
        };
        let window = match event_loop.create_window(attrs) {
            Ok(w) => Arc::new(w),
            Err(e) => {
                eprintln!("leader: could not open a window: {e}");
                event_loop.exit();
                return;
            }
        };
        self.mark("window created");
        self.normal =
            platform::Saved { size: Some((width, height)), position: window.outer_position().ok().map(|p| (p.x, p.y)), maximized: false };
        let gpu_window = window.clone();
        let proxy = self.proxy.clone();
        std::thread::Builder::new()
            .name("gpu".into())
            .spawn(move || {
                let _ = proxy.send_event(UserEvent::Gpu(Box::new(Renderer::new(gpu_window, platform::backends()))));
            })
            .expect("gpu thread");
        let system = self.font_job.take().and_then(|j| j.join().ok()).unwrap_or_else(font::load_system);
        let families: Vec<String> = std::env::var("LEADER_FONT").ok().and_then(|f| parse_guifont(&f)).map(|(f, _)| f).unwrap_or_default();
        let fonts = Fonts::new(system, &families, font::DEFAULT_SIZE, window.scale_factor() as f32);
        self.mark(&format!("fonts ready: {} {}pt, cell {}x{}", fonts.family(), fonts.size, fonts.metrics.width, fonts.metrics.height));
        let family = fonts.family().to_string();
        self.fonts = Some(fonts);
        self.window = Some(window);
        // For the config's install checks (lua/gui/checks.lua).
        let _ = self.nvim.notify("nvim_set_var", vec!["leader_gui_font".into(), family.into()]);
        let _ = self.nvim.notify("nvim_set_var", vec!["leader_gui_version".into(), env!("CARGO_PKG_VERSION").into()]);
        // Wayland never tells a window where it is: the settings say "remember position" does nothing there.
        let placed = self.normal.position.is_some();
        let _ = self.nvim.notify("nvim_set_var", vec!["leader_gui_can_position".into(), placed.into()]);
        self.layout();
        if let Err(e) = self.nvim.attach(self.grid.0, self.grid.1) {
            eprintln!("leader: nvim_ui_attach failed: {e}");
            event_loop.exit();
            return;
        }
        let _ = self.nvim.notify("nvim_ui_set_focus", vec![true.into()]);
        self.mark(&format!("attached {}x{}", self.grid.0, self.grid.1));
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        // a hover that drew nothing (no flush came back) does not hold the next one for long
        self.hover_flush(false);
        if self.blink.tick(&self.screen) {
            self.render(event_loop);
        }
        if let Some(snap) = self.snapshot.as_mut()
            && snap.keys_at.is_some_and(|t| Instant::now() >= t)
        {
            snap.keys_at = None;
            if let Some(keys) = snap.keys.take() {
                let _ = self.nvim.input(&keys);
                self.input_at = Some(Instant::now());
            }
        }
        if self.snapshot.as_ref().and_then(|s| s.at).is_some_and(|at| Instant::now() >= at) {
            let snap = self.snapshot.take().unwrap();
            if let (Some(r), Some(fonts)) = (self.renderer.as_mut(), self.fonts.as_mut()) {
                let width = self.window.as_ref().map(|w| w.inner_size().width as f32).unwrap_or_default();
                let view =
                    View { origin: self.origin, focused: self.focused, cursor_on: true, bar: Some(&self.bar), width, scale: fonts.scale };
                let (w, h, rgba) = r.snapshot(&self.screen, fonts, &view);
                match write_png(&snap.path, w, h, &rgba) {
                    Ok(()) => eprintln!("leader: snapshot {w}x{h} written to {}", snap.path.display()),
                    Err(e) => eprintln!("leader: snapshot failed: {e}"),
                }
            }
            let _ = self.nvim.notify("nvim_command", vec!["qall!".into()]);
        }
        // Sleep until the next thing that has a time: a blink edge or a snapshot step. Nothing else wakes us
        // but Neovim and the window.
        // The bar's hover fades and the wave through the mark: frames only while they move (~60 fps), then idle.
        let anim = self.bar.animating().then(|| Instant::now() + self.bar.frame_interval());
        if anim.is_some() {
            self.render(event_loop);
        }
        let snap = self.snapshot.as_ref().and_then(|s| s.keys_at.or(s.at));
        let hover = self.mouse.hover_next.and(self.mouse.hover_sent).map(|t| t + HOVER_WAIT);
        let next = [self.blink.next, snap, anim, hover].into_iter().flatten().min();
        event_loop.set_control_flow(match next {
            Some(t) => ControlFlow::WaitUntil(t),
            None => ControlFlow::Wait,
        });
    }

    fn exiting(&mut self, _event_loop: &ActiveEventLoop) {
        // Snapshot runs (tests) never move the size a person chose.
        if let (Some(w), false) = (self.window.clone(), self.scripted) {
            self.note_normal();
            let keep = self.bar.state.keep;
            platform::save_window(&platform::Saved {
                size: self.normal.size.filter(|_| keep.size),
                position: self.normal.position.filter(|_| keep.position),
                maximized: keep.maximized && w.is_maximized(),
            });
        }
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: UserEvent) {
        match event {
            UserEvent::Nvim => self.drain_nvim(event_loop),
            UserEvent::Window(name) => self.window_command(&name),
            UserEvent::Appbar(v) => {
                let next = appbar::State::from_value(&v);
                let old = &self.bar.state;
                let geometry =
                    (next.enabled, next.height, next.pad_x, next.pad_bottom) != (old.enabled, old.height, old.pad_x, old.pad_bottom);
                if next.enabled != old.enabled
                    && let Some(w) = &self.window
                {
                    w.set_decorations(!next.enabled);
                }
                if next != self.bar.state {
                    self.bar.set_state(next);
                    if geometry {
                        self.relayout();
                    }
                    self.render(event_loop);
                }
            }
            UserEvent::Gpu(result) => match *result {
                Ok(renderer) => {
                    self.mark(&format!("gpu ready: {}", renderer.adapter_info));
                    let _ = self.nvim.notify("nvim_set_var", vec!["leader_gui_gpu".into(), renderer.adapter_info.as_str().into()]);
                    self.renderer = Some(renderer);
                    if let (Some(r), Some(w)) = (self.renderer.as_mut(), &self.window) {
                        let size = w.inner_size();
                        r.resize(size.width, size.height);
                    }
                    self.redraw();
                }
                Err(e) => {
                    eprintln!("leader: no usable GPU: {e}");
                    event_loop.exit();
                }
            },
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => {
                let _ = self.nvim.notify("nvim_command", vec!["confirm qall".into()]);
            }
            WindowEvent::Resized(size) => {
                if let Some(r) = self.renderer.as_mut() {
                    r.resize(size.width, size.height);
                }
                self.bar.maximized = self.window.as_ref().is_some_and(|w| w.is_maximized());
                self.note_normal();
                self.relayout();
            }
            WindowEvent::Moved(_) => self.note_normal(),
            WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                if let Some(fonts) = self.fonts.as_mut() {
                    let (families, size) = (vec![fonts.family().to_string()], fonts.size);
                    fonts.set(&families, size, scale_factor as f32);
                }
                if let Some(r) = self.renderer.as_mut() {
                    r.clear_glyphs();
                }
                self.relayout();
            }
            WindowEvent::RedrawRequested => self.render(event_loop),
            WindowEvent::Focused(focused) => {
                self.focused = focused;
                self.bar.focused = focused;
                self.blink.reset(&self.screen, focused);
                let _ = self.nvim.notify("nvim_ui_set_focus", vec![focused.into()]);
                self.redraw();
            }
            WindowEvent::ModifiersChanged(m) => self.mods = m.state(),
            WindowEvent::KeyboardInput { event, .. } => {
                if event.state != ElementState::Pressed {
                    return;
                }
                if self.shortcut(&event.logical_key) {
                    return;
                }
                if let Key::Named(NamedKey::Shift | NamedKey::Control | NamedKey::Alt | NamedKey::Super) = event.logical_key {
                    return;
                }
                if let Some(keys) = input::key(&event.logical_key, event.text.as_deref(), self.mods) {
                    let _ = self.nvim.input(&keys);
                    self.input_at.get_or_insert_with(Instant::now);
                }
            }
            WindowEvent::CursorMoved { position, .. } => self.on_move(event_loop, position),
            WindowEvent::CursorLeft { .. } => {
                if self.bar.set_hover(None) {
                    self.render(event_loop);
                }
            }
            WindowEvent::MouseInput { state, button, .. } => {
                let consumed = self.mouse.pressed.is_none() && self.on_chrome(event_loop, state, button);
                if !consumed && self.screen.mouse {
                    self.on_button(state, button);
                }
            }
            WindowEvent::MouseWheel { delta, .. } => {
                if self.screen.mouse {
                    self.on_wheel(delta);
                }
            }
            WindowEvent::DroppedFile(path) => {
                let code = "vim.cmd.drop(vim.fn.fnameescape(...))";
                let _ = self.nvim.notify("nvim_exec_lua", vec![code.into(), Value::Array(vec![path.to_string_lossy().as_ref().into()])]);
            }
            WindowEvent::Destroyed => event_loop.exit(),
            _ => {}
        }
    }
}

fn write_png(path: &std::path::Path, w: u32, h: u32, rgba: &[u8]) -> Result<(), String> {
    let file = std::fs::File::create(path).map_err(|e| e.to_string())?;
    let mut enc = png::Encoder::new(std::io::BufWriter::new(file), w, h);
    enc.set_color(png::ColorType::Rgba);
    enc.set_depth(png::BitDepth::Eight);
    let mut writer = enc.write_header().map_err(|e| e.to_string())?;
    writer.write_image_data(rgba).map_err(|e| e.to_string())
}
