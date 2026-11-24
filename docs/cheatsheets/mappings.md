# Mappings

**Mappings** is Leader's live shortcut finder. Open it with `<leader>ch`, `:Cheatsheet`, the start screen's **Mappings** button or **Help → Keymap Finder…**.

It reads the same real mappings as [`CHEATSHEET.md`](../../CHEATSHEET.md): global shortcuts, every contextual leader menu, LSP keys, blink.cmp, nvim-tree and a small native Neovim section. Nothing in the view is a hand-maintained key table.

## Reading the screen

- **Left:** mappings grouped by menu or feature. The badge is the mode (`N` Normal, `V` Visual, `O` Operator-pending, `I` Insert, `T` Terminal). The number beside a group is its result count.
- **Right:** the selected key, its action, where it applies, a concrete **Example**, detailed **Usage**, numbered **Steps**, the expected **Result** and practical **Notes**. Scroll the pane when the explanation is longer than the window.
- **Bottom:** a live search input above the active language, modes, sources and order. The chips are buttons.

On a narrow terminal the list and detail pane take turns instead of squeezing both into the window.

## Find anything

Press `/` or click the search bar under the list, then type. The input is live: every keystroke updates the results, count and detail pane immediately, without a modal or an Enter press. Every word must match somewhere in the row, so `go race` finds the Go race-test command without needing to remember its exact key. Search covers:

- the key notation and action;
- language, menu, mode, source and availability;
- the example and usage text.

`Enter` keeps the query and returns to the list. `Esc` clears it and returns; `Ctrl+U` clears it while staying in the input. `r` clears the search and every filter at once.

### Useful searches

- `save` — saving, sessions and write-related actions.
- `go test` — Go test commands.
- `race` — actions whose example or command mentions race detection.
- `visual` — mappings that also apply to a selection.
- `completion` — blink.cmp controls.
- `tree rename` — nvim-tree rename actions.

## Language, filters and order

- `l` chooses a language. **All languages** includes everything; **Global** contains shared shortcuts; a language shows its contextual menu.
- `f` opens the mode and source checklist. Modes and sources are independent, so you can combine, for example, Visual + Leader menus.
- `s` orders by key ascending or descending, action, language or mode. Ordering applies inside each visible group.
- `Tab` folds or unfolds the group under the cursor. `{` and `}` jump between groups.
- `r` returns to all languages, all modes, all sources, empty search and key order.

## Mouse

Mouse support works in the desktop app and in terminals with mouse reporting enabled:

- move over a row to preview its details without clicking;
- click a row to open and focus its detail pane;
- click a group title to fold or unfold it;
- click **Copy**, **Search** or **Language** in the detail pane;
- click the live search bar and type directly;
- click any chip in the bottom strip;
- use the mouse in the language picker, sort picker and filter checklist.

Chips take the primary color under the pointer. Hover never scrolls the list away from the mouse.

## Examples and usage

Every mapping has an example, including ones without a curated recipe. Precise recipes live in `lua/cheatsheet/examples.lua` for common workflows such as saving, finding files, Go tests, LSP navigation, commits and the inline agent. The fallback derives a useful example from the action, mode, language and source, so a new mapping never appears as an empty detail.

Examples describe the situation in which to press the key. Usage explains the workflow and why it is useful; Steps give a numbered procedure; Result says what you should see; Notes cover prerequisites, shortcuts, safety and common pitfalls. Common actions have curated recipes, while every other mapping receives a deterministic workflow generated from its action, mode, language and source.

## Keyboard reference

- `j` / `k` or arrows move through mappings.
- `Enter` or `l` opens the detail pane; `h` or `Esc` goes back.
- `q` closes the finder from the list.
- `/` focuses the live search; results change as you type. `Enter` keeps the query, `Esc` clears it and `Ctrl+U` clears it in place.
- `l` chooses language; `f` filters; `s` orders; `r` resets.
- `y` copies the selected key notation.
- `?` opens the complete help, including mouse controls.

## Maintenance

The view is split by responsibility:

- `utils/cheatsheet.lua` collects and deduplicates the real mappings.
- `cheatsheet/model.lua` performs pure search, filtering, grouping and ordering.
- `cheatsheet/examples.lua` supplies curated examples plus deterministic usage, numbered steps, expected results and notes for every mapping.
- `cheatsheet/init.lua` draws the view and connects keyboard and mouse actions.
- `utils/market.lua` provides the shared full-screen list, detail pane, folding, mouse behavior and optional `live_input` row with `TextChangedI` updates.
- `ui/flat/groups.lua` owns the colors; the view never hardcodes a theme color.

When adding a shortcut, give its `desc` at least two words starting with its section. If the action deserves a better explanation, add a recipe to `examples.lua`; otherwise the fallback already covers it.

Run `scripts/test-cheatsheet.sh` after changing the model, examples or view. It checks filtering, ordering, examples, mouse actions, real windows and collection against the installed config.
