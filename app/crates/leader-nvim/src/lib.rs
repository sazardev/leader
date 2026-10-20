//! Neovim link for the Leader desktop app: msgpack-rpc over `nvim --embed`,
//! `redraw` events parsed into typed events, and the screen state they build
//! (grids, windows, floats, highlights, cursor). No window and no GPU here,
//! so all of it is testable headless.

pub mod event;
pub mod grid;
pub mod rpc;
pub mod screen;

pub use event::{Attr, CursorShape, Event};
pub use grid::{Cell, Grid};
pub use rpc::{Handler, Nvim, RpcError, Spawn, Waker};
pub use screen::{Layer, Screen};
