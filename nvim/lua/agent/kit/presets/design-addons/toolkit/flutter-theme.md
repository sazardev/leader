<!-- name: Flutter theme -->
<!-- desc: the design in Flutter terms: ColorScheme and TextTheme, ThemeExtension for the rest, widgets read Theme.of -->
<!-- for: gui -->
<!-- default: flutter -->

## Toolkit

| Design | Flutter |
| --- | --- |
| Color token | a `ColorScheme` role (`primary`, `surface`, `onSurfaceVariant`, `error`…); tokens with no role go in a `ThemeExtension` |
| Text style | a `TextTheme` slot (`titleLarge`, `bodyMedium`, `labelSmall`…), fonts from the design |
| Spacing / radius | constants in a `ThemeExtension` (`AppSpacing`, `AppRadii`) or one `tokens.dart`; never a literal in a widget |
| Dark mode | `theme` + `darkTheme` on `MaterialApp`, `themeMode` from settings |
| Shape | `cardTheme`, `filledButtonTheme`… set the radius once; widgets do not pass `shape` |
| Layout | `LayoutBuilder` / breakpoints for compact, medium, expanded widths |
| Motion | `AnimatedFoo` widgets and `Curves` from the design; `MediaQuery.disableAnimationsOf(context)` respected |

- `lib/theme/` holds the `ThemeData` builders and the extensions; widgets read `Theme.of(context)`.
- Golden tests (`matchesGoldenFile`) cover the main screens in light and dark.

## Rules for agents

- A widget never names a `Color(0x…)` or a font size: it reads the theme.
- New tokens go into the theme or an extension first.
