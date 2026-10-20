//! Screen state → the quads of one frame, on the CPU. Everything the GPU draws is one instanced
//! quad (rectangle, glyph or decoration) in painter's order, so a frame is ONE draw call.
use std::collections::HashMap;

use bytemuck::{Pod, Zeroable};
use leader_nvim::{CursorShape, Screen};
use smol_str::SmolStr;

use crate::boxdraw;
use crate::font::{CellMetrics, Fonts};

pub const RECT: u32 = 0;
pub const MASK: u32 = 1;
pub const COLOR: u32 = 2;
pub const UNDERCURL: u32 = 3;
pub const DOTTED: u32 = 4;
pub const DASHED: u32 = 5;
/// An antialiased X filling the quad (the close button); `uv.x` = line width.
pub const CROSS: u32 = 6;
/// An antialiased disc filling the quad (the mark's dots).
pub const CIRCLE: u32 = 7;

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable, PartialEq)]
pub struct Quad {
    pub pos: [f32; 2],
    pub size: [f32; 2],
    /// Atlas texel of the top-left corner (glyphs) or unused.
    pub uv: [f32; 2],
    /// sRGB, straight alpha.
    pub color: [f32; 4],
    pub kind: u32,
}

#[derive(Debug, Clone, Copy)]
struct Placed {
    left: f32,
    top: f32,
    width: f32,
    height: f32,
    u: f32,
    v: f32,
    color: bool,
}

pub struct Upload {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// The atlas ran out of room: grow it, clear the cache and build again.
#[derive(Debug)]
pub struct AtlasFull;

/// Glyphs already rasterized, and where they live in the atlas (a shelf packer).
pub struct Glyphs {
    pub size: u32,
    x: u32,
    y: u32,
    shelf: u32,
    map: HashMap<(SmolStr, u8), Vec<Placed>>,
    pub uploads: Vec<Upload>,
}

impl Glyphs {
    pub fn new(size: u32) -> Glyphs {
        Glyphs { size, x: 0, y: 0, shelf: 0, map: HashMap::new(), uploads: Vec::new() }
    }

    pub fn reset(&mut self, size: u32) {
        *self = Glyphs::new(size);
    }

    fn alloc(&mut self, w: u32, h: u32) -> Option<(u32, u32)> {
        if w + 1 > self.size {
            return None;
        }
        if self.x + w + 1 > self.size {
            self.x = 0;
            self.y += self.shelf + 1;
            self.shelf = 0;
        }
        if self.y + h + 1 > self.size {
            return None;
        }
        let at = (self.x, self.y);
        self.x += w + 1;
        self.shelf = self.shelf.max(h);
        Some(at)
    }

    fn get(&mut self, fonts: &mut Fonts, text: &str, bold: bool, italic: bool, small: bool) -> Result<&[Placed], AtlasFull> {
        let key = (SmolStr::new(text), bold as u8 | (italic as u8) << 1 | (small as u8) << 2);
        if !self.map.contains_key(&key) {
            let mut placed = Vec::new();
            for r in fonts.rasterize(text, bold, italic, small) {
                let (x, y) = self.alloc(r.width, r.height).ok_or(AtlasFull)?;
                placed.push(Placed {
                    left: r.left as f32,
                    top: r.top as f32,
                    width: r.width as f32,
                    height: r.height as f32,
                    u: x as f32,
                    v: y as f32,
                    color: r.color,
                });
                self.uploads.push(Upload { x, y, width: r.width, height: r.height, rgba: r.rgba });
            }
            self.map.insert(key.clone(), placed);
        }
        Ok(&self.map[&key])
    }
}

pub struct View<'a> {
    /// Top-left of the editor in the window, physical px.
    pub origin: (f32, f32),
    pub focused: bool,
    /// Cursor blink phase: false = hidden right now.
    pub cursor_on: bool,
    /// The app bar across the top (our own title bar), when on.
    pub bar: Option<&'a crate::appbar::Bar>,
    /// Window width in physical px, and the scale factor.
    pub width: f32,
    pub scale: f32,
}

pub fn rgb(c: u32, alpha: f32) -> [f32; 4] {
    [((c >> 16) & 0xff) as f32 / 255.0, ((c >> 8) & 0xff) as f32 / 255.0, (c & 0xff) as f32 / 255.0, alpha]
}

fn rect(x: f32, y: f32, w: f32, h: f32, color: [f32; 4], kind: u32) -> Quad {
    Quad { pos: [x, y], size: [w, h], uv: [0.0, 0.0], color, kind }
}

fn glyph_quads(out: &mut Vec<Quad>, placed: &[Placed], x: f32, baseline: f32, color: [f32; 4]) {
    for p in placed {
        out.push(Quad {
            pos: [x + p.left, baseline + p.top],
            size: [p.width, p.height],
            uv: [p.u, p.v],
            color,
            kind: if p.color { COLOR } else { MASK },
        });
    }
}

/// Draws one cell's text: block/box characters as exact rectangles, everything else from the atlas.
#[allow(clippy::too_many_arguments)]
pub fn cell_text(
    out: &mut Vec<Quad>,
    fonts: &mut Fonts,
    glyphs: &mut Glyphs,
    m: CellMetrics,
    text: &str,
    bold: bool,
    italic: bool,
    x: f32,
    y: f32,
    color: [f32; 4],
    small: bool,
) -> Result<(), AtlasFull> {
    let mut chars = text.chars();
    if let (Some(c), None) = (chars.next(), chars.next())
        && let Some(pieces) = boxdraw::pieces(c, m.width, m.height, m.stroke)
    {
        for pc in pieces {
            out.push(rect(x + pc.x, y + pc.y, pc.w, pc.h, [color[0], color[1], color[2], color[3] * pc.alpha], RECT));
        }
        return Ok(());
    }
    let placed = glyphs.get(fonts, text, bold, italic, small)?;
    glyph_quads(out, placed, x, y + m.baseline, color);
    Ok(())
}

/// Builds the frame into `out` (cleared first).
pub fn build(screen: &Screen, fonts: &mut Fonts, glyphs: &mut Glyphs, view: &View, out: &mut Vec<Quad>) -> Result<(), AtlasFull> {
    out.clear();
    let m = fonts.metrics;
    let (cw, ch) = (m.width, m.height);
    let default_bg = screen.colors.bg;
    // Cells on the editor's right edge stretch to the window's: the few pixels left over by the cell width are
    // painted like the cells next to them (the statusline reaches the edge). The rows' leftover sits under the bar.
    let root_w = screen.grids.get(&1).map(|g| g.width as f32).unwrap_or(0.0);
    let mut texts: Vec<Quad> = Vec::new();
    let mut decos: Vec<Quad> = Vec::new();

    for layer in screen.layers() {
        let ox = view.origin.0 + layer.col * cw;
        let oy = view.origin.1 + layer.row * ch;
        texts.clear();
        decos.clear();
        let right_edge = !layer.floating && layer.col + layer.grid.width as f32 >= root_w;
        for r in 0..layer.grid.height {
            let y = oy + r as f32 * ch;
            let row = layer.grid.row(r);
            if row.is_empty() {
                continue;
            }
            // Backgrounds as runs of equal color.
            let mut run: Option<(usize, u32, f32)> = None;
            for (c, cell) in row.iter().enumerate().chain(std::iter::once((row.len(), &row[0]))) {
                let here = (c < row.len()).then(|| {
                    let attr = screen.attr(cell.hl);
                    let (_, bg, _) = screen.resolve(cell.hl);
                    let alpha = if layer.floating { 1.0 - attr.blend as f32 / 100.0 } else { 1.0 };
                    (bg, alpha)
                });
                match (run, here) {
                    (Some((_, b, a)), Some((bg, alpha))) if b == bg && a == alpha => {}
                    _ => {
                        if let Some((start, b, a)) = run {
                            // Only grid 1 may skip its default background: Neovim leaves stale cells on it
                            // under the windows, so every window paints all of its own.
                            if layer.id != 1 || b != default_bg {
                                let x = ox + start as f32 * cw;
                                let w = if right_edge && c == row.len() { (view.width - x).max(cw) } else { (c - start) as f32 * cw };
                                out.push(rect(x, y, w, ch, rgb(b, a), RECT));
                            }
                        }
                        run = here.map(|(bg, alpha)| (c, bg, alpha));
                    }
                }
            }
            // Text and decorations.
            for (c, cell) in row.iter().enumerate() {
                let attr = screen.attr(cell.hl);
                let x = ox + c as f32 * cw;
                let (fg, _, sp) = screen.resolve(cell.hl);
                if !cell.text.is_empty() && cell.text != " " {
                    cell_text(&mut texts, fonts, glyphs, m, &cell.text, attr.bold, attr.italic, x, y, rgb(fg, 1.0), false)?;
                }
                let width = if cell.text.is_empty() { 0.0 } else { cw };
                if width == 0.0 {
                    continue;
                }
                let line = |kind| rect(x, y + m.underline, cw, m.stroke, rgb(sp, 1.0), kind);
                if attr.underline {
                    decos.push(line(RECT));
                }
                if attr.underdouble {
                    decos.push(line(RECT));
                    decos.push(rect(x, y + m.underline - 2.0 * m.stroke, cw, m.stroke, rgb(sp, 1.0), RECT));
                }
                if attr.underdotted {
                    decos.push(line(DOTTED));
                }
                if attr.underdashed {
                    decos.push(line(DASHED));
                }
                if attr.undercurl {
                    let h = (m.stroke * 3.0).max(3.0);
                    decos.push(rect(x, (y + m.underline - h / 2.0).min(y + ch - h), cw, h, rgb(sp, 1.0), UNDERCURL));
                }
                if attr.strikethrough {
                    decos.push(rect(x, y + (m.baseline * 0.65).round(), cw, m.stroke, rgb(fg, 1.0), RECT));
                }
            }
        }
        out.extend_from_slice(&texts);
        out.extend_from_slice(&decos);
    }

    cursor(screen, fonts, glyphs, view, out)?;
    if let Some(bar) = view.bar {
        bar.draw(out, fonts, glyphs, view.width, screen.colors.fg, screen.colors.bg, view.scale)?;
    }
    Ok(())
}

fn cursor(screen: &Screen, fonts: &mut Fonts, glyphs: &mut Glyphs, view: &View, out: &mut Vec<Quad>) -> Result<(), AtlasFull> {
    if screen.busy || !view.cursor_on {
        return Ok(());
    }
    let Some((row, col)) = screen.cursor_position() else { return Ok(()) };
    let m = fonts.metrics;
    let (x, y) = (view.origin.0 + col * m.width, view.origin.1 + row * m.height);
    // The cell under the cursor, on whatever grid is on top there.
    let cell = screen.grid_at(row, col).and_then(|(id, r, c)| {
        let g = screen.grids.get(&id)?;
        (r < g.height && c < g.width).then(|| g.row(r)[c as usize].clone())
    });
    let (text, hl) = cell.map(|c| (c.text, c.hl)).unwrap_or_default();
    let (cell_fg, cell_bg, _) = screen.resolve(hl);
    let attr_id = screen.current_mode().map(|m| m.attr_id).unwrap_or(0);
    // attr_id 0 = reverse video of the cell, like a terminal. A cursor highlight with blend=100 hides it
    // (Leader's start screen does that).
    let (cur_fg, cur_bg, alpha) = if attr_id == 0 {
        (cell_bg, cell_fg, 1.0)
    } else {
        let a = screen.attr(attr_id);
        (a.fg.unwrap_or(cell_bg), a.bg.unwrap_or(cell_fg), 1.0 - a.blend as f32 / 100.0)
    };
    if alpha <= 0.0 {
        return Ok(());
    }
    let wide = text.chars().next().is_some_and(unicode_wide);
    let w = if wide { m.width * 2.0 } else { m.width };
    let (shape, pct) = screen.cursor_shape();
    let thin = |n: f32| (n * pct as f32 / 100.0).round().max(1.0);
    if !view.focused {
        let s = m.stroke;
        let color = rgb(cur_bg, alpha);
        out.push(rect(x, y, w, s, color, RECT));
        out.push(rect(x, y + m.height - s, w, s, color, RECT));
        out.push(rect(x, y, s, m.height, color, RECT));
        out.push(rect(x + w - s, y, s, m.height, color, RECT));
        return Ok(());
    }
    match shape {
        CursorShape::Block => {
            out.push(rect(x, y, w, m.height, rgb(cur_bg, alpha), RECT));
            if !text.is_empty() && text != " " {
                let attr = screen.attr(hl);
                cell_text(out, fonts, glyphs, m, &text, attr.bold, attr.italic, x, y, rgb(cur_fg, alpha), false)?;
            }
        }
        CursorShape::Vertical => out.push(rect(x, y, thin(m.width), m.height, rgb(cur_bg, alpha), RECT)),
        CursorShape::Horizontal => {
            let h = thin(m.height);
            out.push(rect(x, y + m.height - h, w, h, rgb(cur_bg, alpha), RECT));
        }
    }
    Ok(())
}

/// East Asian wide and emoji ranges, enough for the cursor width (Neovim already lays the grid out).
fn unicode_wide(c: char) -> bool {
    matches!(c as u32, 0x1100..=0x115F | 0x2E80..=0xA4CF | 0xAC00..=0xD7A3 | 0xF900..=0xFAFF | 0xFE30..=0xFE4F | 0xFF00..=0xFF60 | 0xFFE0..=0xFFE6 | 0x1F300..=0x1F64F | 0x1F900..=0x1F9FF | 0x20000..=0x3FFFD)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shelf_packer_wraps_and_fills() {
        let mut g = Glyphs::new(10);
        assert_eq!(g.alloc(4, 3), Some((0, 0)));
        assert_eq!(g.alloc(4, 2), Some((5, 0)));
        assert_eq!(g.alloc(4, 2), Some((0, 4)));
        assert_eq!(g.alloc(4, 6), None);
        assert_eq!(g.alloc(20, 1), None);
    }

    #[test]
    fn colors_are_unit_floats() {
        assert_eq!(rgb(0xff8000, 0.5), [1.0, 128.0 / 255.0, 0.0, 0.5]);
    }
}
