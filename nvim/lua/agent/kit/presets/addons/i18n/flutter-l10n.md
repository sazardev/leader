<!-- name: Flutter gen-l10n -->
<!-- desc: Flutter localization with ARB files and generated AppLocalizations; plurals, placeholders, intl formats -->
<!-- for: flutter dart mobile -->

## Stack

| Internationalization | Flutter `gen-l10n` (ARB files in `lib/l10n/`, generated `AppLocalizations`, `intl`) | Official, typed, compile-time checked translations |

## Project layout

```
l10n.yaml                      arb-dir: lib/l10n, template-arb-file: app_en.arb, output-localization-file: app_localizations.dart
lib/l10n/app_en.arb            the template: keys, text, @key descriptions and placeholders
lib/l10n/app_<lng>.arb         one ARB per language (app_es.arb, app_pt.arb)
```

## Conventions

- `flutter: generate: true` in `pubspec.yaml`; `flutter_localizations` and `intl` are dependencies.
- `app_en.arb` is the template; every key has an `@key` entry with a `description` and typed `placeholders`.
- Strings are read with `AppLocalizations.of(context)!.<key>` (or `context.l10n` through an extension); no literal text in widgets.
- Plurals and selects use ICU syntax in the ARB (`{count, plural, =0{No items} one{1 item} other{{count} items}}`).
- Dates and numbers use `DateFormat` / `NumberFormat` with the current locale; placeholders declare `format`.
- `supportedLocales` and `localizationsDelegates` come from `AppLocalizations`; the app reacts to the system locale.
- Generated files in `.dart_tool` or `lib/l10n/app_localizations*.dart` are never edited by hand.

## Commands

| Generate l10n | `flutter gen-l10n` |

## Testing

- Widget tests pump the app with `AppLocalizations.delegate` and a test locale; a golden or finder per language catches overflow.

## Rules for agents

- Never hardcode a visible string; add the key to `app_en.arb` and every other ARB, then run `flutter gen-l10n`.
- Never edit generated `AppLocalizations` files.
- Never concatenate localized fragments; use placeholders.
