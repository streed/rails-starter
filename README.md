# rails-starter

A Rails application template for spinning up new projects with a sane,
opinionated stack: PostgreSQL + Redis + Sidekiq + Devise + Pundit + Stripe +
the dry-rb ecosystem, with a `CLAUDE.md` that teaches AI agents how to write
maintainable code in the resulting app.

## Stack

- **Rails 8+**, Ruby (latest)
- **PostgreSQL** for the database
- **Redis** + **Sidekiq** + **sidekiq-cron** for background jobs (Solid Queue removed)
- **Devise** with `confirmable`, `lockable`, `trackable` enabled
- **Pundit** for authorization
- **Stripe** for payments (initializer + env vars wired)
- **dry-rb**: `dry-monads`, `dry-validation`, `dry-struct`, `dry-types`
- **RSpec** + FactoryBot + Faker
- **Lograge** + **Sentry** for observability
- **Rack::Attack** + **Rack::Cors** for API hardening
- **Oj** + **Alba** for fast JSON
- **Pagy** for pagination
- **Email**: Resend in production, letter_opener in development

## Usage

Hosted at **https://github.com/streed/rails-starter**. Use the raw URL — no clone needed:

```bash
rails new myapp \
  --database=postgresql \
  --skip-solid \
  --skip-test \
  --css=tailwind \
  -m https://raw.githubusercontent.com/streed/rails-starter/main/template.rb
```

To take all defaults silently, append `-- --skip`:

```bash
rails new myapp -d postgresql --skip-solid --skip-test \
  -m https://raw.githubusercontent.com/streed/rails-starter/main/template.rb \
  -- --skip
```

Or from a local clone (when iterating on the template itself):

```bash
git clone git@github.com:streed/rails-starter.git
rails new myapp -d postgresql --skip-solid --skip-test -m ./rails-starter/template.rb
```

Handy shell alias:

```bash
alias new-rails='rails new --database=postgresql --skip-solid --skip-test --css=tailwind -m https://raw.githubusercontent.com/streed/rails-starter/main/template.rb'
# then: new-rails myapp
```

Notes:

- `--database=postgresql` is **required** — the template asserts it
- `--skip-solid` skips Solid Queue/Cache/Cable (we use Sidekiq + Redis)
- `--skip-test` opts out of Minitest in favor of RSpec
- On first run the template **prompts** for the values it needs (hosts, mail
  From, Stripe keys, Resend key, Sentry DSN, seed admin/user credentials) and
  bakes them into `.env.development`, `.env.production.example`, and `db/seeds.rb`.
  Press enter at any prompt to take the default. Pass `--skip` to take all
  defaults silently.
- The template installs gems, generates Devise/Pundit/RSpec, configures
  Sidekiq, writes initializers, creates `CLAUDE.md`, runs migrations + seeds,
  and makes an initial git commit

## What you get

- `app/services/application_service.rb` — base class returning `Dry::Monads::Result`
- `config/initializers/{sidekiq,redis,stripe,dry_types,cors,rack_attack,sentry,lograge,oj}.rb`
- `config/schedule.yml` — sidekiq-cron schedule (empty, ready to fill)
- Devise `User` with `confirmable`/`lockable`/`trackable`, plus `name` and `admin` columns
- Sidekiq web UI mounted at `/sidekiq`, gated on `current_user.admin?`
- `PagesController` with public `/` home and authenticated `/dashboard`
- `HealthController` at `/up` that pings DB and Redis (returns 503 on failure)
- `db/seeds.rb` — idempotent, creates `admin@example.com` and `user@example.com`
  (password: `password`) plus 5 Faker users in development
- `spec/factories/users.rb` with `:admin` and `:unconfirmed` traits
- `bin/dev-setup` — one-shot bundle/migrate/seed for new contributors
- `.env.development` and `.env.test` with sensible defaults
- A `CLAUDE.md` documenting the architectural rules so AI agents stay in lane

## Seeded users

| Email                 | Password   | Role    |
|-----------------------|------------|---------|
| `admin@example.com`   | `password` | admin   |
| `user@example.com`    | `password` | regular |
| 5 × Faker users       | `password` | regular (development only) |

## Customizing

Edit `template.rb` directly. The `CLAUDE.md` body lives in `claude_md_contents`
at the bottom of the file — tweak the rules to match your team's preferences
before generating new projects.
