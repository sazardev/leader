<!-- name: gettext -->
<!-- desc: PO/POT catalogs with gettext for Python, PHP and server-rendered apps; extraction and compile steps -->
<!-- for: python php ruby elixir -->

## Stack

| Internationalization | gettext (`.pot` template, one `.po` catalog per language, compiled `.mo`; `ngettext` for plurals) | Standard extraction and translator tooling that works outside any one framework |

## Project layout

```
locale/messages.pot            the template extracted from source (never edited by hand)
locale/<lng>/LC_MESSAGES/messages.po   translations per language; compiled to messages.mo
```

## Conventions

- Source strings are written in English inside `_("…")` / `gettext(…)`; use `ngettext(singular, plural, n)` for plurals and `pgettext` when a word needs context.
- Use named placeholders (`_("Hello %(name)s")`), never positional ones, so translators can reorder them.
- Never build a sentence from translated pieces; one message per sentence.
- Request-scoped language: the active locale is chosen per request (Accept-Language, user setting) and never stored in a global.
- Extract, merge and compile are scripted; `.pot` and `.po` are committed, compiled `.mo` files are built in CI or at deploy.
- CI fails when the `.pot` is out of date or a `.po` has fuzzy or untranslated entries for release languages.

## Commands

| i18n extract | `xgettext --from-code=UTF-8 -o locale/messages.pot <source files>` |
| i18n compile | `msgfmt -o locale/<lng>/LC_MESSAGES/messages.mo locale/<lng>/LC_MESSAGES/messages.po` |

## Testing

- Tests run with a fake locale and assert that plurals and placeholders render for every shipped language.

## Rules for agents

- Never translate inside the string (no f-strings or interpolation before the call); translate the template, then format.
- Never edit `messages.pot` by hand; regenerate it.
- Never commit `.mo` files if the build compiles them.
