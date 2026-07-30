# Flowboard

Flowboard is a server-rendered project workspace built with Swift Vapor, Leaf,
Fluent, Turbo, and Stimulus. Fluent stores accounts, sessions, boards, saved
views, tasks, comments, checklists, attachments, templates, and sharing roles in
SQLite. The browser uses the same Vapor origin, so normal use does not need CORS.

## Run locally

Build the browser assets:

```sh
cd frontend
pnpm install
pnpm build
```

Start Vapor:

```sh
cd ../backend
swift run App serve
```

Open [http://localhost:8080/register](http://localhost:8080/register). Create an
account to get a private workspace and first board. The app creates
`backend/db.sqlite` and runs development migrations on first start.

Re-run `pnpm build` after a CSS or TypeScript change. Vite writes the asset
bundle to `backend/Public`, and Vapor renders all application pages with Leaf.
Turbo replaces full page reloads, while small Stimulus controllers handle
menus, dialogs, dates, drag and drop, theme state, search, and mobile navigation.

## Run with Docker

Build the production image from the repository root:

```sh
docker build -t flowboard .
```

For local HTTP use, start the container in development mode so the browser can
use a non-secure session cookie:

```sh
docker run --rm -p 8080:8080 \
  -v flowboard-data:/data \
  flowboard serve --env development --hostname 0.0.0.0 --port 8080
```

Open [http://localhost:8080/register](http://localhost:8080/register). The named
volume keeps the SQLite database and uploaded files when the container stops.

In production, start the image without an extra command:

```sh
docker run --rm -p 8080:8080 -v flowboard-data:/data flowboard
```

The production entrypoint applies pending Fluent migrations and then starts
Vapor. Production session cookies require HTTPS, so put this container behind a
TLS reverse proxy.

## Features

- Leaf-rendered registration, login, overview, task search, board, task detail,
  board settings, and account settings pages
- Bcrypt password hashes, CSRF protection, and persistent `HttpOnly`,
  `SameSite=Lax` Fluent sessions
- Generic OAuth 2.0 authorization-code login with PKCE, verified-email linking,
  and persisted provider identities
- Board, Table, Calendar, and Gallery views with saved grouping, filtering, and
  sorting rules
- Month navigation in Calendar views and custom Flatpickr date controls in forms
- Persisted tasks with status, priority, labels, assignee, dates, custom fields,
  comments, followers, checklists, and protected attachments
- Board templates, duplication, archive, JSON import and export, and task search
- Authenticated board sharing with Viewer, Commenter, Editor, and Admin roles
- Custom listboxes, dialogs, confirmations, file controls, and status messages;
  the application does not use native dropdowns, alerts, prompts, or calendars
- Light and dark themes, keyboard access, reduced motion, and responsive layouts
- Fluent models, relationships, migrations, validation, transactions,
  pagination, and SQLite

## Check the project

```sh
cd frontend
pnpm check
pnpm build

cd ../backend
swift build
swift test
```

The Swift Testing framework must be present in the selected Apple toolchain.
Use the full Xcode toolchain if Command Line Tools does not include it:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

## Configuration

`backend/.env.example` defines the SQLite path, optional development CORS
origins, and the generic OAuth settings. OAuth stays disabled until all six
required endpoint and client values are present. Register
`OAUTH_REDIRECT_URL` exactly with the provider; local development normally uses
`http://localhost:8080/oauth/callback`.

The default profile mapping reads `sub`, `email`, `name`, `picture`, and
`email_verified`.
The optional field settings accept dot-separated paths for providers with
nested profile data. Valid HTTPS picture URLs are synchronized on each OAuth
login. Verified email is required before a new provider identity can create or
link an account; disable that check only when the provider guarantees verified
emails through another contract.

Production does not migrate automatically. Build the frontend, run migrations,
and then start the server:

```sh
cd frontend
pnpm build

cd ../backend
swift run App --env production migrate --yes
swift run App --env production serve
```

Production session cookies use the `Secure`, `HttpOnly`, and `SameSite=Lax`
attributes. Lax mode lets the provider return to the OAuth callback while the
per-session state and PKCE verifier protect the transaction. Put Vapor behind
HTTPS before you use production mode.

## Routes

Web pages:

- `GET /login` and `POST /login`
- `GET /register` and `POST /register`
- `GET /oauth/start` and `GET /oauth/callback`
- `POST /logout`
- `GET /app/**` for protected application pages

The JSON API remains available under `/api/v1`:

- `POST /auth/register`, `POST /auth/login`, and `POST /auth/logout`
- `GET /auth/me` and `PATCH /auth/me`
- `GET /boards`, `POST /boards`, `GET /boards/:id`
- `PATCH /boards/:id` and `DELETE /boards/:id`
- `GET /tasks?page=1&per=100`, with optional `boardID` and `status`
- `POST /tasks`, `PATCH /tasks/:id`, and `DELETE /tasks/:id`
- `POST /tasks/:id/move`
- `GET /health`

All board and task routes require a valid session and enforce the board member's
role.
