<!-- name: Comments and threads -->
<!-- desc: comment list, composer, mentions, edit/delete states and replies -->
<!-- for: all -->

## Components

- GUI: comment item: 32 px avatar, author name (medium weight), relative time ("2h ago", full timestamp on hover), body text at 14-15 px, actions row below (Reply, React, "..." menu); items separated by 16-24 px, not boxed.
- GUI: replies nest one level only, indented 40 px with a thin left rule; deeper replies attach to the same thread with an "@name" prefix; long threads collapse to "Show 6 more replies".
- GUI: composer sits at the bottom of the list or inline under the item being replied to; starts as a single-line field and grows up to 8 lines; the Send button is disabled when empty and the shortcut Cmd/Ctrl+Enter sends; Esc with text asks before discarding.
- GUI: mentions: typing "@" opens a list of people (max 6, avatar and name, filtered as typed), Enter or Tab inserts a chip; mentioned people are notified once; nonmembers cannot be mentioned without a warning.
- GUI: posting is optimistic: the comment appears at once with a muted "Sending..." state; on failure it stays with "Not sent. Retry" and the text is never lost.
- GUI: edit: the body becomes a composer prefilled with the text, "Save" and "Cancel"; edited comments show "(edited)"; delete asks for confirmation and, when it has replies, keeps a "Comment deleted" placeholder so the thread stays readable.
- GUI: permissions: authors edit and delete their own, moderators any; disabled actions are hidden rather than shown disabled; closed or locked threads show a notice instead of the composer.
- GUI: empty: "No comments yet. Start the discussion." with the composer focused-ready; loading shows 3 skeleton items; new comments arriving live show a "New comments" pill rather than shifting the viewport.
- TUI: comments as indented blocks with `author  time` headers, `r` replies, `e` edits, `d` deletes with a confirmation, the composer opens in `$EDITOR` for multi-line text.

## Accessibility

- The list is a landmark with a heading and count; a new comment is announced politely; the mention popup is a combobox; icon-only actions have names that include the author ("Reply to Ana").

## Rules for agents

- Never lose a draft: keep it per thread until sent or explicitly discarded.
- Escape user content; render links and mentions from parsed data, never raw HTML.
