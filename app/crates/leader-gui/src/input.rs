//! Keyboard and mouse → Neovim's key notation (`nvim_input`, `nvim_input_mouse`).
use winit::keyboard::{Key, ModifiersState, NamedKey};

fn named(key: NamedKey) -> Option<&'static str> {
    Some(match key {
        NamedKey::Enter => "CR",
        NamedKey::Tab => "Tab",
        NamedKey::Backspace => "BS",
        NamedKey::Escape => "Esc",
        NamedKey::Delete => "Del",
        NamedKey::Insert => "Insert",
        NamedKey::Home => "Home",
        NamedKey::End => "End",
        NamedKey::PageUp => "PageUp",
        NamedKey::PageDown => "PageDown",
        NamedKey::ArrowUp => "Up",
        NamedKey::ArrowDown => "Down",
        NamedKey::ArrowLeft => "Left",
        NamedKey::ArrowRight => "Right",
        NamedKey::Space => "Space",
        NamedKey::F1 => "F1",
        NamedKey::F2 => "F2",
        NamedKey::F3 => "F3",
        NamedKey::F4 => "F4",
        NamedKey::F5 => "F5",
        NamedKey::F6 => "F6",
        NamedKey::F7 => "F7",
        NamedKey::F8 => "F8",
        NamedKey::F9 => "F9",
        NamedKey::F10 => "F10",
        NamedKey::F11 => "F11",
        NamedKey::F12 => "F12",
        _ => return None,
    })
}

/// A character as it must appear inside `<…>`.
fn in_brackets(c: &str) -> &str {
    match c {
        "<" => "lt",
        ">" => "gt",
        "\\" => "Bslash",
        "|" => "Bar",
        " " => "Space",
        "-" => "minus",
        other => other,
    }
}

fn prefix(mods: ModifiersState, shift: bool) -> String {
    let mut p = String::new();
    if mods.control_key() {
        p.push_str("C-");
    }
    if shift && mods.shift_key() {
        p.push_str("S-");
    }
    if mods.alt_key() {
        p.push_str("M-");
    }
    if mods.super_key() {
        p.push_str("D-");
    }
    p
}

/// Keys for `nvim_input`, or None for keys that type nothing (lone modifiers, unknown keys).
/// `text` is what the key produced with the layout applied (shift, AltGr, dead keys).
pub fn key(logical: &Key, text: Option<&str>, mods: ModifiersState) -> Option<String> {
    match logical {
        Key::Named(NamedKey::Space) if !(mods.control_key() || mods.alt_key() || mods.super_key()) => Some(" ".into()),
        Key::Named(k) => {
            let name = named(*k)?;
            let p = prefix(mods, true);
            Some(format!("<{p}{name}>"))
        }
        Key::Character(c) => {
            // AltGr reaches us as Ctrl+Alt on some hosts (Windows, WSLg): '@' on a Spanish layout is
            // AltGr+2. When the layout produced a printable character, that character is what was meant.
            let altgr = mods.control_key() && mods.alt_key() && text.is_some_and(|t| t != c.as_str() && !t.chars().any(char::is_control));
            if altgr {
                let t = text.unwrap_or(c);
                return Some(if t == "<" { "<lt>".into() } else { t.to_string() });
            }
            if mods.control_key() || mods.alt_key() || mods.super_key() {
                // Shift is already in the character ('A', '?'), so it is not repeated as S-.
                Some(format!("<{}{}>", prefix(mods, false), in_brackets(c)))
            } else {
                let t = text.unwrap_or(c);
                Some(if t == "<" { "<lt>".into() } else { t.to_string() })
            }
        }
        _ => text.filter(|t| !t.chars().any(char::is_control)).map(|t| t.replace('<', "<lt>")),
    }
}

/// Modifier argument of `nvim_input_mouse`.
pub fn mouse_mods(mods: ModifiersState) -> String {
    let mut m = String::new();
    if mods.control_key() {
        m.push_str("C-");
    }
    if mods.shift_key() {
        m.push_str("S-");
    }
    if mods.alt_key() {
        m.push_str("A-");
    }
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ch(s: &str) -> Key {
        Key::Character(s.into())
    }

    #[test]
    fn plain_text_passes_through() {
        assert_eq!(key(&ch("a"), Some("a"), ModifiersState::empty()).as_deref(), Some("a"));
        assert_eq!(key(&ch("A"), Some("A"), ModifiersState::SHIFT).as_deref(), Some("A"));
        assert_eq!(key(&ch("<"), Some("<"), ModifiersState::SHIFT).as_deref(), Some("<lt>"));
        assert_eq!(key(&Key::Named(NamedKey::Space), Some(" "), ModifiersState::empty()).as_deref(), Some(" "));
    }

    #[test]
    fn modifiers_build_notation() {
        assert_eq!(key(&ch("w"), None, ModifiersState::CONTROL).as_deref(), Some("<C-w>"));
        assert_eq!(key(&ch("A"), None, ModifiersState::CONTROL | ModifiersState::SHIFT).as_deref(), Some("<C-A>"));
        assert_eq!(key(&ch("x"), None, ModifiersState::ALT).as_deref(), Some("<M-x>"));
        assert_eq!(key(&ch("\\"), None, ModifiersState::CONTROL).as_deref(), Some("<C-Bslash>"));
        assert_eq!(key(&Key::Named(NamedKey::Tab), None, ModifiersState::SHIFT).as_deref(), Some("<S-Tab>"));
        assert_eq!(key(&Key::Named(NamedKey::Space), None, ModifiersState::CONTROL).as_deref(), Some("<C-Space>"));
        assert_eq!(key(&Key::Named(NamedKey::Enter), None, ModifiersState::empty()).as_deref(), Some("<CR>"));
    }

    #[test]
    fn altgr_as_ctrl_alt_types_its_character() {
        let ca = ModifiersState::CONTROL | ModifiersState::ALT;
        assert_eq!(key(&ch("2"), Some("@"), ca).as_deref(), Some("@"));
        assert_eq!(key(&ch("x"), None, ca).as_deref(), Some("<C-M-x>"));
    }

    #[test]
    fn lone_modifiers_type_nothing() {
        assert_eq!(key(&Key::Named(NamedKey::Shift), None, ModifiersState::SHIFT), None);
        assert_eq!(key(&Key::Named(NamedKey::Control), None, ModifiersState::CONTROL), None);
    }
}
