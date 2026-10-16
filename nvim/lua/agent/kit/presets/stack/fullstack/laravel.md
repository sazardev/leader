<!-- name: Laravel -->
<!-- desc: Laravel 11 + Livewire or Inertia, actions per use case, Pest, Pint, Larastan at max level -->

# STACK.md: Laravel

## Summary

A full-stack PHP application on Laravel 11. The UI is either Livewire 3 (server-driven components, Blade) or Inertia
with Vue/React (choose one per project, never both). Business logic lives in single-purpose Action classes, one per use
case; controllers, Livewire components and jobs only translate input and call actions. Static analysis runs at
Larastan's maximum level, so the code is as typed as PHP allows.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | PHP 8.3+ (`declare(strict_types=1)`) | Enums, readonly properties, typed everything |
| Framework | Laravel 11 | Routing, Eloquent, queues, validation, auth |
| UI | Livewire 3 + Alpine.js (or Inertia 2 + Vue 3/React) | One approach per project |
| Database | PostgreSQL or MySQL 8 | |
| Auth | Laravel Breeze/Jetstream starter, Sanctum for API tokens | |
| Validation | Form Requests (Livewire: `#[Validate]` / form objects) | |
| DTOs | `spatie/laravel-data` (optional) or readonly classes | Typed input to actions |
| Queues | Laravel queues (Redis) + Horizon | |
| Styling | Tailwind CSS via Vite | |
| Tests | Pest 3 (+ `pestphp/pest-plugin-laravel`) | |
| Format | Laravel Pint | |
| Static analysis | Larastan (PHPStan) level `max` | |
| Refactoring | Rector (optional) | Automated upgrades |
| Package manager | Composer + npm/pnpm for assets | |

## Project layout

```
app/
  Actions/Orders/PlaceOrder.php        one public handle()/execute() per class
  Actions/Orders/CancelOrder.php
  Data/Orders/PlaceOrderData.php       typed input
  Domain/Orders/OrderStatus.php        enums, value objects, domain exceptions
  Models/Order.php                     Eloquent: casts, relations, scopes; no workflows
  Http/Controllers/OrderController.php thin: FormRequest → Action → response
  Http/Requests/PlaceOrderRequest.php
  Livewire/Orders/OrderTable.php       (Livewire) component: state + calls actions
  Livewire/Orders/OrderForm.php
  Policies/OrderPolicy.php             authorization
  Contracts/PaymentGateway.php         interfaces for external services
  Services/Payments/StripeGateway.php  implementations
  Providers/AppServiceProvider.php     binds contracts to implementations
resources/views/livewire/orders/       Blade views for components
routes/web.php
database/migrations/
database/factories/
tests/
  Feature/Orders/PlaceOrderTest.php
  Unit/Actions/PlaceOrderTest.php
```

Dependency direction: `Controllers/Livewire/Jobs → Actions → Models, Domain, Contracts`; implementations of contracts
are bound in a service provider and injected; actions never resolve infrastructure with `new` or facades for external services.

## Conventions

- One class = one responsibility: one Action per use case, one FormRequest per endpoint, one Policy per model.
- Actions are injected (constructor DI) and take typed input (DTO or explicit parameters); they wrap multi-row writes in `DB::transaction`.
- Controllers: `authorize` (policy) → validated input → action → response/redirect. No Eloquent queries beyond simple loads.
- Eloquent: `$fillable` (or `$guarded = []` never), casts for enums/dates, `preventLazyLoading()` in non-production.
- Domain states are PHP enums; status changes happen only in actions.
- Strict types in every file; return types and property types everywhere.
- New feature = migration + model + enum → action (+ DTO) → policy → FormRequest → controller/Livewire component → view → tests.

## Commands

| Task | Command |
| --- | --- |
| Install | `composer install && npm install` |
| Dev | `composer run dev` (server, queue, logs, Vite) |
| Migrate | `php artisan migrate` |
| Fresh DB with seeds | `php artisan migrate:fresh --seed` |
| Tests | `php artisan test` (or `./vendor/bin/pest`) |
| Parallel tests | `./vendor/bin/pest --parallel` |
| Format | `./vendor/bin/pint` |
| Static analysis | `./vendor/bin/phpstan analyse` |
| Assets build | `npm run build` |
| Make an action | create `app/Actions/<Feature>/<Verb><Noun>.php` by hand (no generator) |

## Testing

- Actions: Pest tests with `RefreshDatabase` and factories; fake external contracts with in-memory implementations bound in the test.
- HTTP/Livewire: feature tests (`$this->post(...)`, `Livewire::test(...)`) asserting authorization, validation errors and effects.
- Policies: unit tests for each ability.
- Queue/mail/events: `Queue::fake()`, `Mail::fake()`, `Event::fake()` and assertions.
- A bug fix starts with a failing test.

## Quality gates

- Pint clean (`pint --test` in CI); PHPStan/Larastan level `max` with zero errors (baseline only for legacy code, shrinking).
- Pest green, with `--parallel` in CI; no lazy loading violations.
- `composer audit` clean.

## Dependencies

- Laravel first-party packages first.
- Allowed: the table above and well-maintained Spatie/Laravel packages with a reason in the PR.
- Do NOT use: Livewire and Inertia in the same project, repositories that only wrap Eloquent one-to-one, facades for external services inside actions (inject contracts), `DB::raw` with user input, jQuery.

## Rules for agents

- Put business logic in Actions; never in controllers, Livewire components, models' events or Blade.
- Every endpoint validates with a FormRequest (or Livewire validation) and authorizes with a Policy.
- Never use `$guarded = []`; declare `$fillable`.
- Every schema change is a new migration; never edit an applied one.
- Eager-load relations for lists (`with(...)`); lazy loading is an error in development.
- Add `declare(strict_types=1)` and full type declarations to every new PHP file.
- External services are interfaces in `app/Contracts`, bound in a provider and faked in tests.
- Run Pint and PHPStan before finishing; do not add PHPStan ignores to make code pass.
