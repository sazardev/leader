//! Fonts: the system font database (loaded on a background thread while the window and GPU start),
//! cell metrics of the chosen family, and glyph rasterization (shaped by cosmic-text with its font
//! fallback for icons, emoji and CJK, rasterized by swash).
use cosmic_text::{Attrs, Buffer, Family, FontSystem, Metrics, Shaping, Style, SwashCache, SwashContent, Weight};

pub const DEFAULT_FAMILIES: &[&str] = &["GeistMono Nerd Font Mono", "GeistMono NFM", "JetBrainsMono Nerd Font Mono", "DejaVu Sans Mono"];
pub const DEFAULT_SIZE: f32 = 12.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CellMetrics {
    pub width: f32,
    pub height: f32,
    /// From the top of the cell.
    pub baseline: f32,
    /// From the top of the cell.
    pub underline: f32,
    pub stroke: f32,
}

/// A rasterized glyph piece, positioned relative to the cell's left edge and baseline.
pub struct Raster {
    pub left: i32,
    pub top: i32,
    pub width: u32,
    pub height: u32,
    pub color: bool,
    /// RGBA8; masks are white with coverage in alpha.
    pub rgba: Vec<u8>,
}

pub struct Fonts {
    system: FontSystem,
    cache: SwashCache,
    family: String,
    /// Points, as in `guifont`.
    pub size: f32,
    pub scale: f32,
    /// `linespace` (logical pixels): extra air between lines, from Neovim's option.
    pub linespace: f32,
    /// Base font weight (400 regular, 500 medium, 700 bold), from `gui.font_weight`.
    pub weight: u16,
    pub metrics: CellMetrics,
    /// The smaller text of the app bar (`SMALL` of the editor's size), measured the same way.
    pub small: CellMetrics,
}

/// The app bar's text against the editor's: quieter, so the bar never competes with the code.
pub const SMALL: f32 = 0.86;

/// Adds `linespace` (physical pixels) between lines: half above, half below, so the text stays centered in the cell.
fn spaced(mut m: CellMetrics, extra: f32) -> CellMetrics {
    if extra <= 0.0 {
        return m;
    }
    let top = (extra / 2.0).round();
    m.height += extra;
    m.baseline += top;
    m.underline = (m.underline + top).min(m.height - m.stroke);
    m
}

pub fn load_system() -> FontSystem {
    FontSystem::new()
}

fn has_family(system: &FontSystem, name: &str) -> bool {
    system.db().faces().any(|f| f.families.iter().any(|(n, _)| n.eq_ignore_ascii_case(name)))
}

impl Fonts {
    pub fn new(system: FontSystem, families: &[String], size: f32, weight: u16, scale: f32) -> Fonts {
        let mut fonts = Fonts {
            system,
            cache: SwashCache::new(),
            family: String::new(),
            size,
            scale,
            linespace: 0.0,
            weight: weight.clamp(100, 900),
            metrics: CellMetrics { width: 8.0, height: 16.0, baseline: 12.0, underline: 14.0, stroke: 1.0 },
            small: CellMetrics { width: 7.0, height: 14.0, baseline: 10.0, underline: 12.0, stroke: 1.0 },
        };
        fonts.set(families, size, weight, scale);
        fonts
    }

    pub fn family(&self) -> &str {
        &self.family
    }

    /// Picks the first installed family (or the defaults, then the system monospace) and measures it.
    pub fn set(&mut self, families: &[String], size: f32, weight: u16, scale: f32) {
        let wanted = families.iter().map(String::as_str).chain(DEFAULT_FAMILIES.iter().copied());
        self.family = wanted.into_iter().find(|f| has_family(&self.system, f)).unwrap_or("monospace").to_string();
        self.size = size.clamp(4.0, 72.0);
        self.weight = weight.clamp(100, 900);
        self.scale = scale;
        self.cache = SwashCache::new();
        let px = self.px(false);
        let base = self.measure(px);
        self.metrics = spaced(base, (self.linespace * self.scale).round().max(0.0));
        self.small = self.measure(self.px(true));
    }

    /// Applies Neovim's `linespace` (logical pixels) to the editor's cells; the app bar keeps its own compact metrics.
    pub fn set_linespace(&mut self, space: f32) {
        let space = space.max(0.0);
        if (self.linespace - space).abs() < f32::EPSILON {
            return;
        }
        self.linespace = space;
        let px = self.px(false);
        let base = self.measure(px);
        self.metrics = spaced(base, (self.linespace * self.scale).round().max(0.0));
    }

    fn px(&self, small: bool) -> f32 {
        // Points to pixels at 96 dpi, like terminals and other Neovim GUIs.
        (self.size * 96.0 / 72.0 * self.scale * if small { SMALL } else { 1.0 }).round()
    }

    fn attrs(&self, bold: bool, italic: bool) -> Attrs<'_> {
        let family = if self.family == "monospace" { Family::Monospace } else { Family::Name(&self.family) };
        Attrs::new().family(family).weight(if bold { Weight::BOLD } else { Weight(self.weight) }).style(if italic {
            Style::Italic
        } else {
            Style::Normal
        })
    }

    fn measure(&mut self, px: f32) -> CellMetrics {
        let id = {
            let mut buffer = Buffer::new(&mut self.system, Metrics::new(px, px));
            let attrs = self.attrs(false, false);
            buffer.set_text("M", &attrs, Shaping::Advanced, None);
            buffer.shape_until_scroll(&mut self.system, false);
            buffer.layout_runs().flat_map(|r| r.glyphs.iter()).next().map(|g| (g.font_id, g.w))
        };
        let Some((font_id, advance)) = id else {
            return CellMetrics {
                width: (px * 0.6).round(),
                height: (px * 1.25).round(),
                baseline: px.round(),
                underline: px.round() + 2.0,
                stroke: 1.0,
            };
        };
        let Some(font) = self.system.get_font(font_id, Weight::NORMAL) else {
            return CellMetrics {
                width: advance.round(),
                height: (px * 1.25).round(),
                baseline: px.round(),
                underline: px.round() + 2.0,
                stroke: 1.0,
            };
        };
        let m = font.as_swash().metrics(&[]).scale(px);
        let content = m.ascent + m.descent;
        let height = (content + m.leading.max(0.0)).ceil().max(1.0);
        let baseline = ((height - content) / 2.0 + m.ascent).round();
        let stroke = m.stroke_size.max(1.0).round();
        CellMetrics {
            width: advance.round().max(1.0),
            height,
            baseline,
            underline: (baseline - m.underline_offset).round().min(height - stroke),
            stroke,
        }
    }

    /// The pieces of a cell's text (usually one glyph; several for combining marks); `small` = the app bar's size.
    pub fn rasterize(&mut self, text: &str, bold: bool, italic: bool, small: bool) -> Vec<Raster> {
        let px = self.px(small);
        let line = if small { self.small.height } else { self.metrics.height };
        let mut buffer = Buffer::new(&mut self.system, Metrics::new(px, line));
        let attrs = self.attrs(bold, italic);
        buffer.set_text(text, &attrs, Shaping::Advanced, None);
        buffer.shape_until_scroll(&mut self.system, false);
        let glyphs: Vec<_> = buffer.layout_runs().flat_map(|r| r.glyphs.iter().map(|g| g.physical((0.0, 0.0), 1.0))).collect();
        let mut out = Vec::with_capacity(glyphs.len());
        for g in glyphs {
            let Some(image) = self.cache.get_image(&mut self.system, g.cache_key).as_ref() else { continue };
            let (w, h) = (image.placement.width, image.placement.height);
            if w == 0 || h == 0 {
                continue;
            }
            let (color, rgba) = match image.content {
                SwashContent::Mask => (false, image.data.iter().flat_map(|&a| [255, 255, 255, a]).collect()),
                SwashContent::Color => (true, image.data.clone()),
                SwashContent::SubpixelMask => (false, image.data.chunks(4).flat_map(|p| [255, 255, 255, p[1]]).collect()),
            };
            out.push(Raster { left: g.x + image.placement.left, top: g.y - image.placement.top, width: w, height: h, color, rgba });
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cell() -> CellMetrics {
        CellMetrics { width: 8.0, height: 16.0, baseline: 12.0, underline: 14.0, stroke: 1.0 }
    }

    #[test]
    fn linespace_centers_the_glyph_in_a_taller_cell() {
        let m = spaced(cell(), 4.0);
        assert_eq!(m.height, 20.0);
        assert_eq!(m.baseline, 14.0);
        assert_eq!(m.underline, 16.0);
    }

    #[test]
    fn no_linespace_keeps_the_metrics() {
        assert_eq!(spaced(cell(), 0.0), cell());
    }
}
