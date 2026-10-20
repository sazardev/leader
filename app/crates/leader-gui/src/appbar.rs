//! The app bar: our own title bar, part of the editor rather than a frame around it. It is painted with the
//! editor's own background and steps back (its content fades) while a modal is open. Like Zed's: Leader's mark
//! opens the app menu (a wave runs through its dots on hover); then the tools the config chose for the left (the
//! project's name, home, recent files…); the current file as a centered, clickable path; on the right what is
//! happening right now (LSP progress, installs, a save; a dot spinner and a thin progress line), the chips the
//! config chose, the tools for the right (theme, agent, terminal…) and the window controls as three small flat
//! squares. Every tool says what it does in a tooltip after a moment under the pointer; a right click on the bar
//! customizes it. The config decides the content and what each tool opens (`lua/gui/` sends it as
//! `leader_appbar` over RPC; the menus are its own flat floats).
use std::time::{Duration, Instant};

use rmpv::Value;

use crate::font::{CellMetrics, Fonts};
use crate::scene::{self, AtlasFull, Glyphs, Quad};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Colors {
    pub fg: u32,
    pub dim: u32,
    pub faint: u32,
    /// The mark's dots (the brand's green on dark themes).
    pub mark: u32,
    pub accent: u32,
    pub green: u32,
    pub yellow: u32,
    pub red: u32,
    pub on: u32,
}

/// A piece of information on the right: text in a color, optionally on a solid pill.
#[derive(Debug, Clone, PartialEq)]
pub struct Chip {
    pub text: String,
    pub fg: Option<u32>,
    pub bg: Option<u32>,
    /// Cells of space before it (chips of one group sit closer).
    pub gap: f32,
    /// Clicking it runs this action of the config (`require("gui").action(name)`); None = just information.
    pub action: Option<String>,
}

/// A button of the toolbar: an icon, optionally a label (then a ▾ when it opens a menu), what it does.
#[derive(Debug, Clone, PartialEq)]
pub struct Tool {
    pub icon: String,
    pub label: Option<String>,
    /// Shown under the pointer after a moment ("Theme", "Agent · claude/sonnet").
    pub tip: Option<String>,
    /// The config's action (`require("gui").action(name, col)`).
    pub action: String,
    /// It opens a menu (a ▾ after its label).
    pub menu: bool,
    /// Lit like a toggle that is on (the file tree is open…).
    pub active: bool,
}

/// Something running (LSP indexing, an install) or just finished (`done`: a check instead of the spinner).
#[derive(Debug, Clone, PartialEq)]
pub struct Activity {
    pub text: String,
    /// 0..=100 when known: the progress line under the bar fills to it.
    pub percent: Option<f32>,
    pub done: bool,
}

/// What the config last sent.
#[derive(Debug, Clone, PartialEq)]
pub struct State {
    pub enabled: bool,
    /// In text lines.
    pub height: f32,
    /// Logical px around the editor (0 = edge to edge).
    pub pad_x: f32,
    pub pad_bottom: f32,
    /// Window controls on the left (false = right, the default).
    pub controls_left: bool,
    pub show_mark: bool,
    /// The tools after the mark and before the window controls, in order.
    pub left: Vec<Tool>,
    pub right: Vec<Tool>,
    /// Folders of the current file's path, then the file itself.
    pub path: Vec<String>,
    pub file: String,
    pub modified: bool,
    pub chips: Vec<Chip>,
    pub activity: Option<Activity>,
    pub colors: Option<Colors>,
}

impl Default for State {
    fn default() -> Self {
        State {
            enabled: true,
            height: 1.5,
            pad_x: 0.0,
            pad_bottom: 0.0,
            controls_left: false,
            show_mark: true,
            left: Vec::new(),
            right: Vec::new(),
            path: Vec::new(),
            file: String::new(),
            modified: false,
            chips: Vec::new(),
            activity: None,
            colors: None,
        }
    }
}

fn hex(v: Option<&Value>) -> Option<u32> {
    u32::from_str_radix(v?.as_str()?.trim_start_matches('#'), 16).ok()
}

fn get<'a>(map: &'a Value, key: &str) -> Option<&'a Value> {
    map.as_map()?.iter().find(|(k, _)| k.as_str() == Some(key)).map(|(_, v)| v)
}

fn float(v: Option<&Value>) -> Option<f32> {
    v.and_then(|v| v.as_f64().or_else(|| v.as_i64().map(|i| i as f64))).map(|f| f as f32)
}

fn flag(v: &Value, k: &str, def: bool) -> bool {
    get(v, k).and_then(Value::as_bool).unwrap_or(def)
}

fn string(v: &Value, k: &str) -> Option<String> {
    get(v, k).and_then(Value::as_str).filter(|s| !s.is_empty()).map(String::from)
}

fn tools(v: &Value, k: &str) -> Vec<Tool> {
    get(v, k)
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .filter_map(|t| {
                    Some(Tool {
                        icon: string(t, "icon").unwrap_or_default(),
                        label: string(t, "label"),
                        tip: string(t, "tip"),
                        action: string(t, "action")?,
                        menu: flag(t, "menu", false),
                        active: flag(t, "active", false),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

impl State {
    pub fn from_value(v: &Value) -> State {
        let d = State::default();
        let strings = |k: &str| -> Vec<String> {
            get(v, k).and_then(Value::as_array).map(|a| a.iter().filter_map(|s| s.as_str().map(String::from)).collect()).unwrap_or_default()
        };
        let colors = get(v, "colors").and_then(|c| {
            let h = |k| hex(get(c, k));
            Some(Colors {
                fg: h("fg")?,
                dim: h("dim")?,
                faint: h("faint")?,
                mark: h("mark").or(h("accent"))?,
                accent: h("accent")?,
                green: h("green").or(h("accent"))?,
                yellow: h("yellow")?,
                red: h("red")?,
                on: h("on")?,
            })
        });
        let chips = get(v, "chips")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|c| {
                        Some(Chip {
                            text: get(c, "text")?.as_str()?.to_string(),
                            fg: hex(get(c, "fg")),
                            bg: hex(get(c, "bg")),
                            gap: float(get(c, "gap")).unwrap_or(2.0).clamp(0.0, 8.0),
                            action: get(c, "action").and_then(Value::as_str).map(String::from),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        let activity = get(v, "activity").and_then(|a| {
            Some(Activity {
                text: get(a, "text")?.as_str()?.to_string(),
                percent: float(get(a, "percent")).map(|p| p.clamp(0.0, 100.0)),
                done: flag(a, "done", false),
            })
        });
        let padding = get(v, "padding");
        let pad = |k: &str, def: f32| padding.and_then(|p| float(get(p, k))).unwrap_or(def).clamp(0.0, 200.0);
        State {
            enabled: flag(v, "enabled", true),
            height: float(get(v, "height")).unwrap_or(d.height).clamp(1.2, 4.0),
            pad_x: pad("x", d.pad_x),
            pad_bottom: pad("bottom", d.pad_bottom),
            controls_left: get(v, "controls").and_then(Value::as_str) == Some("left"),
            show_mark: flag(v, "mark", true),
            left: tools(v, "left"),
            right: tools(v, "right"),
            path: strings("path"),
            file: get(v, "file").and_then(Value::as_str).unwrap_or_default().to_string(),
            modified: flag(v, "modified", false),
            chips,
            activity,
            colors,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Button {
    Close,
    Minimize,
    Maximize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hit {
    Outside,
    Drag,
    Button(Button),
    /// The mark: the app menu.
    Mark,
    /// A tool of the left or the right side.
    Tool(Side, usize),
    /// A part of the path: index into the folders, `path.len()` = the file.
    Path(usize),
    /// A chip that has an action.
    Chip(usize),
}

/// Hover backgrounds fade in, the wave runs through the mark, the bar steps back for a modal, activity comes and goes,
/// a tooltip waits a moment before it shows.
const FADE: Duration = Duration::from_millis(140);
const WAVE: Duration = Duration::from_millis(900);
const STEP_BACK: Duration = Duration::from_millis(180);
const ACTIVITY_FADE: Duration = Duration::from_millis(260);
const TIP_DELAY: Duration = Duration::from_millis(550);

pub struct Bar {
    pub state: State,
    hover: Option<Hit>,
    hover_at: Instant,
    /// When the pointer entered the mark: the wave runs from there.
    wave_at: Option<Instant>,
    /// A modal (a big float: Telescope, the welcome screen…) is open, since when.
    modal: bool,
    modal_at: Instant,
    /// The activity on screen and when it appeared; the last one stays while it fades out.
    shown: Option<Activity>,
    shown_at: Instant,
    gone_at: Option<Instant>,
    pub maximized: bool,
    pub focused: bool,
}

impl Default for Bar {
    fn default() -> Self {
        let long_ago = Instant::now() - Duration::from_secs(10);
        Bar {
            state: State::default(),
            hover: None,
            hover_at: long_ago,
            wave_at: None,
            modal: false,
            modal_at: long_ago,
            shown: None,
            shown_at: long_ago,
            gone_at: None,
            maximized: false,
            focused: true,
        }
    }
}

/// Colors before the config has spoken: from Neovim's default colors, so the first frame already fits.
fn fallback(fg: u32, bg: u32) -> Colors {
    Colors {
        fg,
        dim: mix(bg, fg, 0.62),
        faint: mix(bg, fg, 0.34),
        mark: 0xb8bb26,
        accent: 0x8ec07c,
        green: 0xb8bb26,
        yellow: 0xfabd2f,
        red: 0xfb4934,
        on: bg,
    }
}

pub fn mix(a: u32, b: u32, t: f32) -> u32 {
    let ch = |s: u32| {
        let (x, y) = (((a >> s) & 0xff) as f32, ((b >> s) & 0xff) as f32);
        ((x + (y - x) * t.clamp(0.0, 1.0)).round() as u32) << s
    };
    ch(16) | ch(8) | ch(0)
}

fn ease(t: f32) -> f32 {
    1.0 - (1.0 - t.clamp(0.0, 1.0)).powi(3)
}

fn progress(since: Instant, d: Duration) -> f32 {
    since.elapsed().as_secs_f32() / d.as_secs_f32()
}

/// East Asian wide characters take two cells, like in the grid.
fn cells(s: &str) -> usize {
    s.chars()
        .map(|c| {
            if matches!(c as u32, 0x1100..=0x115F | 0x2E80..=0xA4CF | 0xAC00..=0xD7A3 | 0xF900..=0xFAFF | 0xFF00..=0xFF60) { 2 } else { 1 }
        })
        .sum()
}

/// Draws a string on the bar's text row, one cell per character; returns the width used.
#[allow(clippy::too_many_arguments)]
fn text(
    out: &mut Vec<Quad>,
    fonts: &mut Fonts,
    glyphs: &mut Glyphs,
    m: CellMetrics,
    s: &str,
    x: f32,
    y: f32,
    color: u32,
    bold: bool,
) -> Result<f32, AtlasFull> {
    let mut cx = x;
    for ch in s.chars() {
        let mut buf = [0u8; 4];
        let g = ch.encode_utf8(&mut buf);
        if ch != ' ' {
            scene::cell_text(out, fonts, glyphs, m, g, bold, false, cx, y, scene::rgb(color, 1.0), true)?;
        }
        cx += m.width * cells(g) as f32;
    }
    Ok(cx - x)
}

const SEP: &str = " › ";
const DONE_ICON: &str = "\u{f00c}";
const CHEVRON: &str = "\u{f107}";

/// A dot of the mark: center x, y (brand units), column, row.
pub type Dot = (f32, f32, usize, usize);

/// The brand's mark at small sizes (`brand/dots.js` "classicN", what its favicon uses): an N of 5×7 dots,
/// pitch 10, radius 4.1. Returns the dot centers in brand units with their column and row, and the size (50×70).
/// The big icon uses the heavy N (`assets/leader.svg`); at the bar's ~20 px the classic one stays crisp.
pub fn mark_dots() -> (Vec<Dot>, f32, f32) {
    const N: [&str; 7] = ["X...X", "XX..X", "X.X.X", "X.X.X", "X..XX", "X...X", "X...X"];
    let pitch = 10.0;
    let mut dots = Vec::new();
    for (r, row) in N.iter().enumerate() {
        for (c, ch) in row.chars().enumerate() {
            if ch == 'X' {
                dots.push((c as f32 * pitch + pitch / 2.0, r as f32 * pitch + pitch / 2.0, c, r));
            }
        }
    }
    (dots, 5.0 * pitch, 7.0 * pitch)
}

const DOT_RADIUS: f32 = 4.1;
const COLS: f32 = 4.0;
const ROWS: f32 = 6.0;

/// One drawn part of the path.
#[derive(Debug, Clone, PartialEq)]
struct Part {
    /// Index of the folder, `path.len()` = the file; None = the "…" standing in for folders that do not fit.
    index: Option<usize>,
    label: String,
    x: f32,
    w: f32,
}

/// Where everything sits, computed once for drawing and for the mouse.
struct Layout {
    h: f32,
    ty: f32,
    /// The three controls: center x, center y, radius.
    controls: [(Button, f32, f32, f32); 3],
    mark: Option<(f32, f32, f32)>,
    /// Each tool's x and width, side by side.
    left: Vec<(f32, f32)>,
    right: Vec<(f32, f32)>,
    parts: Vec<Part>,
    /// The right side: each chip's x and width; the activity sits before them.
    chips: Vec<(f32, f32)>,
    activity_x: f32,
}

impl Bar {
    pub fn height(&self, m: &CellMetrics) -> f32 {
        if self.state.enabled { (m.height * self.state.height).round() } else { 0.0 }
    }

    pub fn colors(&self, fg: u32, bg: u32) -> Colors {
        self.state.colors.unwrap_or_else(|| fallback(fg, bg))
    }

    /// The tool that runs `action` (for the shortcuts that open the same menus under their button).
    pub fn find(&self, action: &str) -> Option<Hit> {
        let pos = |list: &[Tool]| list.iter().position(|t| t.action == action);
        pos(&self.state.left).map(|i| Hit::Tool(Side::Left, i)).or_else(|| pos(&self.state.right).map(|i| Hit::Tool(Side::Right, i)))
    }

    pub fn tool(&self, side: Side, i: usize) -> Option<&Tool> {
        match side {
            Side::Left => self.state.left.get(i),
            Side::Right => self.state.right.get(i),
        }
    }

    /// The pointer moved onto something else; true when the bar must be drawn again.
    pub fn set_hover(&mut self, hover: Option<Hit>) -> bool {
        if hover == self.hover {
            return false;
        }
        if hover == Some(Hit::Mark) {
            self.wave_at = Some(Instant::now());
        }
        // moving between the three controls keeps them lit: no new fade
        let controls = |h: Option<Hit>| matches!(h, Some(Hit::Button(_)));
        if !(controls(hover) && controls(self.hover)) {
            self.hover_at = Instant::now();
        }
        self.hover = hover;
        true
    }

    /// A modal opened or closed: the bar steps back or forward. True when that changed.
    pub fn set_modal(&mut self, modal: bool) -> bool {
        if modal == self.modal {
            return false;
        }
        self.modal = modal;
        self.modal_at = Instant::now();
        true
    }

    /// The config sent a new state: keeps the activity's fade in/out going across updates.
    pub fn set_state(&mut self, state: State) {
        match (&self.shown, &state.activity) {
            (None, Some(a)) => {
                self.shown = Some(a.clone());
                self.shown_at = Instant::now();
                self.gone_at = None;
            }
            (Some(_), Some(a)) => {
                if self.gone_at.is_some() {
                    self.shown_at = Instant::now();
                }
                self.shown = Some(a.clone());
                self.gone_at = None;
            }
            (Some(_), None) if self.gone_at.is_none() => self.gone_at = Some(Instant::now()),
            _ => {}
        }
        self.state = state;
    }

    /// What the tooltip under the pointer says, if one is due.
    fn tip(&self) -> Option<String> {
        match self.hover? {
            Hit::Tool(side, i) => self.tool(side, i).and_then(|t| t.tip.clone()),
            Hit::Mark => Some("Menu · F10".into()),
            Hit::Button(Button::Minimize) => Some("Minimize".into()),
            Hit::Button(Button::Maximize) => Some(if self.maximized { "Restore" } else { "Maximize" }.into()),
            Hit::Button(Button::Close) => Some("Close".into()),
            _ => None,
        }
    }

    /// Something is moving (a fade, the wave, a spinner, a tooltip about to show): the next frame is needed soon.
    pub fn animating(&mut self) -> bool {
        if self.gone_at.is_some_and(|t| t.elapsed() >= ACTIVITY_FADE) {
            self.shown = None;
            self.gone_at = None;
        }
        let busy = self.shown.as_ref().is_some_and(|a| !a.done);
        let tip_coming = self.tip().is_some() && self.hover_at.elapsed() < TIP_DELAY + FADE;
        self.hover_at.elapsed() < FADE
            || self.modal_at.elapsed() < STEP_BACK
            || self.wave_at.is_some_and(|t| t.elapsed() < WAVE)
            || self.shown.is_some() && (self.shown_at.elapsed() < ACTIVITY_FADE || self.gone_at.is_some())
            || busy
            || tip_coming
    }

    /// Frames for a spinner need less than the fades: ~30 per second is smooth for dots.
    pub fn frame_interval(&self) -> Duration {
        let fading =
            self.hover_at.elapsed() < FADE || self.modal_at.elapsed() < STEP_BACK || self.wave_at.is_some_and(|t| t.elapsed() < WAVE);
        Duration::from_millis(if fading { 16 } else { 33 })
    }

    fn activity_width(&self, m: &CellMetrics) -> f32 {
        self.shown.as_ref().map_or(0.0, |a| (cells(&a.text) as f32 + 4.0) * m.width)
    }

    fn chips_width(&self, m: &CellMetrics) -> f32 {
        self.state.chips.iter().map(|c| (c.gap + cells(&c.text) as f32 + if c.bg.is_some() { 2.0 } else { 0.0 }) * m.width).sum()
    }

    fn tool_width(t: &Tool, m: &CellMetrics) -> f32 {
        match &t.label {
            // icon (if any), the label, a ▾ for a menu, a cell of air on each side
            Some(label) => {
                let icon = if t.icon.is_empty() { 0.0 } else { cells(&t.icon) as f32 + 1.0 };
                ((icon + cells(label) as f32 + if t.menu { 2.0 } else { 0.0 } + 2.0) * m.width).round()
            }
            None => (m.width * 2.4).round(),
        }
    }

    /// `line` = the editor's metrics (the bar's height is counted in its lines), `m` = the bar's own smaller text.
    fn layout(&self, line: &CellMetrics, m: &CellMetrics, width: f32) -> Layout {
        let h = self.height(line);
        let ty = ((h - m.height) / 2.0).round();
        let s = &self.state;
        // the controls: three small flat squares, minimize · maximize · close (r = half the side)
        let r = (h * 0.17).round().max(4.0);
        let gap = (r * 0.9).round();
        let group = 6.0 * r + 2.0 * gap;
        let edge = (m.width * 1.1).round();
        let gx = if s.controls_left { edge } else { width - edge - group };
        let cy = (h / 2.0).round();
        let at = |i: f32| gx + r + i * (2.0 * r + gap);
        let controls = if s.controls_left {
            [(Button::Close, at(0.0), cy, r), (Button::Minimize, at(1.0), cy, r), (Button::Maximize, at(2.0), cy, r)]
        } else {
            [(Button::Minimize, at(0.0), cy, r), (Button::Maximize, at(1.0), cy, r), (Button::Close, at(2.0), cy, r)]
        };

        let mut x = if s.controls_left { gx + group + (m.width * 1.6).round() } else { edge };
        let (_, bw, bh) = mark_dots();
        let mark = s.show_mark.then(|| {
            let mh = (h * 0.56).round();
            let my = ((h - mh) / 2.0).round();
            let at = (x, my, mh);
            x += (mh * bw / bh).round() + (m.width * 1.0).round();
            at
        });
        let left = s
            .left
            .iter()
            .map(|t| {
                let w = Self::tool_width(t, m);
                let at = (x, w);
                x += w;
                at
            })
            .collect();
        let left_end = x + m.width;

        let right_end = if s.controls_left { width - edge } else { gx - m.width * 1.2 };
        let tools_w: f32 = s.right.iter().map(|t| Self::tool_width(t, m)).sum();
        let mut tx = right_end - tools_w;
        let right = s
            .right
            .iter()
            .map(|t| {
                let w = Self::tool_width(t, m);
                let at = (tx, w);
                tx += w;
                at
            })
            .collect();
        let mut cx = right_end - tools_w - self.chips_width(m) - if s.right.is_empty() { 0.0 } else { m.width * 0.5 };
        let activity_x = cx - self.activity_width(m);
        let chips = s
            .chips
            .iter()
            .map(|c| {
                cx += c.gap * m.width;
                let w = (cells(&c.text) as f32 + if c.bg.is_some() { 2.0 } else { 0.0 }) * m.width;
                let at = (cx, w);
                cx += w;
                at
            })
            .collect();
        let right_start = activity_x - m.width;

        Layout { h, ty, controls, mark, left, right, parts: self.parts(m, width, left_end, right_start), chips, activity_x }
    }

    /// The path centered on the window when it fits between the sides; leading folders give way to "…" when not.
    fn parts(&self, m: &CellMetrics, width: f32, left: f32, right: f32) -> Vec<Part> {
        if self.state.file.is_empty() || right <= left {
            return Vec::new();
        }
        let folders = &self.state.path;
        let sep = cells(SEP) as f32 * m.width;
        let file_w = (cells(&self.state.file) + if self.state.modified { 2 } else { 0 }) as f32 * m.width;
        for skip in 0..=folders.len() {
            let mut labels: Vec<(Option<usize>, String, f32)> = Vec::new();
            if skip > 0 {
                labels.push((None, "…".into(), m.width));
            }
            for (i, f) in folders.iter().enumerate().skip(skip) {
                labels.push((Some(i), f.clone(), cells(f) as f32 * m.width));
            }
            labels.push((Some(folders.len()), self.state.file.clone(), file_w));
            let total: f32 = labels.iter().map(|l| l.2).sum::<f32>() + sep * (labels.len() - 1) as f32;
            if total <= right - left || skip == folders.len() {
                let mut x = ((width - total) / 2.0).max(left).min(right - total).round();
                return labels
                    .into_iter()
                    .map(|(index, label, w)| {
                        let p = Part { index, label, x, w };
                        x += w + sep;
                        p
                    })
                    .collect();
            }
        }
        Vec::new()
    }

    pub fn hit(&self, x: f32, y: f32, width: f32, line: &CellMetrics, m: &CellMetrics) -> Hit {
        let l = self.layout(line, m, width);
        if !self.state.enabled || y < 0.0 || y >= l.h {
            return Hit::Outside;
        }
        for (b, cx, _, r) in l.controls {
            if (x - cx).abs() <= r + 3.0 {
                return Hit::Button(b);
            }
        }
        let (_, bw, bh) = mark_dots();
        if let Some((mx, _, mh)) = l.mark
            && x >= mx - m.width * 0.5
            && x < mx + mh * bw / bh + m.width * 0.5
        {
            return Hit::Mark;
        }
        for (side, list) in [(Side::Left, &l.left), (Side::Right, &l.right)] {
            for (i, (tx, w)) in list.iter().enumerate() {
                if x >= *tx && x < tx + w {
                    return Hit::Tool(side, i);
                }
            }
        }
        let pad = m.width * 0.5;
        for (i, (cx, w)) in l.chips.iter().enumerate() {
            if self.state.chips[i].action.is_some() && x >= cx - pad && x < cx + w + pad {
                return Hit::Chip(i);
            }
        }
        for p in l.parts {
            if let Some(i) = p.index
                && x >= p.x - pad
                && x < p.x + p.w + pad
            {
                return Hit::Path(i);
            }
        }
        Hit::Drag
    }

    /// Where a button starts, in px: menus open right under it.
    pub fn anchor(&self, hit: Hit, line: &CellMetrics, m: &CellMetrics, width: f32) -> f32 {
        let l = self.layout(line, m, width);
        match hit {
            Hit::Mark => l.mark.map(|(x, ..)| x),
            Hit::Tool(Side::Left, i) => l.left.get(i).map(|(x, _)| *x),
            Hit::Tool(Side::Right, i) => l.right.get(i).map(|(x, _)| *x),
            Hit::Chip(i) => l.chips.get(i).map(|(x, _)| *x),
            _ => None,
        }
        .unwrap_or(0.0)
    }

    /// 0..1: how far the hover background of `hit` has faded in.
    fn lit(&self, hit: Hit) -> f32 {
        if self.hover != Some(hit) {
            return 0.0;
        }
        ease(progress(self.hover_at, FADE))
    }

    /// Paints the bar across the top of a `width` px window, on the editor's background `bg`.
    #[allow(clippy::too_many_arguments)]
    pub fn draw(
        &self,
        out: &mut Vec<Quad>,
        fonts: &mut Fonts,
        glyphs: &mut Glyphs,
        width: f32,
        fg: u32,
        bg: u32,
        scale: f32,
    ) -> Result<(), AtlasFull> {
        if !self.state.enabled {
            return Ok(());
        }
        let (line, m) = (fonts.metrics, fonts.small);
        let c = self.colors(fg, bg);
        let l = self.layout(&line, &m, width);
        let (h, ty) = (l.h, l.ty);
        let hover_bg = mix(bg, c.fg, 0.09);
        let quad = |x: f32, y: f32, w: f32, hh: f32, col: u32, alpha: f32, kind: u32| Quad {
            pos: [x, y],
            size: [w, hh],
            uv: [scale, 0.0],
            color: scene::rgb(col, alpha),
            kind,
        };
        let rect = |x: f32, y: f32, w: f32, hh: f32, col: u32| quad(x, y, w, hh, col, 1.0, scene::RECT);
        out.push(rect(0.0, 0.0, width, h, bg));

        // A modal steps the bar back: everything on it fades toward the background (unfocused does too).
        let step = ease(progress(self.modal_at, STEP_BACK));
        let back = if self.modal { step } else { 1.0 - step };
        let quiet = if self.focused { 0.55 * back } else { 0.6 };
        let ink = |col: u32| mix(col, bg, quiet);
        let (fg, dim, faint) = (ink(c.fg), ink(c.dim), ink(c.faint));

        // Window controls: quiet squares; hovering the group colors them and shows what each does.
        let group_lit = [Button::Close, Button::Minimize, Button::Maximize].iter().map(|b| self.lit(Hit::Button(*b))).fold(0.0, f32::max);
        let group_lit =
            if matches!(self.hover, Some(Hit::Button(_))) { group_lit.max(ease(progress(self.hover_at, FADE))) } else { group_lit };
        for (b, cx, cy, r) in l.controls {
            let color = match b {
                Button::Close => c.red,
                Button::Minimize => c.yellow,
                Button::Maximize => c.green,
            };
            let dot = mix(mix(bg, c.fg, 0.22), color, group_lit);
            out.push(rect((cx - r).round(), (cy - r).round(), 2.0 * r, 2.0 * r, ink(dot)));
            if group_lit > 0.0 {
                let sym = mix(color, bg, 0.72);
                let s = r.round();
                let stroke = scale.max(1.0).round();
                let bar_h = |out: &mut Vec<Quad>| {
                    out.push(quad((cx - s / 2.0).round(), (cy - stroke / 2.0).round(), s, stroke, sym, group_lit, scene::RECT))
                };
                match b {
                    Button::Close => out.push(quad(cx - s / 2.0, cy - s / 2.0, s, s, sym, group_lit, scene::CROSS)),
                    Button::Minimize => bar_h(out),
                    Button::Maximize if self.maximized => bar_h(out),
                    Button::Maximize => {
                        bar_h(out);
                        out.push(quad((cx - stroke / 2.0).round(), (cy - s / 2.0).round(), stroke, s, sym, group_lit, scene::RECT));
                    }
                }
            }
        }

        // The mark. On hover a wave runs through the dots from the bottom left: they swell and warm up, then settle.
        let block_h = (h * 0.72).round();
        let block_y = ((h - block_h) / 2.0).round();
        if let Some((mx, my, mh)) = l.mark {
            let (dots, _, bh) = mark_dots();
            let s = mh / bh;
            let wave = self.wave_at.map(|t| progress(t, WAVE)).filter(|p| *p < 1.0);
            let base = if self.focused { c.mark } else { c.faint };
            for (x, y, col, row) in dots {
                let bump = wave.map_or(0.0, |p| {
                    let d = (col as f32 / COLS + (ROWS - row as f32) / ROWS) / 2.0;
                    let k = (p * 1.5 - 0.25 - d) / 0.13;
                    (-k * k).exp()
                });
                let r = DOT_RADIUS * s * (1.0 + 0.45 * bump);
                out.push(quad(mx + x * s - r, my + y * s - r, 2.0 * r, 2.0 * r, ink(mix(base, c.yellow, bump)), 1.0, scene::CIRCLE));
            }
        }

        // The tools: an icon (and a label with ▾ for a menu) on a block that fades in on hover; an active one stays lit.
        for (side, list, places) in [(Side::Left, &self.state.left, &l.left), (Side::Right, &self.state.right, &l.right)] {
            for (i, (t, (x, w))) in list.iter().zip(places.iter()).enumerate() {
                let lit = self.lit(Hit::Tool(side, i)).max(if t.active { 0.55 } else { 0.0 });
                if lit > 0.0 {
                    out.push(quad(*x, block_y, *w, block_h, hover_bg, lit, scene::RECT));
                }
                let ink_t = if t.active { mix(dim, c.accent, 0.8) } else { mix(faint, fg, lit) };
                match &t.label {
                    Some(label) => {
                        let mut tx = x + m.width;
                        if !t.icon.is_empty() {
                            tx += text(out, fonts, glyphs, m, &t.icon, tx, ty, ink_t, false)? + m.width;
                        }
                        tx += text(out, fonts, glyphs, m, label, tx, ty, mix(dim, fg, 0.6 + 0.4 * lit), true)?;
                        if t.menu {
                            text(out, fonts, glyphs, m, CHEVRON, tx + (m.width * 0.4).round(), ty, mix(faint, fg, lit), false)?;
                        }
                    }
                    None => {
                        text(out, fonts, glyphs, m, &t.icon, (x + (w - m.width) / 2.0).round(), ty, ink_t, false)?;
                    }
                }
            }
        }

        // The path, centered: folders dimmed, the file bright; the part under the pointer gets a block behind it.
        let folders = self.state.path.len();
        for (n, p) in l.parts.iter().enumerate() {
            if n > 0 {
                text(out, fonts, glyphs, m, SEP, p.x - cells(SEP) as f32 * m.width, ty, faint, false)?;
            }
            let lit = p.index.map_or(0.0, |i| self.lit(Hit::Path(i)));
            if lit > 0.0 {
                let pad = (m.width * 0.5).round();
                out.push(quad(p.x - pad, block_y, p.w + 2.0 * pad, block_h, hover_bg, lit, scene::RECT));
            }
            let is_file = p.index == Some(folders);
            let color = if is_file { fg } else { mix(dim, fg, lit) };
            let x = p.x + text(out, fonts, glyphs, m, &p.label, p.x, ty, color, is_file)?;
            if is_file && self.state.modified {
                text(out, fonts, glyphs, m, " ●", x, ty, ink(c.accent), false)?;
            }
        }

        // What is happening right now: a spinner of three dots (or a check when done), the text, and the progress
        // line along the bottom edge. Fades in when it starts and out when it ends.
        if let Some(a) = &self.shown {
            let appear = ease(progress(self.shown_at, ACTIVITY_FADE));
            let leave = self.gone_at.map_or(1.0, |t| 1.0 - ease(progress(t, ACTIVITY_FADE)));
            let alpha = appear * leave;
            if alpha > 0.0 {
                let x = l.activity_x + m.width;
                let tint = |col: u32| mix(bg, col, alpha);
                if a.done {
                    text(out, fonts, glyphs, m, DONE_ICON, x, ty, tint(ink(c.green)), false)?;
                } else {
                    let t = self.shown_at.elapsed().as_secs_f32();
                    let r = (m.height * 0.1).round().max(1.5);
                    for i in 0..3 {
                        let phase = (t * 6.0 - i as f32 * 0.9).sin() * 0.5 + 0.5;
                        let rr = r * (0.7 + 0.5 * phase);
                        let cx = x + r + i as f32 * (2.6 * r);
                        let cy = (h / 2.0).round();
                        out.push(quad(cx - rr, cy - rr, 2.0 * rr, 2.0 * rr, tint(ink(mix(c.faint, c.accent, phase))), 1.0, scene::CIRCLE));
                    }
                }
                text(out, fonts, glyphs, m, &a.text, x + 2.0 * m.width, ty, tint(dim), false)?;
                let stroke = (2.0 * scale).round().max(2.0);
                match (a.done, a.percent) {
                    (false, Some(p)) => out.push(quad(0.0, h - stroke, width * p / 100.0, stroke, c.accent, alpha, scene::RECT)),
                    (false, None) => {
                        // unknown length: a short segment sweeping across
                        let t = (self.shown_at.elapsed().as_secs_f32() * 0.55).fract();
                        let w = width * 0.22;
                        out.push(quad(-w + t * (width + w), h - stroke, w, stroke, c.accent, alpha * 0.8, scene::RECT));
                    }
                    _ => {}
                }
            }
        }

        // Chips, right-aligned, in the order the config gave; the ones with an action light up under the pointer.
        for (i, (chip, (x, w))) in self.state.chips.iter().zip(&l.chips).enumerate() {
            let lit = self.lit(Hit::Chip(i));
            if let Some(cbg) = chip.bg {
                out.push(rect(*x, ty, *w, m.height, ink(mix(cbg, c.fg, 0.15 * lit))));
                text(out, fonts, glyphs, m, &chip.text, x + m.width, ty, chip.fg.unwrap_or(c.on), true)?;
            } else {
                if lit > 0.0 {
                    let pad = (m.width * 0.5).round();
                    out.push(quad(x - pad, block_y, w + 2.0 * pad, block_h, hover_bg, lit, scene::RECT));
                }
                text(out, fonts, glyphs, m, &chip.text, *x, ty, ink(chip.fg.unwrap_or(c.dim)), false)?;
            }
        }

        // The tooltip, after a moment under the pointer: a small flat block under the bar, over the editor.
        if let Some(tip) = self.tip() {
            let wait = self.hover_at.elapsed();
            if wait >= TIP_DELAY {
                let alpha = ease((wait - TIP_DELAY).as_secs_f32() / FADE.as_secs_f32());
                let anchor = match self.hover {
                    Some(Hit::Button(b)) => l.controls.iter().find(|c| c.0 == b).map(|c| c.1).unwrap_or(0.0),
                    Some(hit) => self.anchor(hit, &line, &m, width),
                    None => 0.0,
                };
                let w = (cells(&tip) as f32 + 2.0) * m.width;
                let x = anchor.min(width - w - m.width).max(m.width / 2.0).round();
                let y = h + (m.height * 0.3).round();
                out.push(quad(x, y, w, m.height * 1.5, mix(bg, c.fg, 0.16), alpha, scene::RECT));
                let text_y = (y + m.height * 0.25).round();
                text(out, fonts, glyphs, m, &tip, x + m.width, text_y, mix(mix(bg, c.fg, 0.16), c.fg, alpha), false)?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metrics() -> CellMetrics {
        CellMetrics { width: 10.0, height: 20.0, baseline: 15.0, underline: 17.0, stroke: 1.0 }
    }

    fn tool(icon: &str, label: Option<&str>, action: &str) -> Tool {
        Tool {
            icon: icon.into(),
            label: label.map(String::from),
            tip: Some(action.into()),
            action: action.into(),
            menu: label.is_some(),
            active: false,
        }
    }

    fn bar(path: &[&str], file: &str) -> Bar {
        let mut b = Bar::default();
        b.state.path = path.iter().map(|s| s.to_string()).collect();
        b.state.file = file.into();
        b.state.left = vec![tool("", Some("leader"), "projects"), tool("H", None, "home")];
        b.state.right = vec![tool("T", None, "theme"), tool("A", None, "agent")];
        b
    }

    #[test]
    fn the_mark_is_the_brands_n() {
        let (dots, w, h) = mark_dots();
        assert_eq!((w, h, dots.len()), (50.0, 70.0, 18));
        for r in 0..7 {
            let row: Vec<usize> = dots.iter().filter(|d| d.3 == r).map(|d| d.2).collect();
            assert!(row.contains(&0) && row.contains(&4), "row {r}: {row:?}");
        }
    }

    #[test]
    fn hits_every_part_of_the_bar() {
        let b = bar(&["nvim", "lua"], "gui.lua");
        let m = metrics();
        let l = b.layout(&m, &m, 1000.0);
        assert_eq!(l.h, 30.0);
        for (btn, cx, _, _) in l.controls {
            assert_eq!(b.hit(cx, 15.0, 1000.0, &m, &m), Hit::Button(btn));
        }
        assert!(l.controls.iter().all(|c| c.1 > 900.0), "controls on the right by default");
        assert_eq!(b.hit(l.mark.unwrap().0 + 2.0, 10.0, 1000.0, &m, &m), Hit::Mark);
        assert_eq!(b.hit(l.left[0].0 + 2.0, 10.0, 1000.0, &m, &m), Hit::Tool(Side::Left, 0));
        assert_eq!(b.hit(l.left[1].0 + 2.0, 10.0, 1000.0, &m, &m), Hit::Tool(Side::Left, 1));
        assert_eq!(b.hit(l.right[1].0 + 2.0, 10.0, 1000.0, &m, &m), Hit::Tool(Side::Right, 1));
        assert!(l.right[1].0 + l.right[1].1 <= l.controls[0].1, "right tools sit before the controls");
        assert_eq!(l.parts.iter().map(|p| p.label.as_str()).collect::<Vec<_>>(), vec!["nvim", "lua", "gui.lua"]);
        assert_eq!(b.hit(l.parts[1].x + 1.0, 10.0, 1000.0, &m, &m), Hit::Path(1));
        assert_eq!(b.hit(300.0, 40.0, 1000.0, &m, &m), Hit::Outside);
    }

    #[test]
    fn finds_tools_by_action() {
        let b = bar(&[], "a.rs");
        assert_eq!(b.find("home"), Some(Hit::Tool(Side::Left, 1)));
        assert_eq!(b.find("agent"), Some(Hit::Tool(Side::Right, 1)));
        assert_eq!(b.find("nope"), None);
    }

    #[test]
    fn a_label_makes_a_wider_tool_with_a_chevron() {
        let m = metrics();
        let icon_only = Bar::tool_width(&tool("T", None, "theme"), &m);
        let labeled = Bar::tool_width(&tool("", Some("leader"), "projects"), &m);
        assert_eq!(icon_only, 24.0);
        assert_eq!(labeled, (6.0 + 2.0 + 2.0) * 10.0);
    }

    #[test]
    fn tooltips_wait_a_moment() {
        let mut b = bar(&[], "a.rs");
        b.set_hover(Some(Hit::Tool(Side::Right, 0)));
        assert_eq!(b.tip().as_deref(), Some("theme"));
        assert!(b.animating(), "a frame is due when the tip shows");
        b.set_hover(Some(Hit::Drag));
        assert_eq!(b.tip(), None);
    }

    #[test]
    fn the_path_is_centered() {
        let b = bar(&["nvim", "lua"], "gui.lua");
        let l = b.layout(&metrics(), &metrics(), 1000.0);
        let (first, last) = (&l.parts[0], l.parts.last().unwrap());
        let mid = (first.x + last.x + last.w) / 2.0;
        assert!((mid - 500.0).abs() <= 1.0, "middle at {mid}");
    }

    #[test]
    fn no_tools_and_controls_on_the_left() {
        let mut b = bar(&[], "a.rs");
        b.state.left.clear();
        b.state.right.clear();
        b.state.show_mark = false;
        b.state.controls_left = true;
        let l = b.layout(&metrics(), &metrics(), 1000.0);
        assert!(l.mark.is_none() && l.left.is_empty() && l.right.is_empty());
        assert!(l.controls[0].1 < 60.0, "controls on the left");
    }

    #[test]
    fn hover_starts_the_fade_and_the_wave() {
        let mut b = Bar::default();
        assert!(b.set_hover(Some(Hit::Mark)));
        assert!(!b.set_hover(Some(Hit::Mark)), "same target: nothing to redraw");
        assert!(b.animating());
        assert!(b.wave_at.is_some());
    }

    #[test]
    fn activity_fades_out_after_it_ends() {
        let mut b = Bar::default();
        let mut s =
            State { activity: Some(Activity { text: "lua_ls · indexing".into(), percent: Some(40.0), done: false }), ..State::default() };
        b.set_state(s.clone());
        assert!(b.shown.is_some() && b.animating());
        s.activity = None;
        b.set_state(s);
        assert!(b.gone_at.is_some(), "it stays to fade out");
        assert!(b.shown.is_some());
    }

    #[test]
    fn chips_with_an_action_are_clickable() {
        let mut b = bar(&[], "a.rs");
        b.state.chips = vec![
            Chip { text: "lua_ls".into(), fg: None, bg: None, gap: 2.0, action: None },
            Chip { text: "9 to install".into(), fg: None, bg: None, gap: 2.0, action: Some("welcome".into()) },
        ];
        let l = b.layout(&metrics(), &metrics(), 1000.0);
        assert_eq!(b.hit(l.chips[1].0 + 1.0, 10.0, 1000.0, &metrics(), &metrics()), Hit::Chip(1));
        assert_eq!(b.hit(l.chips[0].0 + 1.0, 10.0, 1000.0, &metrics(), &metrics()), Hit::Drag, "information only");
    }

    #[test]
    fn long_paths_drop_leading_folders() {
        let b = bar(&["a-very-long-folder", "another-long-one", "src"], "main.rs");
        let l = b.layout(&metrics(), &metrics(), 560.0);
        assert_eq!(l.parts[0].index, None, "the … stands in for what was dropped");
        assert_eq!(l.parts.last().map(|p| p.label.as_str()), Some("main.rs"));
    }

    #[test]
    fn disabled_bar_takes_no_room() {
        let mut b = Bar::default();
        b.state.enabled = false;
        assert_eq!(b.height(&metrics()), 0.0);
        assert_eq!(b.hit(10.0, 5.0, 1000.0, &metrics(), &metrics()), Hit::Outside);
    }

    #[test]
    fn state_from_the_config() {
        let colors = Value::Map(
            ["fg", "dim", "faint", "accent", "yellow", "red", "on"].iter().map(|k| (Value::from(*k), Value::from("#102030"))).collect(),
        );
        let chip = Value::Map(vec![("text".into(), "REC @q".into()), ("bg".into(), "#ff0000".into()), ("gap".into(), 1.into())]);
        let activity = Value::Map(vec![("text".into(), "gopls".into()), ("percent".into(), 140.into())]);
        let theme = Value::Map(vec![
            ("icon".into(), "T".into()),
            ("tip".into(), "Theme".into()),
            ("action".into(), "theme".into()),
            ("active".into(), true.into()),
        ]);
        let v = Value::Map(vec![
            ("path".into(), Value::Array(vec!["nvim".into(), "lua".into()])),
            ("file".into(), "gui.lua".into()),
            ("modified".into(), true.into()),
            ("chips".into(), Value::Array(vec![chip])),
            ("activity".into(), activity),
            ("controls".into(), "left".into()),
            ("right".into(), Value::Array(vec![theme, Value::Map(vec![("icon".into(), "x".into())])])),
            ("padding".into(), Value::Map(vec![("x".into(), 4.into())])),
            ("colors".into(), colors),
        ]);
        let s = State::from_value(&v);
        assert_eq!((s.path.len(), s.file.as_str(), s.modified, s.pad_x, s.pad_bottom), (2, "gui.lua", true, 4.0, 0.0));
        assert_eq!(s.chips, vec![Chip { text: "REC @q".into(), fg: None, bg: Some(0xff0000), gap: 1.0, action: None }]);
        assert_eq!(s.activity, Some(Activity { text: "gopls".into(), percent: Some(100.0), done: false }));
        assert!(s.controls_left && s.show_mark);
        assert_eq!(s.right.len(), 1, "a tool without an action is dropped");
        assert_eq!((s.right[0].tip.as_deref(), s.right[0].active), (Some("Theme"), true));
        assert_eq!(s.colors.map(|c| (c.mark, c.green)), Some((0x102030, 0x102030)), "mark and green fall back to the accent");
    }
}
