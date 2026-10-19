<!-- name: Onboarding -->
<!-- desc: first-run flow, setup checklist, progressive disclosure, skip and resume -->
<!-- for: all -->

## Components

- Get to the first useful result in the fewest steps: ask only what the product cannot work without (3 steps or fewer); everything else is asked later in context.
- GUI: a multi-step flow shows "Step 2 of 4" with a progress bar at the top; each step has one question, one primary button ("Continue") and a "Skip" text button when the step is optional; "Back" always works and keeps answers.
- GUI: a setup checklist (3-6 items) lives on the home screen in a card: each item is a verb ("Invite a teammate"), shows done state with a check, links straight to where it is done, and the card can be dismissed and reopened from the help menu.
- GUI: progress persists on the server per user; closing the app mid-flow resumes at the last step with "Pick up where you left off".
- GUI: tooltips or coach marks are limited to 1 at a time, anchored to the element, 3 steps maximum per tour, with "Next", "Skip tour" and a dot indicator; never block the interface behind a full-screen overlay.
- GUI: prefer sample data or a prefilled template over empty screens; mark sample data clearly and make it removable in one action.
- GUI: reveal advanced features progressively: show them when the user first needs them, with a one-line hint the first time only.
- TUI: first run prints a short welcome with the 3 keys that matter (`?` help, `:` commands, `q` quit) and a prompt to continue; a `--no-intro` flag or saved flag skips it forever.
- TUI: setup questions are prompts with a visible default in brackets; Enter accepts it; Ctrl+C aborts without writing partial config.

## Accessibility

- Tours and flows are fully keyboard operable, focus moves to each new step's heading, and nothing auto-advances on a timer.

## Rules for agents

- Every onboarding step is skippable or has a sensible default, except account basics.
- Never show the same hint twice once dismissed; store dismissal per user.
- Never ask for permissions (notifications, location, camera) before the moment the feature needs them, and explain why first.
