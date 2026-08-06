# Flowboard

Flowboard is a server-rendered project workspace. SvelteKit owns every browser
route and renders the first response on the server. Swift Vapor provides the
private JSON API, authentication, and data services. Fluent stores accounts,
sessions, boards, views, tasks, comments, checklists, attachment metadata,
templates, and sharing roles in SQLite. Production attachments use Railway's
private S3-compatible storage.

## Run locally

Install and start the Vapor API on loopback:

```sh
cd backend
swift run App serve --hostname 127.0.0.1 --port 8081
```

In another terminal, install and start SvelteKit:

```sh
cd frontend
pnpm install
BACKEND_URL=http://127.0.0.1:8081 pnpm dev
```

Open [http://localhost:5173/register](http://localhost:5173/register). SvelteKit
proxies `/api` and `/oauth` to Vapor, so the browser uses one origin. Vapor
creates `backend/db.sqlite` and runs development migrations on first start.

## Run with Docker

Build the production image from the repository root:

```sh
docker build -t flowboard .
```

For local HTTP, use the development environment so session cookies do not need
TLS:

```sh
docker run --rm -p 8080:8080 \
  -e APP_ENVIRONMENT=development \
  -v flowboard-data:/data \
  flowboard
```

Open [http://localhost:8080/register](http://localhost:8080/register). The named
volume keeps the SQLite database and local attachments.

For production, start the same image without `APP_ENVIRONMENT`:

```sh
docker run --rm -p 8080:8080 -v flowboard-data:/data flowboard
```

The entrypoint applies pending migrations, starts Vapor on private loopback port
8081, and starts the SvelteKit Node server on public port 8080. Put the container
behind HTTPS because production session cookies use the `Secure` attribute.

## Deploy on Railway

Create one Railway service from this repository. Railway reads `railway.json`,
builds the root `Dockerfile`, sends traffic to its assigned `PORT`, and checks
`/health`. The health route succeeds only when SvelteKit can reach Vapor.

Attach one persistent volume at `/data`. It stores SQLite. Keep the service at
one replica because SQLite cannot support
several application containers writing to the same database.

Connect a Railway bucket with the six `AWS_*` values in
`backend/.env.example`. Production requires the complete bucket configuration,
and all new attachments use that private bucket.

Generate a public Railway domain. Add the OAuth values from
`backend/.env.example`, set `OAUTH_REDIRECT_URL` to the public HTTPS domain plus
`/oauth/callback`, and register that exact URI with the provider. Do not set
`PORT`; Railway supplies it. The container sets its private `BACKEND_URL`.

For NFC tags, add a short custom domain to the same service and set
`TAP_BASE_URL=https://tap.example.com/t`. If this value is absent, Flowboard
uses the current public domain plus `/t`.

Deploy from the Railway dashboard or from the repository root:

```sh
railway up
```

The Docker context excludes credentials, local databases, uploads,
dependencies, and generated output.

## Features

- SvelteKit SSR for registration, login, overview, task search, boards, task
  detail, board administration, account settings, and the public Tap runner
- Bcrypt password hashes and persistent `Secure`, `HttpOnly`, `SameSite=Lax`
  Fluent sessions
- OAuth 2.0 authorization-code login with PKCE, verified-email linking, and
  stored provider identities
- Board, Table, Calendar, Gantt, and Gallery views with saved grouping, filtering, and
  sorting rules
- Tasks with workflow values, labels, an assignee, dates, custom fields,
  comments, followers, checklists, and protected attachments
- Board templates, duplication, archive, JSON import and export, and task search
- Board sharing with Viewer, Commenter, Editor, and Admin roles
- Private Canvas course and assignment import through a restricted Chrome extension
- NFC Tap actions with scoped bearer links, use limits, cooldowns, expiration,
  rotation, and idempotent execution
- Light and dark themes, keyboard access, reduced motion, and responsive layouts
- Fluent models, relationships, migrations, validation, transactions,
  pagination, and SQLite

## Check the project

```sh
cd frontend
pnpm check
pnpm build
pnpm test

cd ../backend
swift build
swift test

cd ../extensions/canvas-sync
pnpm check
pnpm test
pnpm build
```

The Swift Testing framework must be present in the selected Apple toolchain. If
Command Line Tools does not include it, use the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

## Configuration

`backend/.env.example` defines the SQLite path, optional direct-API CORS
origins, the public Tap URL, Railway bucket values, and generic OAuth settings.
Development and tests use local attachment files when bucket values are absent.
OAuth stays disabled until all required endpoint and client values are present.

The default OAuth profile mapping reads `sub`, `email`, `name`, `picture`, and
`email_verified`. Optional field settings accept dot-separated paths for nested
provider data. Flowboard needs a verified email before it creates or links an
account unless the provider contract guarantees that state.

## Transactional email

The optional email Worker sends welcome, board membership, task assignment, and
task comment notifications. Set `NOTIFICATION_WORKER_URL`,
`NOTIFICATION_SHARED_SECRET`, and `PUBLIC_APP_URL` in the backend environment.
The shared secret must match the Worker secret named
`NOTIFICATION_SHARED_SECRET`.

Install and check the Worker with pnpm:

```sh
cd workers/email
pnpm install
pnpm run types
pnpm check
pnpm test
```

Use `pnpm run dev` for remote email binding development with test addresses you
control. Set the production secret with `pnpm wrangler secret put
NOTIFICATION_SHARED_SECRET --env production`, then deploy with
`pnpm run deploy`. Email Sending requires the onboarded `mail.11011.dev`
domain and a Workers Paid plan for arbitrary recipients.

Production does not migrate during Vapor configuration. The container
entrypoint runs this migration command before it starts either server:

```sh
cd backend
swift run App --env production migrate --yes
```

The Canvas release adds the `canvas_connections`, `canvas_course_links`, and
`canvas_assignment_links` tables. A production rollout must finish this
migration command before the updated Vapor or SvelteKit server starts. The
links retain imported boards and tasks when a connection is removed.

## Routes

SvelteKit owns these browser surfaces:

- `GET /login` and `GET /register`
- `GET /oauth/start` and `GET /oauth/callback`
- `GET /t` for the public NFC Tap runner
- `GET /app/**` for protected application pages
- `/api/**` as the same-origin gateway to Vapor

The JSON API is available under `/api/v1`. See
[the API guide](backend/API.md) for request fields, filters, role rules, and
examples.

- `POST /auth/register`, `POST /auth/login`, and `POST /auth/logout`
- `GET /auth/me` and `PATCH /auth/me`
- Session-only Canvas connection management under `/auth/canvas-connections`
- Restricted Canvas extension routes under `/integrations/canvas`
- Board, member, view, workflow, field, template, Tap, import, and export routes
  under `/boards`
- Task, move, comment, checklist, follower, and attachment routes under `/tasks`
- `POST /taps/prepare` and `POST /taps/execute`
- `GET /health`

Private routes require a valid session or API key and enforce each board role.
