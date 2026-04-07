# frozen_string_literal: true
#
# rails-starter — Rails application template
#
# Usage:
#   rails new myapp \
#     --database=postgresql \
#     --skip-solid \
#     --skip-test \
#     --javascript=importmap \
#     --css=tailwind \
#     -m https://raw.githubusercontent.com/.../template.rb
#
# Or from a local checkout:
#   rails new myapp -d postgresql --skip-solid --skip-test -m ./template.rb

RAILS_REQUIREMENT = ">= 8.0"

def assert_minimum_rails_version
  return if Gem::Requirement.new(RAILS_REQUIREMENT).satisfied_by?(Gem.loaded_specs["rails"].version)

  raise "This template requires Rails #{RAILS_REQUIREMENT}. You are using #{Rails.version}."
end

def assert_postgresql
  return if IO.read("config/database.yml") =~ /postgresql/

  raise "This template requires PostgreSQL. Re-run with: rails new myapp -d postgresql"
end

assert_minimum_rails_version
assert_postgresql

# ---------------------------------------------------------------------------
# Interactive prompts — collect real values up front so generated files are
# populated correctly on first run. Pass --skip to accept all defaults.
# ---------------------------------------------------------------------------

def prompt(label, default:, secret: false)
  return default if options[:skip]

  answer = ask("#{label} [#{secret ? '****' : default}]:")
  answer.to_s.strip.empty? ? default : answer.strip
end

def yes_no(label, default: true)
  return default if options[:skip]
  yes?("#{label} (#{default ? 'Y/n' : 'y/N'}):") || (default && !no?("#{label} (Y/n):"))
end

say "\n== rails-starter configuration ==", :green
say "Press enter to accept defaults. Re-run with --skip to take all defaults silently.\n", :yellow

CONFIG = {
  app_host_dev:    prompt("Development host (used for mailer URLs)",    default: "localhost:3000"),
  app_host_prod:   prompt("Production host (e.g. myapp.com)",            default: "example.com"),
  cors_origins:    prompt("Production CORS origins (comma-separated)",   default: "https://example.com"),
  mail_from:       prompt("Default mail From address",                   default: "no-reply@#{app_name.tr('_', '-')}.com"),
  resend_api_key:  prompt("Resend API key (leave blank to fill later)",  default: "re_xxx", secret: true),
  stripe_pk:       prompt("Stripe publishable key (test)",               default: "pk_test_xxx", secret: true),
  stripe_sk:       prompt("Stripe secret key (test)",                    default: "sk_test_xxx", secret: true),
  stripe_whsec:    prompt("Stripe webhook signing secret",               default: "whsec_xxx",   secret: true),
  sentry_dsn:      prompt("Sentry DSN (leave blank to skip)",            default: "",            secret: true),
  admin_email:     prompt("Seed admin email",                            default: "admin@example.com"),
  admin_password:  prompt("Seed admin password (min 6 chars)",           default: "password", secret: true),
  user_email:      prompt("Seed regular user email",                     default: "user@example.com"),
  user_password:   prompt("Seed regular user password",                  default: "password", secret: true)
}.freeze

say "\nConfiguration captured. Generating app...\n", :green

# ---------------------------------------------------------------------------
# Gemfile
# ---------------------------------------------------------------------------

# Strip Solid* adapters that ship with Rails 8 by default.
gsub_file "Gemfile", /^gem ["']solid_queue["'].*\n/, ""
gsub_file "Gemfile", /^gem ["']solid_cache["'].*\n/, ""
gsub_file "Gemfile", /^gem ["']solid_cable["'].*\n/, ""

# Auth & Authorization
gem "devise"
gem "pundit"

# Payments
gem "stripe"

# Background jobs (replaces solid_queue)
gem "sidekiq"
gem "sidekiq-cron"
gem "redis", ">= 5.0"
gem "connection_pool"

# API hardening
gem "rack-cors"
gem "rack-attack"
gem "pagy"

# Fast JSON
gem "oj"
gem "alba"

# dry-rb ecosystem — service objects, value objects, validation
gem "dry-monads"
gem "dry-validation"
gem "dry-struct"
gem "dry-types"

# Email
gem "resend"

# Observability
gem "sentry-ruby"
gem "sentry-rails"
gem "lograge"

gem_group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "dotenv-rails"
end

gem_group :development do
  gem "letter_opener"
  gem "bullet"
end

gem_group :test do
  gem "shoulda-matchers"
  gem "simplecov", require: false
end

# ---------------------------------------------------------------------------
# Environment files
# ---------------------------------------------------------------------------

file ".env.development", <<~ENV
  DATABASE_URL=postgres://localhost:5432/#{app_name}_development
  REDIS_URL=redis://localhost:6379/0
  APP_HOST=#{CONFIG[:app_host_dev]}
  MAIL_FROM=#{CONFIG[:mail_from]}
  RESEND_API_KEY=#{CONFIG[:resend_api_key]}
  STRIPE_PUBLISHABLE_KEY=#{CONFIG[:stripe_pk]}
  STRIPE_SECRET_KEY=#{CONFIG[:stripe_sk]}
  STRIPE_WEBHOOK_SECRET=#{CONFIG[:stripe_whsec]}
  SENTRY_DSN=#{CONFIG[:sentry_dsn]}
ENV

file ".env.test", <<~ENV
  DATABASE_URL=postgres://localhost:5432/#{app_name}_test
  REDIS_URL=redis://localhost:6379/1
  APP_HOST=localhost:3000
  MAIL_FROM=#{CONFIG[:mail_from]}
  STRIPE_SECRET_KEY=sk_test_dummy
ENV

# .env.production.example — committed reference for deployment, real values
# go in your secrets manager.
file ".env.production.example", <<~ENV
  DATABASE_URL=postgres://...
  REDIS_URL=redis://...
  APP_HOST=#{CONFIG[:app_host_prod]}
  CORS_ORIGINS=#{CONFIG[:cors_origins]}
  MAIL_FROM=#{CONFIG[:mail_from]}
  RESEND_API_KEY=
  STRIPE_PUBLISHABLE_KEY=
  STRIPE_SECRET_KEY=
  STRIPE_WEBHOOK_SECRET=
  SENTRY_DSN=
ENV

append_to_file ".gitignore", <<~IGNORE

  # dotenv
  .env
  .env.*.local
  .env.development
  .env.test
IGNORE

# ---------------------------------------------------------------------------
# After bundle install
# ---------------------------------------------------------------------------

after_bundle do
  git :init unless File.directory?(".git")

  # -------------------------------------------------------------------------
  # ActiveJob -> Sidekiq
  # -------------------------------------------------------------------------
  application "config.active_job.queue_adapter = :sidekiq"

  # -------------------------------------------------------------------------
  # Devise
  # -------------------------------------------------------------------------
  generate "devise:install"
  generate "devise", "User"

  # Sane Devise defaults — confirmable, lockable, trackable
  inject_into_file "app/models/user.rb",
    "         :confirmable, :lockable, :trackable,\n",
    after: "devise :database_authenticatable, :registerable,\n"

  # Migration tweaks for confirmable/lockable/trackable
  migration = Dir["db/migrate/*_devise_create_users.rb"].first
  if migration
    inject_into_file migration, after: "## Trackable\n" do
      <<~RUBY
        t.integer  :sign_in_count, default: 0, null: false
        t.datetime :current_sign_in_at
        t.datetime :last_sign_in_at
        t.string   :current_sign_in_ip
        t.string   :last_sign_in_ip

      RUBY
    end
    gsub_file migration, "# t.string   :confirmation_token", "t.string   :confirmation_token"
    gsub_file migration, "# t.datetime :confirmed_at",       "t.datetime :confirmed_at"
    gsub_file migration, "# t.datetime :confirmation_sent_at", "t.datetime :confirmation_sent_at"
    gsub_file migration, "# t.string   :unconfirmed_email",  "t.string   :unconfirmed_email"
    gsub_file migration, "# t.integer  :failed_attempts, default: 0, null: false",
                          "t.integer  :failed_attempts, default: 0, null: false"
    gsub_file migration, "# t.string   :unlock_token",       "t.string   :unlock_token"
    gsub_file migration, "# t.datetime :locked_at",          "t.datetime :locked_at"
    gsub_file migration, "# add_index :users, :confirmation_token",   "add_index :users, :confirmation_token"
    gsub_file migration, "# add_index :users, :unlock_token",         "add_index :users, :unlock_token"
  end

  # -------------------------------------------------------------------------
  # User: add admin + name columns and User#admin? helper
  # -------------------------------------------------------------------------
  generate "migration", "AddProfileFieldsToUsers", "name:string", "admin:boolean"
  profile_migration = Dir["db/migrate/*_add_profile_fields_to_users.rb"].first
  if profile_migration
    gsub_file profile_migration,
              "add_column :users, :admin, :boolean",
              "add_column :users, :admin, :boolean, default: false, null: false"
  end

  # -------------------------------------------------------------------------
  # Pundit
  # -------------------------------------------------------------------------
  generate "pundit:install"
  inject_into_class "app/controllers/application_controller.rb", "ApplicationController",
    "  include Pundit::Authorization\n"

  # -------------------------------------------------------------------------
  # RSpec
  # -------------------------------------------------------------------------
  generate "rspec:install"

  # -------------------------------------------------------------------------
  # Initializers
  # -------------------------------------------------------------------------
  create_file "config/initializers/sidekiq.rb", <<~RUBY
    Sidekiq.configure_server do |config|
      config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
      config.concurrency = Integer(ENV.fetch("SIDEKIQ_CONCURRENCY", 5))

      config.on(:startup) do
        schedule_file = Rails.root.join("config", "schedule.yml")
        if File.exist?(schedule_file)
          Sidekiq::Cron::Job.load_from_hash(YAML.load_file(schedule_file))
        end
      end
    end

    Sidekiq.configure_client do |config|
      config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
    end
  RUBY

  create_file "config/initializers/redis.rb", <<~RUBY
    # Shared, thread-safe Redis pool. Use REDIS_POOL.with { |r| r.get(...) }.
    REDIS_POOL = ConnectionPool.new(size: ENV.fetch("REDIS_POOL_SIZE", 10).to_i, timeout: 3) do
      Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    end
  RUBY

  create_file "config/initializers/stripe.rb", <<~RUBY
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
    Rails.configuration.stripe = {
      publishable_key: ENV["STRIPE_PUBLISHABLE_KEY"],
      secret_key:      ENV["STRIPE_SECRET_KEY"],
      webhook_secret:  ENV["STRIPE_WEBHOOK_SECRET"]
    }
  RUBY

  create_file "config/initializers/dry_types.rb", <<~RUBY
    require "dry-types"
    require "dry-struct"
    require "dry-monads"
    require "dry-validation"

    module Types
      include Dry.Types()
    end
  RUBY

  create_file "config/initializers/oj.rb", "Oj.optimize_rails\n"

  create_file "config/initializers/cors.rb", <<~RUBY
    Rails.application.config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins ENV.fetch("CORS_ORIGINS", "*").split(",").map(&:strip)

        resource "/api/*",
          headers: :any,
          methods: %i[get post put patch delete options head],
          max_age: 600
      end
    end
  RUBY

  create_file "config/initializers/rack_attack.rb", <<~RUBY
    class Rack::Attack
      throttle("req/ip", limit: 300, period: 5.minutes) { |req| req.ip }

      throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
        req.ip if req.path == "/users/sign_in" && req.post?
      end

      throttle("logins/email", limit: 5, period: 20.seconds) do |req|
        if req.path == "/users/sign_in" && req.post?
          req.params.dig("user", "email")&.downcase&.strip
        end
      end

      throttle("signups/ip", limit: 5, period: 1.hour) do |req|
        req.ip if req.path == "/users" && req.post?
      end

      throttle("password_resets/ip", limit: 5, period: 1.hour) do |req|
        req.ip if req.path == "/users/password" && req.post?
      end
    end

    ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_, _, _, _, payload|
      Rails.logger.warn "[Rack::Attack] Throttled \#{payload[:request].ip}"
    end
  RUBY

  create_file "config/initializers/sentry.rb", <<~RUBY
    Sentry.init do |config|
      config.dsn = ENV["SENTRY_DSN"]
      config.enabled_environments = %w[production]
      config.breadcrumbs_logger = [:active_support_logger, :http_logger]
      config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0.1").to_f
      config.send_default_pii = false
    end
  RUBY

  create_file "config/initializers/lograge.rb", <<~RUBY
    Rails.application.configure do
      config.lograge.enabled = true
      config.lograge.formatter = Lograge::Formatters::KeyValue.new
    end
  RUBY

  # -------------------------------------------------------------------------
  # Mail: Resend in production, letter_opener in development
  # -------------------------------------------------------------------------
  create_file "config/initializers/resend.rb", <<~RUBY
    require "resend"

    Resend.api_key = ENV["RESEND_API_KEY"]

    # Register Resend as an ActionMailer delivery method.
    require "resend/mailer"
    ActionMailer::Base.add_delivery_method :resend, Resend::Mailer
  RUBY

  # Default from address for all mailers
  inject_into_class "app/mailers/application_mailer.rb", "ApplicationMailer",
    "  default from: ENV.fetch(\"MAIL_FROM\", \"no-reply@example.com\")\n"

  # Development: letter_opener (opens emails in your browser)
  application <<~RUBY, env: "development"
    config.action_mailer.delivery_method = :letter_opener
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  RUBY

  # Test: stay on the standard :test delivery method (no extra config needed)

  # Production: Resend
  application <<~RUBY, env: "production"
    config.action_mailer.delivery_method = :resend
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST") }
  RUBY

  # -------------------------------------------------------------------------
  # Sidekiq cron schedule (empty by default)
  # -------------------------------------------------------------------------
  create_file "config/schedule.yml", <<~YAML
    # sidekiq-cron schedule. Add jobs as:
    # my_job:
    #   cron: "*/5 * * * *"
    #   class: "MyJob"
    #   description: "What it does"
  YAML

  # -------------------------------------------------------------------------
  # Sidekiq web UI (auth-protected)
  # -------------------------------------------------------------------------
  route <<~ROUTES
    require "sidekiq/web"
    require "sidekiq/cron/web"
    authenticate :user, ->(u) { u.respond_to?(:admin?) && u.admin? } do
      mount Sidekiq::Web => "/sidekiq"
    end
  ROUTES

  # -------------------------------------------------------------------------
  # ApplicationService base + ParseResult-style example struct
  # -------------------------------------------------------------------------
  create_file "app/services/application_service.rb", <<~RUBY
    # Base class for service objects.
    #
    # Usage:
    #   class CreateOrder < ApplicationService
    #     def initialize(user:, params:)
    #       @user = user
    #       @params = params
    #     end
    #
    #     def call
    #       order = @user.orders.build(@params)
    #       return Failure(order.errors) unless order.save
    #       Success(order)
    #     end
    #   end
    #
    #   case CreateOrder.call(user:, params:)
    #   in Success(order) then ...
    #   in Failure(errors) then ...
    #   end
    class ApplicationService
      include Dry::Monads[:result]

      def self.call(...)
        new(...).call
      end
    end
  RUBY

  # -------------------------------------------------------------------------
  # Procfile.dev — add sidekiq
  # -------------------------------------------------------------------------
  if File.exist?("Procfile.dev")
    append_to_file "Procfile.dev", "worker: bundle exec sidekiq\n"
  else
    create_file "Procfile.dev", <<~PROC
      web: bin/rails server
      worker: bundle exec sidekiq
    PROC
  end

  # -------------------------------------------------------------------------
  # Strip Solid* config files left over from `rails new`
  # -------------------------------------------------------------------------
  remove_file "config/queue.yml"
  remove_file "config/cache.yml"
  remove_file "config/recurring.yml"
  remove_file "db/queue_schema.rb"
  remove_file "db/cache_schema.rb"
  remove_file "db/cable_schema.rb"

  # Switch any solid_queue / solid_cache references in environment configs
  %w[development production].each do |env|
    path = "config/environments/#{env}.rb"
    next unless File.exist?(path)
    gsub_file path, /config\.active_job\.queue_adapter\s*=\s*:solid_queue.*$/,
                    "config.active_job.queue_adapter = :sidekiq"
    gsub_file path, /config\.cache_store\s*=\s*:solid_cache_store.*$/,
                    "config.cache_store = :redis_cache_store, { url: ENV.fetch(\"REDIS_URL\", \"redis://localhost:6379/0\") }"
    gsub_file path, /config\.solid_queue\..*$/, ""
  end

  # -------------------------------------------------------------------------
  # CLAUDE.md — guidance for the agent working in this codebase
  # -------------------------------------------------------------------------
  template "CLAUDE.md.tt", "CLAUDE.md" if File.exist?(File.expand_path("CLAUDE.md.tt", __dir__))
  create_file "CLAUDE.md", claude_md_contents unless File.exist?("CLAUDE.md")

  # -------------------------------------------------------------------------
  # Home / pages controller + root route + health check
  # -------------------------------------------------------------------------
  create_file "app/controllers/pages_controller.rb", <<~RUBY
    class PagesController < ApplicationController
      skip_before_action :authenticate_user!, only: %i[home]

      def home
      end

      def dashboard
        @user = current_user
      end
    end
  RUBY

  create_file "app/views/pages/home.html.erb", <<~ERB
    <h1>Welcome to <%= Rails.application.class.module_parent_name %></h1>
    <% if user_signed_in? %>
      <p>Signed in as <%= current_user.email %>.</p>
      <%= link_to "Dashboard", dashboard_path %> ·
      <%= button_to "Sign out", destroy_user_session_path, method: :delete %>
    <% else %>
      <%= link_to "Sign in", new_user_session_path %> ·
      <%= link_to "Sign up", new_user_registration_path %>
    <% end %>
  ERB

  create_file "app/views/pages/dashboard.html.erb", <<~ERB
    <h1>Dashboard</h1>
    <p>Hello, <%= @user.name.presence || @user.email %>.</p>
    <% if @user.admin? %>
      <p><%= link_to "Sidekiq", "/sidekiq" %></p>
    <% end %>
  ERB

  create_file "app/controllers/health_controller.rb", <<~RUBY
    class HealthController < ApplicationController
      skip_before_action :authenticate_user!, raise: false

      def show
        ActiveRecord::Base.connection.execute("SELECT 1")
        REDIS_POOL.with { |r| r.ping }
        render json: { status: "ok", time: Time.current.iso8601 }
      rescue => e
        render json: { status: "error", error: e.message }, status: 503
      end
    end
  RUBY

  # Require login by default; individual actions opt out via skip_before_action
  inject_into_class "app/controllers/application_controller.rb", "ApplicationController",
    "  before_action :authenticate_user!\n"

  route 'root to: "pages#home"'
  route 'get "dashboard", to: "pages#dashboard"'
  route 'get "up", to: "health#show"'

  # -------------------------------------------------------------------------
  # Seed users + sample data
  # -------------------------------------------------------------------------
  create_file "db/seeds.rb", <<~RUBY, force: true
    # Idempotent seeds. Safe to run multiple times.
    # Credentials below were captured during `rails new` from template prompts.

    require "faker"

    def upsert_user!(email:, password:, name:, admin: false)
      user = User.find_or_initialize_by(email: email)
      user.password = password
      user.password_confirmation = password
      user.name = name
      user.admin = admin
      user.confirmed_at ||= Time.current if user.respond_to?(:confirmed_at)
      user.save!
      puts "  seeded \#{user.admin? ? 'admin' : 'user '} \#{user.email}"
      user
    end

    puts "Seeding users..."
    upsert_user!(email: #{CONFIG[:admin_email].inspect}, password: #{CONFIG[:admin_password].inspect}, name: "Admin User", admin: true)
    upsert_user!(email: #{CONFIG[:user_email].inspect},  password: #{CONFIG[:user_password].inspect}, name: "Regular User")

    if Rails.env.development?
      5.times do
        upsert_user!(
          email: Faker::Internet.unique.email,
          password: "password",
          name: Faker::Name.name
        )
      end
    end

    puts "Done. Total users: \#{User.count}"
  RUBY

  # -------------------------------------------------------------------------
  # Factories
  # -------------------------------------------------------------------------
  create_file "spec/factories/users.rb", <<~RUBY
    FactoryBot.define do
      factory :user do
        sequence(:email) { |n| "user\#{n}@example.com" }
        password { "password" }
        password_confirmation { "password" }
        name { Faker::Name.name }
        admin { false }
        confirmed_at { Time.current }

        trait :admin do
          admin { true }
        end

        trait :unconfirmed do
          confirmed_at { nil }
        end
      end
    end
  RUBY

  # -------------------------------------------------------------------------
  # bin/setup — one-shot bootstrap for new contributors
  # -------------------------------------------------------------------------
  create_file "bin/dev-setup", <<~BASH, force: true
    #!/usr/bin/env bash
    set -euo pipefail
    bundle install
    bin/rails db:prepare
    bin/rails db:seed
    echo
    echo "Setup complete. Seeded users:"
    echo "  #{CONFIG[:admin_email]} / #{CONFIG[:admin_password]}  (admin)"
    echo "  #{CONFIG[:user_email]} / #{CONFIG[:user_password]}  (regular)"
  BASH
  chmod "bin/dev-setup", 0755

  # -------------------------------------------------------------------------
  # DB setup + initial commit
  # -------------------------------------------------------------------------
  rails_command "db:create"
  rails_command "db:migrate"
  rails_command "db:seed"

  git add: "."
  git commit: %Q{ -m "Initial commit from rails-starter template" }

  say "\n========================================================", :green
  say " #{app_name} is ready.", :green
  say "========================================================", :green
  say " Seeded admin: #{CONFIG[:admin_email]} / #{CONFIG[:admin_password]}"
  say " Seeded user:  #{CONFIG[:user_email]} / #{CONFIG[:user_password]}"
  say ""
  say " Next steps:"
  say "   cd #{app_name}"
  say "   bin/dev                     # web + tailwind + sidekiq"
  say "   open http://#{CONFIG[:app_host_dev]}"
  say ""
  say " Edit .env.development to fill in any keys you skipped."
  say " Production env vars: see .env.production.example"
  say "========================================================\n", :green
end

def claude_md_contents
  <<~MD
    # CLAUDE.md

    Guidance for Claude / AI agents working in this Rails codebase. Read this
    before writing code.

    ## Stack

    - Ruby on Rails 8+, PostgreSQL, Redis
    - **Sidekiq** for background jobs (NOT Solid Queue — it has been removed)
    - **Devise** for authentication (confirmable, lockable, trackable enabled)
    - **Pundit** for authorization
    - **Stripe** for payments
    - **dry-rb** (dry-monads, dry-validation, dry-struct, dry-types) for service
      objects, contracts, and value objects
    - **RSpec** + FactoryBot + Faker for tests
    - **Lograge** + **Sentry** for observability
    - **Rack::Attack** + **Rack::Cors** for API hardening
    - **Email**: Resend in production, letter_opener in development, `:test` in test
      - Default `from:` set in `ApplicationMailer` via `MAIL_FROM` env var
      - Mailers extend `ApplicationMailer` and use Rails' standard ActionMailer API.
        Do not call `Resend.send_email` directly — go through ActionMailer so
        previews, tests, and the `:test` delivery method work uniformly.

    ## Architectural rules

    ### 1. Service objects, not fat models or fat controllers

    Any non-trivial business operation lives in `app/services/` as a subclass of
    `ApplicationService`. A service:

    - Has a single public entrypoint: `call` (invoke via `MyService.call(...)`)
    - Returns a `Dry::Monads::Result` — `Success(value)` or `Failure(reason)`
    - Never raises for expected failure modes; reserve exceptions for bugs
    - Is named for what it does: `CreateSubscription`, `ImportCsv`, `ChargeCustomer`

    ```ruby
    class ChargeCustomer < ApplicationService
      def initialize(user:, amount_cents:)
        @user = user
        @amount_cents = amount_cents
      end

      def call
        return Failure(:no_payment_method) unless @user.stripe_customer_id

        charge = Stripe::Charge.create(
          customer: @user.stripe_customer_id,
          amount:   @amount_cents,
          currency: "usd"
        )
        Success(charge)
      rescue Stripe::StripeError => e
        Failure(stripe_error: e.message)
      end
    end
    ```

    Callers pattern-match the result:

    ```ruby
    case ChargeCustomer.call(user:, amount_cents: 1500)
    in Success(charge) then redirect_to charge_path(charge.id)
    in Failure(:no_payment_method) then redirect_to billing_path
    in Failure(stripe_error:) then flash[:error] = stripe_error
    end
    ```

    ### 2. Validate input at the boundary with dry-validation

    Controller params and external payloads (Stripe webhooks, API requests) get
    validated by a `Dry::Validation::Contract` BEFORE they reach a service. Do not
    rely on Rails strong params alone for non-trivial shapes.

    ```ruby
    class CreateOrderContract < Dry::Validation::Contract
      params do
        required(:user_id).filled(:integer)
        required(:items).array(:hash) do
          required(:sku).filled(:string)
          required(:qty).filled(:integer, gt?: 0)
        end
      end
    end
    ```

    ### 3. Value objects are dry-struct, not Hash or OpenStruct

    Anything passed between layers (parser results, API responses, computed
    summaries) is a `Dry::Struct` with explicit, typed attributes. No untyped
    hashes flowing through service boundaries.

    ### 4. Models stay thin

    Models hold associations, scopes, validations, and trivial query helpers.
    They DO NOT hold multi-step business logic, third-party API calls, or
    side-effecting orchestration. Push that into a service.

    ### 5. Background jobs are thin wrappers

    A Sidekiq job's only responsibility is to deserialize arguments and call a
    service. Business logic belongs in the service so it stays testable
    synchronously.

    ```ruby
    class ImportCsvJob < ApplicationJob
      queue_as :default

      def perform(import_id)
        ImportCsv.call(import_id: import_id)
      end
    end
    ```

    ### 6. Authorization is Pundit, always

    Every controller action that touches a record runs through `authorize` or
    `policy_scope`. No ad-hoc `if current_user.admin?` checks scattered in
    controllers.

    ### 7. Idempotency for webhooks and external side-effects

    Stripe webhooks and other external callbacks must be idempotent. Track
    processed event IDs (e.g. a `processed_webhook_events` table) and short-circuit
    duplicates.

    ## Testing rules

    - RSpec, not Minitest
    - One spec file per service; cover Success and Failure branches explicitly
    - Use FactoryBot factories, not fixtures
    - Stub external HTTP (Stripe, etc.) — never hit the network in tests
    - Integration specs go in `spec/requests/`, not `spec/features/`

    ## Things NOT to do

    - Do not reintroduce Solid Queue / Solid Cache / Solid Cable — Sidekiq + Redis
      is the chosen stack
    - Do not add `rescue => e` blocks that swallow errors. If you can't handle it,
      let it raise to Sentry
    - Do not put business logic in controllers, models, or jobs
    - Do not return raw hashes from services — return monadic Results wrapping
      typed values
    - Do not use `OpenStruct` — use `Dry::Struct`
    - Do not skip validation contracts for "simple" endpoints; they grow
    - Do not bypass Pundit authorization with `skip_authorization` unless the
      action is genuinely public, and document why

    ## Conventions

    - Service files: `app/services/<verb>_<noun>.rb` defining `class VerbNoun`
    - Contract files: `app/contracts/<name>_contract.rb`
    - Value objects: `app/values/<name>.rb` (or colocated next to their service)
    - Job files: `app/jobs/<name>_job.rb`, one job per file, thin wrapper only

    ## Running things

    ```bash
    bin/dev-setup        # one-shot: bundle, db:prepare, db:seed
    bin/dev              # web + css + worker (Procfile.dev)
    bundle exec sidekiq  # background worker (standalone)
    bin/rails db:migrate
    bin/rails db:seed    # idempotent
    bundle exec rspec
    ```

    ## Seeded users (development)

    - `admin@example.com` / `password` — admin (can access `/sidekiq`)
    - `user@example.com`  / `password` — regular user
    - Plus 5 random Faker users in development

    Seeds are idempotent — re-running `db:seed` is safe.

    ## Routes provided out of the box

    - `/`            — public home page
    - `/dashboard`   — authenticated landing page
    - `/up`          — health check (DB + Redis ping), returns JSON
    - `/sidekiq`     — Sidekiq web UI, gated on `current_user.admin?`
    - Devise routes (`/users/sign_in`, `/users/sign_up`, etc.)
  MD
end
