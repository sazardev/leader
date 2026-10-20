//! Block elements (U+2580–U+259F) and box drawing (U+2500–U+257F) drawn as exact rectangles,
//! like Alacritty or kitty do: font glyphs for them rarely fill the cell (line gap, rounding),
//! which breaks the flat design's half cells (`▀`/`▄` FlatEdge) and every border.

/// A rectangle in cell-relative pixels with an alpha multiplier (shades).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Piece {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub alpha: f32,
}

fn p(x: f32, y: f32, w: f32, h: f32) -> Piece {
    Piece { x, y, w, h, alpha: 1.0 }
}

/// Arm weights of a box-drawing char: up, right, down, left (0 none, 1 light, 2 heavy, 3 double).
fn arms(c: char) -> Option<[u8; 4]> {
    Some(match c {
        '─' | '┄' | '┈' | '╌' => [0, 1, 0, 1],
        '━' | '┅' | '┉' | '╍' => [0, 2, 0, 2],
        '│' | '┆' | '┊' | '╎' => [1, 0, 1, 0],
        '┃' | '┇' | '┋' | '╏' => [2, 0, 2, 0],
        '┌' | '╭' => [0, 1, 1, 0],
        '┏' => [0, 2, 2, 0],
        '┐' | '╮' => [0, 0, 1, 1],
        '┓' => [0, 0, 2, 2],
        '└' | '╰' => [1, 1, 0, 0],
        '┗' => [2, 2, 0, 0],
        '┘' | '╯' => [1, 0, 0, 1],
        '┛' => [2, 0, 0, 2],
        '├' => [1, 1, 1, 0],
        '┣' => [2, 2, 2, 0],
        '┤' => [1, 0, 1, 1],
        '┫' => [2, 0, 2, 2],
        '┬' => [0, 1, 1, 1],
        '┳' => [0, 2, 2, 2],
        '┴' => [1, 1, 0, 1],
        '┻' => [2, 2, 0, 2],
        '┼' => [1, 1, 1, 1],
        '╋' => [2, 2, 2, 2],
        '═' => [0, 3, 0, 3],
        '║' => [3, 0, 3, 0],
        '╔' => [0, 3, 3, 0],
        '╗' => [0, 0, 3, 3],
        '╚' => [3, 3, 0, 0],
        '╝' => [3, 0, 0, 3],
        '╠' => [3, 3, 3, 0],
        '╣' => [3, 0, 3, 3],
        '╦' => [0, 3, 3, 3],
        '╩' => [3, 3, 0, 3],
        '╬' => [3, 3, 3, 3],
        '╴' => [0, 0, 0, 1],
        '╵' => [1, 0, 0, 0],
        '╶' => [0, 1, 0, 0],
        '╷' => [0, 0, 1, 0],
        '╸' => [0, 0, 0, 2],
        '╹' => [2, 0, 0, 0],
        '╺' => [0, 2, 0, 0],
        '╻' => [0, 0, 2, 0],
        _ => return None,
    })
}

fn blocks(c: char, w: f32, h: f32) -> Option<Vec<Piece>> {
    let (hw, hh) = ((w / 2.0).round(), (h / 2.0).round());
    let eighth_h = |n: f32| (h * n / 8.0).round();
    let eighth_w = |n: f32| (w * n / 8.0).round();
    let (ul, ur, ll, lr) = (p(0.0, 0.0, hw, hh), p(hw, 0.0, w - hw, hh), p(0.0, hh, hw, h - hh), p(hw, hh, w - hw, h - hh));
    let shade = |a: f32| vec![Piece { alpha: a, ..p(0.0, 0.0, w, h) }];
    Some(match c {
        '▀' => vec![p(0.0, 0.0, w, hh)],
        '▁'..='▇' => {
            let n = (c as u32 - 0x2580) as f32;
            let t = eighth_h(n);
            vec![p(0.0, h - t, w, t)]
        }
        '█' => vec![p(0.0, 0.0, w, h)],
        '▉'..='▏' => {
            let n = (0x2590 - c as u32) as f32;
            vec![p(0.0, 0.0, eighth_w(n), h)]
        }
        '▐' => vec![p(hw, 0.0, w - hw, h)],
        '░' => shade(0.25),
        '▒' => shade(0.5),
        '▓' => shade(0.75),
        '▔' => vec![p(0.0, 0.0, w, eighth_h(1.0))],
        '▕' => {
            let t = eighth_w(1.0);
            vec![p(w - t, 0.0, t, h)]
        }
        '▖' => vec![ll],
        '▗' => vec![lr],
        '▘' => vec![ul],
        '▙' => vec![ul, ll, lr],
        '▚' => vec![ul, lr],
        '▛' => vec![ul, ur, ll],
        '▜' => vec![ul, ur, lr],
        '▝' => vec![ur],
        '▞' => vec![ur, ll],
        '▟' => vec![ur, ll, lr],
        _ => return None,
    })
}

/// The rectangles for `c` in a `w`×`h` cell, or None to let the font draw it.
pub fn pieces(c: char, w: f32, h: f32, stroke: f32) -> Option<Vec<Piece>> {
    if let Some(b) = blocks(c, w, h) {
        return Some(b);
    }
    let [up, right, down, left] = arms(c)?;
    let light = stroke.max(1.0);
    let thick = |weight: u8| if weight == 2 { light * 2.0 } else { light };
    let mut out = Vec::new();
    // Center line of the cell for each axis, aligned so a light stroke sits on whole pixels.
    let cx = ((w - light) / 2.0).floor();
    let cy = ((h - light) / 2.0).floor();
    let horizontal = |out: &mut Vec<Piece>, x0: f32, x1: f32, weight: u8| {
        if weight == 3 {
            out.push(p(x0, cy - light, x1 - x0, light));
            out.push(p(x0, cy + light, x1 - x0, light));
        } else {
            let t = thick(weight);
            out.push(p(x0, cy + (light - t) / 2.0, x1 - x0, t));
        }
    };
    let vertical = |out: &mut Vec<Piece>, y0: f32, y1: f32, weight: u8| {
        if weight == 3 {
            out.push(p(cx - light, y0, light, y1 - y0));
            out.push(p(cx + light, y0, light, y1 - y0));
        } else {
            let t = thick(weight);
            out.push(p(cx + (light - t) / 2.0, y0, t, y1 - y0));
        }
    };
    // Each arm runs from the edge to past the center so the joints close.
    let reach = light * 2.0;
    if left > 0 {
        horizontal(&mut out, 0.0, cx + reach, left);
    }
    if right > 0 {
        horizontal(&mut out, (cx - light).max(0.0), w, right);
    }
    if up > 0 {
        vertical(&mut out, 0.0, cy + reach, up);
    }
    if down > 0 {
        vertical(&mut out, (cy - light).max(0.0), h, down);
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn half_blocks_fill_their_half_exactly() {
        assert_eq!(pieces('▀', 10.0, 21.0, 1.0), Some(vec![p(0.0, 0.0, 10.0, 11.0)]));
        assert_eq!(pieces('▄', 10.0, 21.0, 1.0), Some(vec![p(0.0, 10.0, 10.0, 11.0)]));
        assert_eq!(pieces('█', 10.0, 21.0, 1.0), Some(vec![p(0.0, 0.0, 10.0, 21.0)]));
        assert_eq!(pieces('▌', 10.0, 21.0, 1.0), Some(vec![p(0.0, 0.0, 5.0, 21.0)]));
    }

    #[test]
    fn horizontal_line_spans_the_cell() {
        let ps = pieces('─', 10.0, 20.0, 1.0).unwrap();
        let x0 = ps.iter().map(|p| p.x).fold(f32::MAX, f32::min);
        let x1 = ps.iter().map(|p| p.x + p.w).fold(0.0, f32::max);
        assert_eq!((x0, x1), (0.0, 10.0));
        assert!(ps.iter().all(|p| p.h == 1.0));
    }

    #[test]
    fn letters_are_left_to_the_font() {
        assert_eq!(pieces('a', 10.0, 20.0, 1.0), None);
        assert_eq!(pieces('⣿', 10.0, 20.0, 1.0), None);
    }
}
