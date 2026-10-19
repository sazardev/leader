<!-- name: SaaS for teams -->
<!-- desc: A subscription product that companies use together: workspaces, roles, seats, SSO and an audit trail -->
<!-- modules: accounts sessions-2fa workspaces roles seats-billing subscriptions sso audit-log settings notifications api -->
<!-- tech: database auth payments email jobs analytics -->
<!-- design: navigation-shell settings-screens data-tables auth-screens pricing-checkout onboarding -->
<!-- stacks: nextjs t3 nextjs-supabase rails8 laravel -->

**Who it is for.** Teams that sell software to other companies on a recurring plan. Several people from one customer share the same data, and the buyer cares about who can do what.

**What it adds.** Accounts, sessions and two-factor sign-in let people in safely. Workspaces and roles separate each customer's data and decide who can change what. Subscriptions and seat billing turn plans and team size into revenue, and SSO answers larger customers' security reviews. The audit log, settings, notifications and API cover what a team expects once it depends on the product.

**Decide first.**
- Is the customer a company (workspace) or a person who may belong to several companies?
- What do you charge for: seats, usage, features, or a mix? Is there a free plan or a trial?
- Which roles exist from day one, and can a customer define its own?
- Do you promise SSO or an audit log to win deals, and on which plan?
- What happens to a customer's data when the subscription ends?
