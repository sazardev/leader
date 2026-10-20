use smol_str::SmolStr;

use crate::event::Cell as Run;

#[derive(Debug, Clone, PartialEq)]
pub struct Cell {
    /// The cell's grapheme; "" for the right half of a double-width character.
    pub text: SmolStr,
    pub hl: u32,
}

impl Default for Cell {
    fn default() -> Self {
        Cell { text: SmolStr::new_static(" "), hl: 0 }
    }
}

/// One Neovim grid: a rectangle of cells. `Screen` routes the grid events here.
#[derive(Debug, Default, Clone)]
pub struct Grid {
    pub width: u32,
    pub height: u32,
    pub cells: Vec<Cell>,
}

impl Grid {
    pub fn new(width: u32, height: u32) -> Grid {
        Grid { width, height, cells: vec![Cell::default(); (width * height) as usize] }
    }

    pub fn row(&self, row: u32) -> &[Cell] {
        let w = self.width as usize;
        let start = row as usize * w;
        &self.cells[start..start + w]
    }

    pub fn row_text(&self, row: u32) -> String {
        self.row(row).iter().map(|c| c.text.as_str()).collect::<String>().trim_end().to_string()
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == self.width && height == self.height {
            return;
        }
        let mut next = Grid::new(width, height);
        for r in 0..self.height.min(height) {
            for c in 0..self.width.min(width) {
                next.cells[(r * width + c) as usize] = self.cells[(r * self.width + c) as usize].clone();
            }
        }
        *self = next;
    }

    pub fn clear(&mut self) {
        self.cells.iter_mut().for_each(|c| *c = Cell::default());
    }

    pub fn put_line(&mut self, row: u32, col: u32, runs: &[Run]) {
        if row >= self.height {
            return;
        }
        let mut x = col;
        let mut hl = 0;
        for run in runs {
            hl = run.hl.unwrap_or(hl);
            for _ in 0..run.repeat {
                if x >= self.width {
                    return;
                }
                self.cells[(row * self.width + x) as usize] = Cell { text: run.text.clone(), hl };
                x += 1;
            }
        }
    }

    /// `grid_scroll`: moves the region's rows up (`rows > 0`) or down; the rows left behind keep
    /// their old content, Neovim redraws them right after.
    pub fn scroll(&mut self, top: u32, bot: u32, left: u32, right: u32, rows: i32) {
        let (bot, right) = (bot.min(self.height), right.min(self.width));
        let w = self.width as usize;
        let copy = |g: &mut Grid, src: i64, dst: i64| {
            let (s, d) = (src as usize * w, dst as usize * w);
            for c in left as usize..right as usize {
                g.cells[d + c] = g.cells[s + c].clone();
            }
        };
        let (top, bot, rows) = (top as i64, bot as i64, rows as i64);
        if rows > 0 {
            for dst in top..bot - rows {
                copy(self, dst + rows, dst);
            }
        } else {
            for dst in (top - rows..bot).rev() {
                copy(self, dst + rows, dst);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn runs(s: &str) -> Vec<Run> {
        s.chars().map(|c| Run { text: SmolStr::new(c.to_string()), hl: Some(1), repeat: 1 }).collect()
    }

    fn grid(lines: &[&str]) -> Grid {
        let mut g = Grid::new(lines[0].len() as u32, lines.len() as u32);
        for (i, l) in lines.iter().enumerate() {
            g.put_line(i as u32, 0, &runs(l));
        }
        g
    }

    #[test]
    fn scroll_up_moves_rows() {
        let mut g = grid(&["abc", "def", "ghi"]);
        g.scroll(0, 3, 0, 3, 1);
        assert_eq!((g.row_text(0), g.row_text(1)), ("def".into(), "ghi".into()));
    }

    #[test]
    fn scroll_down_moves_rows() {
        let mut g = grid(&["abc", "def", "ghi"]);
        g.scroll(0, 3, 0, 3, -1);
        assert_eq!((g.row_text(1), g.row_text(2)), ("abc".into(), "def".into()));
    }

    #[test]
    fn scroll_keeps_columns_outside_the_region() {
        let mut g = grid(&["abc", "def"]);
        g.scroll(0, 2, 1, 3, 1);
        assert_eq!(g.row_text(0), "aef");
    }

    #[test]
    fn repeat_fills_and_clips() {
        let mut g = Grid::new(4, 1);
        g.put_line(0, 2, &[Run { text: "x".into(), hl: None, repeat: 9 }]);
        assert_eq!(g.row_text(0), "  xx");
    }

    #[test]
    fn resize_keeps_the_overlap() {
        let mut g = grid(&["abc", "def"]);
        g.resize(2, 3);
        assert_eq!((g.row_text(0), g.row_text(1), g.row_text(2)), ("ab".into(), "de".into(), "".into()));
    }
}
