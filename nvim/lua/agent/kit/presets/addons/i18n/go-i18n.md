<!-- name: go-i18n -->
<!-- desc: Go localization with nicksnyder/go-i18n bundles, message IDs, CLDR plurals and x/text formatting -->
<!-- for: go -->

## Stack

| Internationalization | go-i18n v2 (`nicksnyder/go-i18n`, TOML/JSON message files embedded with `embed`, `golang.org/x/text/language`) | CLDR plurals and template data with no code generation |

## Project layout

```
internal/i18n/bundle.go        bundle setup, language matcher, Localizer per request
internal/i18n/active.en.toml   source messages (id, description, one/other)
internal/i18n/active.<lng>.toml  translations per language, loaded through go:embed
```

## Conventions

- Messages have stable IDs (`checkout.paid`) and a `description` for translators; the `en` file is the source.
- A `*i18n.Localizer` is created per request from `Accept-Language` / the user setting with `language.NewMatcher`; no global current language.
- Call sites use `localizer.Localize(&i18n.LocalizeConfig{MessageID: ..., TemplateData: ..., PluralCount: n})`; the text is not formatted before translation.
- Plurals use `one` / `other` (and more forms where the language needs them) in the message file.
- Number, currency and date formatting use `golang.org/x/text/message` printers for the same language tag.
- Errors for users are translated at the edge (handler); internal errors and logs stay in English.

## Commands

| i18n extract | `goi18n extract -format toml -outdir internal/i18n` |
| i18n merge | `goi18n merge -format toml -outdir internal/i18n internal/i18n/active.*.toml` |

## Testing

- A test loads every message file and checks each ID and template variable exists in every language.

## Rules for agents

- Never hardcode a user-facing string in handlers; add a message ID and translate it for every language.
- Never concatenate translated fragments; use `TemplateData`.
- Never panic on a missing translation; fall back to the default language and log it.
