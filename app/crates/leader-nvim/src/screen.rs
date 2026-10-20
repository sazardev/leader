use std::collections::HashMap;

use rmpv::Value;

use crate::event::{Anchor, Attr, CursorShape, Event, ModeInfo};
use crate::grid::Grid;

/// Where a grid sits on the editor (grid 1), in cells.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Pos {
    Root,
    Win { row: f32, col: f32 },
    Float { anchor: Anchor, anchor_grid: u64, row: f32, col: f32 },
    Msg { row: f32 },
}

#[derive(Debug, Clone, Copy)]
struct Placement {
    pos: Pos,
    zindex: i64,
    /// Last time it was placed: among equal zindex the newest is on top, like Neovim's compositor.
    order: u64,
    hidden: bool,
}

/// A grid ready to draw: its top-left on the editor in cells.
#[derive(Debug, Clone, Copy)]
pub struct Layer<'a> {
    pub id: u64,
    pub grid: &'a Grid,
    pub row: f32,
    pub col: f32,
    /// Floats and messages (they cover what is below even where their cells are "empty").
    pub floating: bool,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Colors {
    pub fg: u32,
    pub bg: u32,
    pub sp: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Cursor {
    pub grid: u64,
    pub row: u32,
    pub col: u32,
}

/// Everything Neovim told the UI, kept as state: grids and where they go, highlights, cursor, mode,
/// options. Pure: `apply` events, then read `layers()` to draw.
#[derive(Debug)]
pub struct Screen {
    pub grids: HashMap<u64, Grid>,
    placements: HashMap<u64, Placement>,
    attrs: Vec<Attr>,
    pub colors: Colors,
    pub modes: Vec<ModeInfo>,
    pub mode: usize,
    pub mode_name: String,
    pub cursor: Cursor,
    pub busy: bool,
    pub mouse: bool,
    pub title: Option<String>,
    pub options: HashMap<String, Value>,
    order: u64,
}

impl Default for Screen {
    fn default() -> Self {
        Screen {
            grids: HashMap::new(),
            placements: HashMap::new(),
            attrs: vec![Attr::default()],
            colors: Colors { fg: 0xffffff, bg: 0x000000, sp: 0xff0000 },
            modes: Vec::new(),
            mode: 0,
            mode_name: String::new(),
            cursor: Cursor { grid: 1, row: 0, col: 0 },
            busy: false,
            mouse: true,
            title: None,
            options: HashMap::new(),
            order: 0,
        }
    }
}

const DEFAULT_ATTR: Attr = Attr {
    fg: None,
    bg: None,
    sp: None,
    reverse: false,
    bold: false,
    italic: false,
    underline: false,
    undercurl: false,
    underdouble: false,
    underdotted: false,
    underdashed: false,
    strikethrough: false,
    blend: 0,
};

impl Screen {
    pub fn attr(&self, id: u32) -> &Attr {
        self.attrs.get(id as usize).unwrap_or(&DEFAULT_ATTR)
    }

    /// Resolved (fg, bg, sp) of a highlight, `reverse` applied.
    pub fn resolve(&self, id: u32) -> (u32, u32, u32) {
        let a = self.attr(id);
        let fg = a.fg.unwrap_or(self.colors.fg);
        let bg = a.bg.unwrap_or(self.colors.bg);
        let sp = a.sp.unwrap_or(fg);
        if a.reverse { (bg, fg, sp) } else { (fg, bg, sp) }
    }

    pub fn current_mode(&self) -> Option<&ModeInfo> {
        self.modes.get(self.mode)
    }

    pub fn cursor_shape(&self) -> (CursorShape, u32) {
        self.current_mode().map(|m| (m.shape, m.percentage)).unwrap_or((CursorShape::Block, 100))
    }

    fn place(&mut self, grid: u64, pos: Pos, zindex: i64) {
        self.order += 1;
        self.placements.insert(grid, Placement { pos, zindex, order: self.order, hidden: false });
    }

    fn origin(&self, id: u64, depth: u8) -> Option<(f32, f32)> {
        let p = self.placements.get(&id)?;
        if depth > 8 {
            return None;
        }
        Some(match p.pos {
            Pos::Root => (0.0, 0.0),
            Pos::Win { row, col } => (row, col),
            Pos::Msg { row } => (row, 0.0),
            Pos::Float { anchor, anchor_grid, row, col } => {
                let (ar, ac) = self.origin(anchor_grid, depth + 1).unwrap_or((0.0, 0.0));
                let g = self.grids.get(&id)?;
                let (w, h) = (g.width as f32, g.height as f32);
                let (r, c) = match anchor {
                    Anchor::NW => (row, col),
                    Anchor::NE => (row, col - w),
                    Anchor::SW => (row - h, col),
                    Anchor::SE => (row - h, col - w),
                };
                (ar + r, ac + c)
            }
        })
    }

    /// Visible grids bottom to top.
    pub fn layers(&self) -> Vec<Layer<'_>> {
        let mut out: Vec<(i64, u64, Layer)> = Vec::with_capacity(self.placements.len());
        for (&id, p) in &self.placements {
            if p.hidden {
                continue;
            }
            let (Some(grid), Some((row, col))) = (self.grids.get(&id), self.origin(id, 0)) else { continue };
            let (z, floating) = match p.pos {
                Pos::Root => (i64::MIN, false),
                Pos::Win { .. } => (i64::MIN + 1, false),
                Pos::Float { .. } | Pos::Msg { .. } => (p.zindex, true),
            };
            out.push((z, p.order, Layer { id, grid, row, col, floating }));
        }
        out.sort_by_key(|(z, order, _)| (*z, *order));
        out.into_iter().map(|(_, _, l)| l).collect()
    }

    /// Top-left of a grid on the editor, in cells.
    pub fn grid_origin(&self, id: u64) -> Option<(f32, f32)> {
        self.origin(id, 0)
    }

    /// The cursor on the editor, in cells.
    pub fn cursor_position(&self) -> Option<(f32, f32)> {
        let (r, c) = self.origin(self.cursor.grid, 0)?;
        Some((r + self.cursor.row as f32, c + self.cursor.col as f32))
    }

    /// The topmost grid under an editor cell, and the cell inside it (for mouse events).
    pub fn grid_at(&self, row: f32, col: f32) -> Option<(u64, u32, u32)> {
        self.layers().into_iter().rev().find_map(|l| {
            let (r, c) = (row - l.row, col - l.col);
            let inside = r >= 0.0 && c >= 0.0 && r < l.grid.height as f32 && c < l.grid.width as f32;
            inside.then_some((l.id, r as u32, c as u32))
        })
    }

    /// Applies one event; returns true on `flush` (the moment to draw).
    pub fn apply(&mut self, ev: Event) -> bool {
        match ev {
            Event::GridResize { grid, width, height } => {
                self.grids.entry(grid).or_default().resize(width, height);
                if grid == 1 && !self.placements.contains_key(&1) {
                    self.place(1, Pos::Root, 0);
                }
            }
            Event::GridLine { grid, row, col, cells } => {
                if let Some(g) = self.grids.get_mut(&grid) {
                    g.put_line(row, col, &cells);
                }
            }
            Event::GridClear { grid } => {
                if let Some(g) = self.grids.get_mut(&grid) {
                    g.clear();
                }
            }
            Event::GridDestroy { grid } => {
                self.grids.remove(&grid);
                self.placements.remove(&grid);
            }
            Event::GridCursorGoto { grid, row, col } => self.cursor = Cursor { grid, row, col },
            Event::GridScroll { grid, top, bot, left, right, rows } => {
                if let Some(g) = self.grids.get_mut(&grid) {
                    g.scroll(top, bot, left, right, rows);
                }
            }
            Event::DefaultColors { fg, bg, sp } => {
                self.colors = Colors { fg, bg, sp };
                self.attrs[0] = Attr::default();
            }
            Event::HlAttrDefine { id, attr } => {
                let id = id as usize;
                if self.attrs.len() <= id {
                    self.attrs.resize(id + 1, Attr::default());
                }
                self.attrs[id] = attr;
            }
            Event::ModeInfoSet { modes, .. } => self.modes = modes,
            Event::ModeChange { mode, index } => {
                self.mode = index as usize;
                self.mode_name = mode;
            }
            Event::WinPos { grid, row, col, width, height } => {
                self.grids.entry(grid).or_default().resize(width, height);
                self.place(grid, Pos::Win { row: row as f32, col: col as f32 }, 0);
            }
            Event::WinFloatPos { grid, anchor, anchor_grid, row, col, zindex } => {
                self.place(grid, Pos::Float { anchor, anchor_grid, row, col }, zindex);
            }
            Event::WinHide { grid } => {
                if let Some(p) = self.placements.get_mut(&grid) {
                    p.hidden = true;
                }
            }
            Event::WinClose { grid } => {
                self.placements.remove(&grid);
            }
            Event::MsgSetPos { grid, row, zindex } => self.place(grid, Pos::Msg { row: row as f32 }, zindex),
            Event::OptionSet { name, value } => {
                self.options.insert(name, value);
            }
            Event::SetTitle { title } => self.title = Some(title),
            Event::Busy(b) => self.busy = b,
            Event::MouseOn(m) => self.mouse = m,
            Event::Flush => return true,
            Event::Other(_) => {}
        }
        false
    }

    /// `guifont` as (families, size in points), e.g. "Geist Mono,Symbols:h13" → (["Geist Mono", "Symbols"], 13).
    pub fn guifont(&self) -> Option<(Vec<String>, Option<f32>)> {
        parse_guifont(self.options.get("guifont")?.as_str()?)
    }
}

pub fn parse_guifont(spec: &str) -> Option<(Vec<String>, Option<f32>)> {
    if spec.trim().is_empty() {
        return None;
    }
    let mut size = None;
    let mut families = Vec::new();
    for part in spec.split(',') {
        let mut fields = part.split(':');
        let family = fields.next().unwrap_or_default().trim().replace('_', " ");
        for f in fields {
            if let Some(h) = f.strip_prefix('h') {
                size = h.parse().ok().or(size);
            }
        }
        if !family.is_empty() {
            families.push(family);
        }
    }
    Some((families, size))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::Cell;

    fn put(s: &mut Screen, grid: u64, row: u32, text: &str) {
        let cells = text.chars().map(|c| Cell { text: c.to_string().into(), hl: Some(0), repeat: 1 }).collect();
        s.apply(Event::GridLine { grid, row, col: 0, cells });
    }

    fn base() -> Screen {
        let mut s = Screen::default();
        s.apply(Event::GridResize { grid: 1, width: 20, height: 10 });
        s.apply(Event::WinPos { grid: 2, row: 1, col: 0, width: 20, height: 8 });
        s
    }

    #[test]
    fn floats_go_over_windows_and_anchor_to_their_grid() {
        let mut s = base();
        s.apply(Event::GridResize { grid: 3, width: 5, height: 2 });
        s.apply(Event::WinFloatPos { grid: 3, anchor: Anchor::SE, anchor_grid: 2, row: 4.0, col: 10.0, zindex: 50 });
        let layers = s.layers();
        assert_eq!(layers.iter().map(|l| l.id).collect::<Vec<_>>(), vec![1, 2, 3]);
        let f = layers[2];
        assert_eq!((f.row, f.col), (1.0 + 4.0 - 2.0, 10.0 - 5.0));
        assert!(f.floating);
    }

    #[test]
    fn hide_and_close_remove_the_layer() {
        let mut s = base();
        s.apply(Event::WinHide { grid: 2 });
        assert_eq!(s.layers().len(), 1);
        s.apply(Event::WinPos { grid: 2, row: 1, col: 0, width: 20, height: 8 });
        assert_eq!(s.layers().len(), 2);
        s.apply(Event::WinClose { grid: 2 });
        assert_eq!(s.layers().len(), 1);
    }

    #[test]
    fn cursor_and_mouse_hits_use_the_grid_origin() {
        let mut s = base();
        put(&mut s, 2, 0, "hello");
        s.apply(Event::GridCursorGoto { grid: 2, row: 3, col: 4 });
        assert_eq!(s.cursor_position(), Some((4.0, 4.0)));
        assert_eq!(s.grid_at(4.0, 4.0), Some((2, 3, 4)));
        assert_eq!(s.grid_at(9.0, 1.0), Some((1, 9, 1)));
    }

    #[test]
    fn reverse_swaps_colors() {
        let mut s = Screen::default();
        s.apply(Event::DefaultColors { fg: 0xeeeeee, bg: 0x111111, sp: 0 });
        s.apply(Event::HlAttrDefine { id: 1, attr: Attr { fg: Some(0xff0000), reverse: true, ..Default::default() } });
        assert_eq!(s.resolve(1), (0x111111, 0xff0000, 0xff0000));
        assert_eq!(s.resolve(99), (0xeeeeee, 0x111111, 0xeeeeee));
    }

    #[test]
    fn guifont_specs() {
        assert_eq!(
            parse_guifont("Geist_Mono,Symbols Nerd Font:h13.5"),
            Some((vec!["Geist Mono".into(), "Symbols Nerd Font".into()], Some(13.5)))
        );
        assert_eq!(parse_guifont("Iosevka"), Some((vec!["Iosevka".into()], None)));
        assert_eq!(parse_guifont(""), None);
    }
}
