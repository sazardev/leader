<!-- name: Nerd Font icons -->
<!-- desc: file, git and status icons from Nerd Fonts, with text fallbacks when the font is missing -->
<!-- for: tui -->

## Typography

- Icons from Nerd Fonts v3 (e.g. `` folder, `` file, `` branch, `` error, `` warning, `` info), always followed by a space and a label.
- A setting or env var (e.g. `APP_ICONS=nerd|unicode|ascii`) chooses icons; default `unicode` unless a Nerd Font is detected or declared.

## Rules for agents

- Every icon has a Unicode and an ASCII fallback in the same table; never an icon without a label in a list.
