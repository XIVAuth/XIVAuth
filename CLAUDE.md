# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

XIVAuth is a single sign-on (SSO) identity service for the Final Fantasy XIV community. Users register and verify their FFXIV characters once, then authenticate with external services via OAuth2 flows. It is purely an identity/authentication provider, not a Lodestone scraping service.

**Key Principle:** "Light touch" approach - prefer Rails conventions and simple solutions over custom abstractions. Security, reliability, maintainability, auditability, and user privacy are paramount.

## Development Commands

### Setup (Docker - Recommended)
```bash
docker compose up                    # Start all services
docker compose run app /bin/sh      # Shell access
rake db:setup                        # Initialize and seed database
```

### Setup (Local)
```bash
bin/dev                             # Runs Procfile.dev (Rails + JS/CSS watchers)
```

### Build Commands
```bash
yarn build                          # Build JavaScript (esbuild)
yarn build:css                      # Build CSS (Sass)
SECRET_KEY_BASE_DUMMY=1 rake assets:precompile  # Production assets
```

### Testing
```bash
bundle exec rspec                   # All tests
bundle exec rspec spec/models       # Specific directory
bundle exec rspec --format documentation
```

### Database
```bash
rake db:migrate                     # Run migrations
rake db:schema:load                 # Load schema
```

### Credentials
Default dev account: `dev@eorzea.id` / `password`

Encrypted credentials template: `config/credentials/sample.yml` (optional for local dev)

## Architecture

### Core Technologies
- **Ruby 3.4.7** / **Rails 8.1**
- **PostgreSQL 16** with UUID primary keys
- **Redis 7** for caching/queues
- **Sidekiq 8** for background jobs
- **Stimulus** + **Hotwire/Turbo** for frontend interactivity
- **Bootstrap 5** with Hope UI theme
- **TypeScript** for JS build (esbuild)

### Authentication Stack
- **Devise** - User authentication
- **Devise Two-Factor** - TOTP support
- **WebAuthn** - Passkey/hardware key support
- **Omniauth** - Social login (GitHub, Steam, Twitch, Discord, Patreon)
- **CanCanCan** - Authorization

### OAuth2 Provider (Doorkeeper)
XIVAuth provides OAuth2 with custom extensions:
- Standard flows: authorization code, client credentials, refresh token
- **Device authorization flow** (custom fork for TV/CLI apps)
- **Polymorphic resource owners** - Users OR CharacterRegistrations can be token owners
- **Character-based authentication** - External apps can request access to specific verified characters
- **Scopes** control access to identity, email, character data
- **JWT signing** with RSA keys (JWKS endpoint: `/api/v1/jwt/jwks`)

**Important:** Doorkeeper behaviors are heavily customized - see `lib/doorkeeper/` for extensions.

### Domain Model Relationships

```
User
├── has_many :character_registrations (links to FFXIV::Character)
├── has_many :social_identities (OAuth logins)
├── has_many :webauthn_credentials (passkeys)
├── has_one :totp_credential (2FA)
├── has_many :team_memberships
└── has_many :oauth_authorizations (granted tokens)

CharacterRegistration (User ↔ FFXIV::Character link)
├── verification_key (unique code for Lodestone bio verification)
├── verified_at (timestamp when verified)
├── entangled_id() (privacy-preserving unique ID per character)
└── Broadcasts Turbo Stream updates on CRUD

FFXIV::Character
├── Lodestone ID (unique identifier)
├── refresh_from_lodestone() (scrapes latest data)
└── has_many :character_registrations

ClientApplication (OAuth apps)
├── Owner (polymorphic: User or Team)
├── has_many :oauth_clients (Doorkeeper applications)
├── has_many :acls (access control lists)
├── private flag (restricts to specific users/teams)
└── usable_by?(user) (complex ACL evaluation)

Team (hierarchical organizations)
├── has_many :direct_memberships
├── Roles: admin, developer, member, invited, blocked
├── inherit_parent_memberships flag
└── Complex nested membership resolution
```

### Character Verification Flow
1. User creates `CharacterRegistration` for their FFXIV character
2. System generates unique `verification_key`
3. User adds key to their Lodestone character bio
4. Background job `FFXIV::VerifyCharacterRegistrationJob` scrapes Lodestone to verify
5. On success, `verified_at` is set
6. Verified characters can be used for OAuth authentication

### Background Jobs (Sidekiq)

**Queues:**
- `default` - General tasks
- `cronjobs` - Scheduled tasks (sidekiq-cron)
- `ffxiv_lodestone_jobs` - Lodestone scraping (throttled)

**Key Scheduled Jobs:**
- `cleanup_unverified_characters` - Daily 2 AM PT
- `cleanup_stale_oauth` - Every 6 hours
- `cleanup_stale_users` - Daily 2 AM PT
- `sync_webauthn_aaguids` - Weekly Thursday 1 AM PT

**Important Jobs:**
- `FFXIV::RefreshCharactersJob` - Updates character data from Lodestone
- `FFXIV::VerifyCharacterRegistrationJob` - Checks Lodestone bio for verification code
- Cleanup jobs for stale records (CharacterRegistrations, OAuth tokens, unconfirmed Users)

### API Structure

**REST API (`/api/v1/`)**
- `GET /api/v1/user` - Current user info
- `POST /api/v1/user/jwt` - Generate JWT for authenticated user
- `GET /api/v1/characters` - List user's characters
- `GET /api/v1/characters/:lodestone_id` - Character details
- `POST /api/v1/characters/:lodestone_id/verify` - Start verification
- `DELETE /api/v1/characters/:lodestone_id/verify` - Unverify character
- `GET /api/v1/characters/:lodestone_id/jwt` - Generate character JWT
- `POST /api/v1/jwt/verify` - Verify JWT token
- `GET /api/v1/jwt/jwks` - JSON Web Key Set

**OAuth2 Endpoints (Doorkeeper)**
- `/oauth/authorize` - Authorization endpoint
- `/oauth/token` - Token endpoint
- `/oauth/device_authorization` - Device flow initiation
- `/oauth/revoke` - Token revocation

### Feature Flags (Flipper)

Configured in `config/initializers/flipper.rb`:
- `user_signups` - Controls registration availability
- Actor groups: `:admins`, `:developers`
- Admin UI: `/admin/flipper`

### Security & Privacy Considerations

- **Minimal data collection** - Only store what's necessary
- **Entangled IDs** - Prevent cross-site character tracking (different ID per character per app)
- **Content Security Policy** - Strict CSP headers
- **Encryption** - ActiveRecord encryption + NaCl for sensitive data
- **JWT signing** - RSA keys with JWKS endpoint
- **2FA required** - TOTP or WebAuthn if any MFA method enabled
- **Cloudflare Turnstile** - CAPTCHA integration
- **Password strength** - zxcvbn validation
- **CSRF protection** - Standard Rails + Omniauth CSRF
- **Brakeman** - Security scanning in CI

**Important:** When making changes, ensure OWASP top 10 vulnerabilities are avoided (SQL injection, XSS, command injection, etc.). If insecure code is written, fix immediately.

### Frontend Architecture

- **Stimulus controllers** in `app/javascript/controllers/` for interactivity
- **Turbo Streams** for real-time updates (CharacterRegistration cards update live)
- **ActionCable** for WebSocket connections
- **TypeScript** with strict typing (`tsconfig.json`)
- **Bootstrap 5 + Hope UI** theme for styling
- **Tom Select** for enhanced dropdowns
- **WebAuthn JSON** helpers for passkey flows
- **Sentry browser SDK** for client-side error tracking

Build outputs: `app/javascript/*.* → app/assets/builds/`

### Important Patterns

1. **Service Objects** - Complex business logic lives in `app/services/` (OAuth, WebAuthn operations)
2. **Concerns** - Shared model behavior (e.g., `OmniauthAuthenticable`, `SystemRoleable`)
3. **Custom Validators** - OAuth-specific validation in `app/validators/oauth/`
4. **Doorkeeper Extensions** - Customizations in `lib/doorkeeper/`
5. **Polymorphic Associations** - OAuth resource_owner, ClientApplication owner
6. **UUID Primary Keys** - All tables use UUIDs, not integers
7. **Hotwire Broadcasts** - Models broadcast Turbo Stream updates (see CharacterRegistration)

### Controller Namespaces

- `/admin` - Administrative interface (Flipper, user management)
- `/api/v1` - REST API endpoints (JSON)
- `/oauth` - OAuth2 authorization flows (Doorkeeper)
- `/users` - User account management (Devise)
- `/developer` - Developer portal for OAuth application management

### Testing

- **RSpec 8** with FactoryBot
- Factories: `spec/factories/`
- Fixtures: `spec/fixtures/` (Lodestone profiles for character tests)
- **SimpleCov** for coverage reporting
- **Capybara + Selenium** for system tests
- **GitHub Actions** CI with PostgreSQL 16 service
- **Reviewdog** for RuboCop PR reviews

### Important Configuration

**Initializers to understand:**
- `config/initializers/doorkeeper.rb` - OAuth2 provider configuration
- `config/initializers/devise.rb` - Authentication setup
- `config/initializers/flipper.rb` - Feature flags
- `config/initializers/sidekiq.rb` - Background jobs + cron
- `config/initializers/webauthn.rb` - WebAuthn/passkey config

**Database:**
- PostgreSQL with `pgcrypto` extension
- UUID primary keys (configured in `config/application.rb`)
- 37 migrations creating enums, JSONB columns, array columns
- See `db/schema.rb` for current structure

**Logging:**
- `rails_semantic_logger` - Structured JSON logs
- Custom contextual logger middleware
- Sentry integration for error tracking

### Design Philosophy Reminders

1. **Simple > Sophisticated** - Solve the precise problem at hand, avoid scope creep
2. **Rails conventions first** - Use standard Rails patterns unless there's a compelling reason not to
3. **Security & privacy by default** - Review all data handling for privacy implications
4. **Maintainability & auditability** - Code should be easy to read and audit
5. **Ask before major changes** - If a request conflicts with design philosophy, clarify with the developer
6. **Pay attention to small details** - Things like database schema normalization, clean URLs, API schemas, 
well-structured namespaces, and semantic correctness are vital. This project handles security-sensitive data, so small 
details say a lot in terms of project quality and planning. The technicals should feel "friendly" and well-thought-out.

### Common Gotchas

- **Doorkeeper customizations** - Standard Doorkeeper docs may not apply; check `lib/doorkeeper/` for extensions
- **Polymorphic resource owners** - OAuth tokens can belong to Users OR CharacterRegistrations
- **Entangled IDs** - Character IDs are deterministically different per OAuth application for privacy
- **SECRET_KEY_BASE** - Used for deterministic token generation; set in credentials or `tmp/local_secret.txt` in dev
- **UUID PKs** - All primary keys are UUIDs, not integers
- **Turbo Streams** - Models may broadcast updates; check for `broadcasts_to` in models
- **Sidekiq throttling** - Lodestone jobs are rate-limited to avoid being blocked by Square Enix