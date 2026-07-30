# Flowboard

Flowboard is a real Svelte Kanban workspace served by a Swift Vapor application.
Vapor uses Leaf for the account pages and authenticated app shell. Fluent stores
users, sessions, boards, and tasks in SQLite.

## Run locally

Install and build the Svelte bundle:

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

Re-run `pnpm build` after a frontend change. The build writes the application
bundle to `backend/Public`, where Vapor serves it on the same origin as the API.
This setup avoids CORS during normal use.

## Features

- Leaf-rendered registration, login, error, and authenticated app pages
- Bcrypt password hashes and HTTP-only, same-site sessions stored with Fluent
- User-owned boards with create, rename, delete, and direct URLs
- Persisted task creation, editing, deletion, search, and transactional movement
- Overview, Kanban board, all-task, and account settings pages
- Fluent models, relationships, migrations, validation, pagination, and SQLite
- Custom Svelte menus, date entry, modals, confirmation, and status messages
- Responsive navigation, keyboard focus, reduced motion, and mobile layouts

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

`backend/.env.example` defines the SQLite path and optional development CORS
origins. `frontend/.env.example` can point a separate frontend host at another
API URL, but the default same-origin setup needs neither value.

Production does not migrate automatically. Build the frontend, run migrations,
and then start the server:

```sh
cd frontend
pnpm build

cd ../backend
swift run App --env production migrate --yes
swift run App --env production serve
```

Production session cookies use the `Secure`, `HttpOnly`, and `SameSite=Strict`
attributes. Put Vapor behind HTTPS before you use production mode.

## Routes

Web pages:

- `GET /login` and `POST /login`
- `GET /register` and `POST /register`
- `POST /logout`
- `GET /app/**` for protected application pages

The JSON API is under `/api/v1`:

- `POST /auth/register`, `POST /auth/login`, and `POST /auth/logout`
- `GET /auth/me` and `PATCH /auth/me`
- `GET /boards`, `POST /boards`, `GET /boards/:id`
- `PATCH /boards/:id` and `DELETE /boards/:id`
- `GET /tasks?page=1&per=100`, with optional `boardID` and `status`
- `POST /tasks`, `PATCH /tasks/:id`, and `DELETE /tasks/:id`
- `POST /tasks/:id/move`
- `GET /health`

All board and task routes require a valid session and enforce board ownership.
