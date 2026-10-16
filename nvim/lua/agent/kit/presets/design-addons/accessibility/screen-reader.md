<!-- name: Screen reader first -->
<!-- desc: semantics before visuals: ARIA and landmarks in GUIs, a plain accessible mode in TUIs -->
<!-- for: all -->

## Accessibility

- GUI: semantic HTML/native controls first, landmarks, headings in order, every control named, live regions for async updates; tested with VoiceOver and NVDA/TalkBack.
- TUI: an accessible mode (flag or env var) prints linear text without box art, spinners or cursor tricks, one line per state change, readable by screen readers.

## Rules for agents

- Never convey state only visually; every icon-only control has an accessible name.
