<!-- name: Empty states -->
<!-- desc: first-use, no-results, error and no-permission states with one clear action -->
<!-- for: all -->

## Components

- Every empty state has three parts at most: a short title, one sentence of explanation, one primary action. No lorem, no jokes, no more than 2 lines of body.
- GUI: first-use: title names what will live here ("No projects yet"), the sentence says the benefit, the button creates the first one ("Create project"); a secondary text link to docs or import is allowed.
- GUI: no-results (search or filters): echo the query ("No results for "invoice 99""), suggest one fix ("Check spelling or clear filters") and offer "Clear filters" as the action.
- GUI: error: say what failed in plain words, keep the cause short, offer "Try again" as the primary action and keep any cached content visible if it exists.
- GUI: no-permission: say what is blocked and who can grant it ("Ask an admin for access"), with a "Request access" action when the product supports it; never show a bare 403.
- GUI: illustration is optional: a single flat 96-128 px spot illustration or icon in muted tones, centered above the title; inside small panels (under 240 px high) use the icon only or nothing.
- GUI: center the block in the container both ways; max width 360 px; a list or table keeps its header visible above the empty state.
- TUI: a centered dim block of 1-3 lines with the key hint in brackets: `No sessions yet. Press n to create one.`; no ASCII art.

## Accessibility

- The title is a real heading; the empty state is announced when it replaces content (`role="status"`); the action is reachable by keyboard and is the first focusable element in the region.

## Rules for agents

- One primary action per empty state, never two equal buttons.
- Distinguish "nothing exists", "nothing matches", "failed to load" and "not allowed"; never reuse one message for all.
- Copy is written in the product voice, active and specific: no "Oops", no "Nothing to see here".
