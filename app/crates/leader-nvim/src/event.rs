use rmpv::Value;
use smol_str::SmolStr;

/// A cell run of a `grid_line`: `text` repeated `repeat` times, with `hl` when the event carried one
/// (otherwise the previous cell's highlight continues).
#[derive(Debug, Clone, PartialEq)]
pub struct Cell {
    pub text: SmolStr,
    pub hl: Option<u32>,
    pub repeat: u32,
}

/// Highlight attributes of `hl_attr_define` (rgb part). Colors are 0xRRGGBB.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Attr {
    pub fg: Option<u32>,
    pub bg: Option<u32>,
    pub sp: Option<u32>,
    pub reverse: bool,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub undercurl: bool,
    pub underdouble: bool,
    pub underdotted: bool,
    pub underdashed: bool,
    pub strikethrough: bool,
    /// 0..=100 (`winblend`/`pumblend`), 100 = fully transparent background.
    pub blend: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CursorShape {
    #[default]
    Block,
    Horizontal,
    Vertical,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ModeInfo {
    pub name: String,
    pub shape: CursorShape,
    /// Size of horizontal/vertical cursors, 1..=100.
    pub percentage: u32,
    pub attr_id: u32,
    /// Blink timings in ms (`guicursor` blinkwait/blinkon/blinkoff); 0 = no blinking.
    pub blinkwait: u32,
    pub blinkon: u32,
    pub blinkoff: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Anchor {
    NW,
    NE,
    SW,
    SE,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    GridResize {
        grid: u64,
        width: u32,
        height: u32,
    },
    GridLine {
        grid: u64,
        row: u32,
        col: u32,
        cells: Vec<Cell>,
    },
    GridClear {
        grid: u64,
    },
    GridDestroy {
        grid: u64,
    },
    GridCursorGoto {
        grid: u64,
        row: u32,
        col: u32,
    },
    GridScroll {
        grid: u64,
        top: u32,
        bot: u32,
        left: u32,
        right: u32,
        rows: i32,
    },
    DefaultColors {
        fg: u32,
        bg: u32,
        sp: u32,
    },
    HlAttrDefine {
        id: u32,
        attr: Attr,
    },
    ModeInfoSet {
        cursor_style_enabled: bool,
        modes: Vec<ModeInfo>,
    },
    ModeChange {
        mode: String,
        index: u32,
    },
    WinPos {
        grid: u64,
        row: u32,
        col: u32,
        width: u32,
        height: u32,
    },
    WinFloatPos {
        grid: u64,
        anchor: Anchor,
        anchor_grid: u64,
        row: f32,
        col: f32,
        zindex: i64,
    },
    WinHide {
        grid: u64,
    },
    WinClose {
        grid: u64,
    },
    MsgSetPos {
        grid: u64,
        row: u32,
        zindex: i64,
    },
    OptionSet {
        name: String,
        value: Value,
    },
    SetTitle {
        title: String,
    },
    Busy(bool),
    MouseOn(bool),
    Flush,
    /// Any event the app does not draw yet; kept by name so the gaps stay visible.
    Other(String),
}

fn num(v: Option<&Value>) -> u64 {
    v.and_then(|v| v.as_u64().or_else(|| v.as_i64().map(|i| i as u64))).unwrap_or(0)
}

fn int(v: Option<&Value>) -> i64 {
    v.and_then(|v| v.as_i64().or_else(|| v.as_u64().map(|u| u as i64))).unwrap_or(0)
}

fn float(v: Option<&Value>) -> f32 {
    v.and_then(|v| v.as_f64().or_else(|| v.as_i64().map(|i| i as f64))).unwrap_or(0.0) as f32
}

fn text(v: Option<&Value>) -> String {
    v.and_then(Value::as_str).unwrap_or_default().to_string()
}

/// Parses the params of a `redraw` notification: `[[name, args...], ...]`.
pub fn parse_redraw(params: &Value) -> Vec<Event> {
    let mut out = Vec::new();
    for batch in params.as_array().into_iter().flatten() {
        let Some(items) = batch.as_array() else { continue };
        let Some(name) = items.first().and_then(Value::as_str) else { continue };
        for call in &items[1..] {
            let Some(a) = call.as_array() else { continue };
            if let Some(ev) = parse_one(name, a) {
                out.push(ev);
            }
        }
    }
    out
}

fn parse_attr(map: &Value) -> Attr {
    let mut attr = Attr::default();
    for (k, v) in map.as_map().into_iter().flatten() {
        let on = v.as_bool().unwrap_or(false);
        match k.as_str().unwrap_or_default() {
            "foreground" => attr.fg = Some(num(Some(v)) as u32),
            "background" => attr.bg = Some(num(Some(v)) as u32),
            "special" => attr.sp = Some(num(Some(v)) as u32),
            "reverse" => attr.reverse = on,
            "bold" => attr.bold = on,
            "italic" => attr.italic = on,
            "underline" => attr.underline = on,
            "undercurl" => attr.undercurl = on,
            "underdouble" => attr.underdouble = on,
            "underdotted" => attr.underdotted = on,
            "underdashed" => attr.underdashed = on,
            "strikethrough" => attr.strikethrough = on,
            "blend" => attr.blend = num(Some(v)).min(100) as u8,
            _ => {}
        }
    }
    attr
}

fn parse_mode(map: &Value) -> ModeInfo {
    let mut mode = ModeInfo { percentage: 100, ..Default::default() };
    for (k, v) in map.as_map().into_iter().flatten() {
        match k.as_str().unwrap_or_default() {
            "name" => mode.name = text(Some(v)),
            "cursor_shape" => {
                mode.shape = match v.as_str() {
                    Some("horizontal") => CursorShape::Horizontal,
                    Some("vertical") => CursorShape::Vertical,
                    _ => CursorShape::Block,
                }
            }
            "cell_percentage" => mode.percentage = num(Some(v)).clamp(1, 100) as u32,
            "attr_id" => mode.attr_id = num(Some(v)) as u32,
            "blinkwait" => mode.blinkwait = num(Some(v)) as u32,
            "blinkon" => mode.blinkon = num(Some(v)) as u32,
            "blinkoff" => mode.blinkoff = num(Some(v)) as u32,
            _ => {}
        }
    }
    mode
}

fn parse_one(name: &str, a: &[Value]) -> Option<Event> {
    let g = |i: usize| num(a.get(i));
    Some(match name {
        "flush" => Event::Flush,
        "grid_resize" => Event::GridResize { grid: g(0), width: g(1) as u32, height: g(2) as u32 },
        "grid_clear" => Event::GridClear { grid: g(0) },
        "grid_destroy" => Event::GridDestroy { grid: g(0) },
        "grid_cursor_goto" => Event::GridCursorGoto { grid: g(0), row: g(1) as u32, col: g(2) as u32 },
        "grid_scroll" => Event::GridScroll {
            grid: g(0),
            top: g(1) as u32,
            bot: g(2) as u32,
            left: g(3) as u32,
            right: g(4) as u32,
            rows: int(a.get(5)) as i32,
        },
        "default_colors_set" => Event::DefaultColors { fg: g(0) as u32, bg: g(1) as u32, sp: g(2) as u32 },
        "hl_attr_define" => Event::HlAttrDefine { id: g(0) as u32, attr: parse_attr(a.get(1)?) },
        "mode_info_set" => Event::ModeInfoSet {
            cursor_style_enabled: a.first()?.as_bool().unwrap_or(true),
            modes: a.get(1)?.as_array()?.iter().map(parse_mode).collect(),
        },
        "mode_change" => Event::ModeChange { mode: text(a.first()), index: g(1) as u32 },
        "win_pos" => Event::WinPos { grid: g(0), row: g(2) as u32, col: g(3) as u32, width: g(4) as u32, height: g(5) as u32 },
        "win_float_pos" => Event::WinFloatPos {
            grid: g(0),
            anchor: match a.get(2)?.as_str()? {
                "NE" => Anchor::NE,
                "SW" => Anchor::SW,
                "SE" => Anchor::SE,
                _ => Anchor::NW,
            },
            anchor_grid: g(3),
            row: float(a.get(4)),
            col: float(a.get(5)),
            zindex: a.get(7).map(|v| int(Some(v))).unwrap_or(50),
        },
        "win_hide" => Event::WinHide { grid: g(0) },
        "win_close" => Event::WinClose { grid: g(0) },
        "msg_set_pos" => Event::MsgSetPos { grid: g(0), row: g(1) as u32, zindex: a.get(4).map(|v| int(Some(v))).unwrap_or(200) },
        "option_set" => Event::OptionSet { name: text(a.first()), value: a.get(1).cloned().unwrap_or(Value::Nil) },
        "set_title" => Event::SetTitle { title: text(a.first()) },
        "busy_start" => Event::Busy(true),
        "busy_stop" => Event::Busy(false),
        "mouse_on" => Event::MouseOn(true),
        "mouse_off" => Event::MouseOn(false),
        "grid_line" => {
            let cells = a
                .get(3)?
                .as_array()?
                .iter()
                .filter_map(|c| {
                    let c = c.as_array()?;
                    Some(Cell {
                        text: SmolStr::new(c.first()?.as_str()?),
                        hl: c.get(1).map(|v| num(Some(v)) as u32),
                        repeat: c.get(2).map(|v| num(Some(v)) as u32).unwrap_or(1),
                    })
                })
                .collect();
            Event::GridLine { grid: g(0), row: g(1) as u32, col: g(2) as u32, cells }
        }
        other => Event::Other(other.to_string()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn arr(v: Vec<Value>) -> Value {
        Value::Array(v)
    }

    #[test]
    fn grid_line_keeps_repeat_and_optional_hl() {
        let raw = arr(vec![arr(vec![
            "grid_line".into(),
            arr(vec![
                1.into(),
                0.into(),
                2.into(),
                arr(vec![arr(vec!["a".into(), 3.into()]), arr(vec!["b".into()]), arr(vec![" ".into(), 0.into(), 4.into()])]),
                false.into(),
            ]),
        ])]);
        let evs = parse_redraw(&raw);
        assert_eq!(
            evs,
            vec![Event::GridLine {
                grid: 1,
                row: 0,
                col: 2,
                cells: vec![
                    Cell { text: "a".into(), hl: Some(3), repeat: 1 },
                    Cell { text: "b".into(), hl: None, repeat: 1 },
                    Cell { text: " ".into(), hl: Some(0), repeat: 4 },
                ],
            }]
        );
    }

    #[test]
    fn batches_hold_several_calls_and_flush() {
        let raw =
            arr(vec![arr(vec!["grid_clear".into(), arr(vec![1.into()]), arr(vec![2.into()])]), arr(vec!["flush".into(), arr(vec![])])]);
        assert_eq!(parse_redraw(&raw), vec![Event::GridClear { grid: 1 }, Event::GridClear { grid: 2 }, Event::Flush]);
    }

    #[test]
    fn hl_attr_and_float_pos() {
        let map = Value::Map(vec![("foreground".into(), 0xff0000.into()), ("bold".into(), true.into()), ("blend".into(), 30.into())]);
        let raw = arr(vec![
            arr(vec!["hl_attr_define".into(), arr(vec![7.into(), map, Value::Map(vec![]), arr(vec![])])]),
            arr(vec![
                "win_float_pos".into(),
                arr(vec![4.into(), Value::Nil, "SE".into(), 2.into(), 10.5.into(), 3.into(), true.into(), 60.into()]),
            ]),
        ]);
        let evs = parse_redraw(&raw);
        assert_eq!(evs[0], Event::HlAttrDefine { id: 7, attr: Attr { fg: Some(0xff0000), bold: true, blend: 30, ..Default::default() } });
        assert_eq!(evs[1], Event::WinFloatPos { grid: 4, anchor: Anchor::SE, anchor_grid: 2, row: 10.5, col: 3.0, zindex: 60 });
    }
}
