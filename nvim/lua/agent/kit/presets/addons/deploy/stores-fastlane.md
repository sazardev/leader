<!-- name: App stores with fastlane -->
<!-- desc: signed builds per flavor, TestFlight / Play internal testing, store metadata as code -->
<!-- for: mobile flutter swift -->
<!-- default: mobile flutter swift -->

## Stack

| Release | fastlane (`ios/fastlane`, `android/fastlane`): build, sign, upload to TestFlight and Play internal testing | Repeatable releases from CI, no manual Xcode/Console steps |

## Project layout

```
ios/fastlane/Fastfile          lanes: beta (TestFlight), release
android/fastlane/Fastfile      lanes: internal, production
fastlane/metadata/             store texts and screenshots as files
```

## Conventions

- iOS signing with `match` (certificates in a private repo or storage); Android upload key in CI secrets, never in the repository.
- Build number = CI run number; version name comes from the project file and is bumped in the release commit.
- Flavors (dev, staging, prod) have their own bundle id / application id and config.

## Commands

| Release beta (iOS) | `cd ios && fastlane beta` |
| Release internal (Android) | `cd android && fastlane internal` |

## Rules for agents

- Never commit keystores, `.p12`, provisioning profiles or API keys.
- Never change bundle ids or signing settings without asking.
