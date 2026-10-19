<!-- name: Languages, time zones and currencies -->
<!-- desc: texts in several languages, dates and numbers in the person's format -->
<!-- for: all -->
<!-- tech: i18n -->
<!-- design: settings-screens -->

## Requirements

### Languages

The system must show every text in the language the person chose.

- Given a person with a chosen language, when they use the product, then every text, message and email appears in it
- Given a text with no translation, when it is shown, then the default language appears, never an empty place or a key

### Dates, numbers and money

The system must format dates, numbers and amounts the way the person expects.

- Given a moment in time, when it is shown, then it appears in the person's time zone and format
- Given an amount, when it is shown, then it carries its currency and the separators of the person's region

## Edge cases

- [Languages] Languages that read right to left, and text much longer than in the original, must not break the layout
- [Dates, numbers and money] A date picked by a person in one time zone and read by another one means the same moment

## Open questions

- [Languages] Which languages are supported at launch, and which one is the default?
- [Dates, numbers and money] Is time zone chosen by the person or taken from the device?
