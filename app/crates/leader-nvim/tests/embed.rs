//! Against a real `nvim --embed --clean`: the protocol, the screen model and Neovim calling the UI back.
//! Needs only nvim on PATH (no window, no GPU).
use std::time::{Duration, Instant};

use leader_nvim::{Nvim, Screen, Spawn};
use rmpv::Value;

fn start(cols: u32, rows: u32) -> (Nvim, Screen) {
    let spec = Spawn { args: vec!["--clean".into(), "-n".into()], ..Default::default() };
    let handler = Box::new(|method: &str, args: &[Value]| match method {
        "echo" => Ok(args.first().cloned().unwrap_or(Value::Nil)),
        _ => Err(Value::from("unknown")),
    });
    let mut nvim = Nvim::spawn(spec, handler, Box::new(|| {})).expect("nvim on PATH");
    nvim.attach(cols, rows).expect("attach");
    let mut screen = Screen::default();
    settle(&nvim, &mut screen);
    (nvim, screen)
}

/// Applies events until Neovim has been quiet for a moment after a flush.
fn settle(nvim: &Nvim, screen: &mut Screen) {
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut flushed = false;
    while Instant::now() < deadline {
        match nvim.events().recv_timeout(Duration::from_millis(if flushed { 80 } else { 2000 })) {
            Ok(batch) => {
                for ev in batch {
                    flushed |= screen.apply(ev);
                }
            }
            Err(_) if flushed => return,
            Err(_) => {}
        }
    }
}

fn text_at(screen: &Screen, grid: u64, row: u32) -> String {
    screen.grids[&grid].row_text(row)
}

#[test]
fn windows_and_floats_are_placed_like_neovim_composes_them() {
    let (mut nvim, mut screen) = start(40, 12);
    nvim.exec_lua(
        r#"
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello leader" })
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "float!" })
        vim.api.nvim_open_win(buf, false, { relative = "editor", row = 3, col = 7, width = 10, height = 2, style = "minimal" })
        "#,
        vec![],
    )
    .unwrap();
    settle(&nvim, &mut screen);

    let layers = screen.layers();
    let win = layers.iter().find(|l| !l.floating && l.id != 1).expect("a window grid");
    assert_eq!(text_at(&screen, win.id, 0), "hello leader");
    let float = layers.iter().find(|l| l.floating && l.grid.width == 10).expect("the float");
    assert_eq!((float.row, float.col), (3.0, 7.0));
    assert_eq!(text_at(&screen, float.id, 0), "float!");
    // Above the windows (the message grid, zindex 200, may still be above the float's 50).
    let index = |id| layers.iter().position(|l| l.id == id).unwrap();
    assert!(index(float.id) > index(win.id), "the float is above the window");
    // A click on the float's cell lands on the float's grid.
    assert_eq!(screen.grid_at(3.0, 8.0), Some((float.id, 0, 1)));
}

#[test]
fn neovim_can_call_the_ui_back() {
    let (mut nvim, _screen) = start(30, 8);
    let chan = nvim.channel().unwrap();
    let got = nvim.exec_lua("return vim.rpcrequest(..., 'echo', 'pong')", vec![chan.into()]).unwrap();
    assert_eq!(got.as_str(), Some("pong"));
}

#[test]
fn resize_reaches_the_root_grid() {
    let (nvim, mut screen) = start(30, 8);
    nvim.try_resize(50, 15).unwrap();
    settle(&nvim, &mut screen);
    let root = &screen.grids[&1];
    assert_eq!((root.width, root.height), (50, 15));
}

#[test]
fn pointer_moves_reach_neovim_when_it_asks_for_them() {
    // what hover is built on: with 'mousemoveevent' on, a "move" from the UI is a <MouseMove> key with the position
    let (mut nvim, mut screen) = start(40, 10);
    nvim.exec_lua(
        r#"
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d" })
        vim.o.mousemoveevent = true
        vim.keymap.set("n", "<MouseMove>", function() vim.g.hovered = vim.fn.getmousepos().line end)
        "#,
        vec![],
    )
    .unwrap();
    settle(&nvim, &mut screen);
    assert_eq!(screen.options.get("mousemoveevent").and_then(Value::as_bool), Some(true), "the UI is told the option");
    let win = screen.layers().iter().find(|l| !l.floating && l.id != 1).map(|l| l.id).unwrap();
    nvim.notify("nvim_input_mouse", vec!["move".into(), "".into(), "".into(), win.into(), 2.into(), 0.into()]).unwrap();
    std::thread::sleep(Duration::from_millis(150));
    let got = nvim.request("nvim_get_var", vec!["hovered".into()]).unwrap();
    assert_eq!(got.as_u64(), Some(3));
}
