<!-- name: Consumer mobile app -->
<!-- desc: An app people keep on their phone: quick onboarding, works offline, push notifications and in-app choices -->
<!-- modules: accounts onboarding offline-sync notifications settings privacy localization favorites states sessions-2fa -->
<!-- tech: database auth email i18n analytics e2e-testing -->
<!-- design: onboarding navigation-shell settings-screens notification-center empty-states auth-screens -->
<!-- stacks: react-native-expo flutter-riverpod flutter-supabase flutter-offline-first swiftui kotlin-compose -->

**Who it is for.** Apps installed by the general public on a phone. People decide in the first minute whether to keep it, connectivity comes and goes, and the app stores set rules about privacy and permissions.

**What it adds.** Accounts and onboarding get a person in quickly, and sessions keep them signed in. Offline sync keeps the app useful on a bad connection, and notifications bring people back. Favorites keep what matters one tap away, settings and localization adapt the app to the person, and privacy covers consent, data export and account deletion that the stores require.

**Decide first.**
- Does the app need an account from the first launch, or can people try it without one?
- Which features must work offline, and what wins when two devices edit the same thing?
- Which permissions do you ask for (notifications, location, camera), and when?
- Which platforms and languages do you launch with?
- How will you handle account deletion and data export for the app stores?
