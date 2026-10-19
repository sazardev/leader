<!-- name: Internal tool -->
<!-- desc: A back-office app for your own staff: records, permissions, bulk edits, imports, reports, audit log -->
<!-- modules: accounts roles sessions-2fa lists bulk-actions import-export audit-log reports admin settings -->
<!-- tech: database auth jobs email unit-testing -->
<!-- design: data-tables search-and-filters forms navigation-shell dialogs dashboards-charts -->
<!-- stacks: react-vite nextjs django-htmx laravel rails8 go-htmx -->

**Who it is for.** Teams that run part of the business from an admin screen: operations, support, finance or logistics. The users are employees, they know the work, and they care about speed and correctness over polish.

**What it adds.** Accounts, sessions and roles decide who is inside and what each person may touch. Lists, bulk actions and import/export let staff work through many records at once. The audit log records who changed what, reports show how the work is going, and admin and settings keep the tool configurable without a developer.

**Decide first.**
- Which records does the tool own, and which system is the source of truth for them?
- Who signs in (company directory or its own accounts), and which roles exist?
- Which actions are risky and need a confirmation or an approval?
- How much history must the audit log keep, and who may read it?
- Which spreadsheets or exports do people use today that this must replace?
