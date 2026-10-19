<!-- name: Feature flags and settings -->
<!-- desc: turning features on and off per person, team or percentage, without releasing again -->
<!-- for: all -->
<!-- tech: analytics -->
<!-- design: settings-screens -->

## Requirements

### Flags

The system must let the team turn features on and off without a new release.

- Given a flag, when the team changes it, then the product follows it within a short, known time
- Given a flag for a group, when a person of that group uses the product, then they get the feature and nobody else does

### Gradual release

The system must let a feature reach people in steps.

- Given a percentage, when it grows, then people who already have the feature keep it
- Given a problem, when the flag is turned off, then the feature disappears for everyone without losing their data

## Edge cases

- [Flags] A flag that cannot be read falls back to a safe value decided for each flag
- [Gradual release] A person using two devices sees the same version of the feature on both

## Open questions

- [Flags] Who can change flags, and are changes recorded?
- [Gradual release] Which groups are used (person, team, plan, country)?
