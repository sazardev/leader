<!-- name: Accessibility -->
<!-- desc: usable by everyone: keyboard, screen readers, contrast, focus, motion and text size -->
<!-- for: all -->
<!-- design: forms dialogs navigation-shell -->

## Requirements

### Keyboard and focus

The system must be fully usable without a mouse, with a visible focus at all times.

- Given any screen, when a person uses only the keyboard, then they can reach and use every action in a logical order
- Given a dialog, when it opens, then focus moves into it, stays inside it and returns to where it was when it closes
- Given the focused element, when it changes, then it is clearly visible

### Screen readers and structure

The system must tell assistive technology what things are and what changes.

- Given a control or image, when a screen reader reads it, then it announces a meaningful name and role
- Given a message that appears (error, confirmation), when it shows, then it is announced without moving the person
- Given a form error, when it shows, then it names the field and says how to fix it

### Visual comfort

The system must stay readable for people with different eyes and preferences.

- Given any text or control, when it is shown, then its contrast meets the target below (proposed: WCAG 2.2 AA)
- Given a person who enlarges text (proposed: up to 200%), when they do, then nothing is cut off or overlaps
- Given a person who prefers reduced motion, when animations would run, then they are removed or made static
- Given information shown with color, when it matters, then it is also shown with text or a shape

## Edge cases

- [Keyboard and focus] A custom control (menu, date picker) only reacts to the mouse: it must also work with the keyboard
- [Screen readers and structure] Content that loads later (a list, a toast): its arrival is announced
- [Visual comfort] A person uses a high contrast or forced-colors mode: nothing important disappears
- [Keyboard and focus] A time limit (a session, a toast that vanishes): the person can extend it or it is not needed

## Open questions

- [Visual comfort] Which accessibility standard and level must the product meet (WCAG 2.2 AA, a law in your market)?
- [Screen readers and structure] Which screen readers and browsers must be tested?
- [Visual comfort] Are videos or audio part of the product, and do they need captions and transcripts?
