<!-- name: Notification center -->
<!-- desc: bell, unread count, list, mark as read, grouping and preferences -->
<!-- for: all -->

## Components

- GUI: a bell icon button in the top bar, 40 px target, with a badge showing the unread count (cap at "99+"); a dot instead of a number when counts are not meaningful; the badge clears per item as read, not all at once on open.
- GUI: clicking opens a popover (400 px wide, max 560 px high) on wide screens or a full screen on narrow ones; header "Notifications" with "Mark all as read" and a settings icon; tabs "All" and "Unread" with counts.
- GUI: each item: actor avatar, one-line sentence with the bold object ("Ana commented on Roadmap"), a 2-line preview at most, relative time, an unread dot and tinted surface; clicking marks it read and goes to the exact place; a "..." menu offers Mark as unread, Mute thread, Delete.
- GUI: group by day (Today, Yesterday, Earlier) and collapse bursts of the same kind ("5 people reacted to your post"); important items (mentions, approvals, failures) are not collapsed or muted by defaults.
- GUI: new notifications arriving live update the badge and prepend without moving what the user is reading; do not play sounds or show desktop alerts unless the user has opted in.
- GUI: empty state: "You are all caught up" with a link to preferences; loading shows 5 skeleton rows; load more on scroll with a page size of 20 and a retention window stated ("Showing the last 30 days").
- GUI: preferences are a matrix of event type by channel (In-app, Email, Push) with toggles, an email digest option (instant, daily, weekly), quiet hours, and a per-project override; sensible defaults: only direct events are on by default.
- GUI: unsubscribe links in emails work in one click without login and say exactly what will stop.
- TUI: a status-line counter `3 unread`, `N` opens the list, `Enter` opens the item, `m` marks read, `M` marks all, `x` dismisses; no popups interrupting typing.

## Accessibility

- The bell button name includes the count ("Notifications, 3 unread"); the list uses semantic lists; new items are announced politely and rate-limited so a burst is one announcement.

## Rules for agents

- Every notification links to what caused it and is actionable or informational, never both vague and urgent.
- Never notify the actor about their own action.
