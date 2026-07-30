# Flowboard

Flowboard is a Svelte Kanban workspace backed by a Swift Vapor API. The frontend
uses a restrained Vercel-style interface, and the server uses Fluent ORM with
SQLite, migrations, validation, relations, pagination, and transactional moves.

## Run locally

Start the API:

```sh
cd backend
swift run App serve
```

Start the frontend in a second terminal:

```sh
cd frontend
pnpm install
pnpm dev
```

Open [http://localhost:5173](http://localhost:5173). The development server
creates and seeds `backend/db.sqlite` on first run.

## Check the project

```sh
cd backend
swift build
swift test

cd ../frontend
pnpm check
pnpm build
```

## Configuration

Copy the example environment files only when you need different values:

- `backend/.env.example` defines the SQLite path and allowed browser origins.
- `frontend/.env.example` defines the public API base URL.

Production does not migrate automatically. Run migrations before starting the
server:

```sh
cd backend
swift run App --env production migrate --yes
swift run App --env production serve
```

## API

The REST API is under `/api/v1`:

- `GET /boards/default` returns the starter board and its ordered tasks.
- `GET /boards` and `POST /boards` list and create boards.
- `GET /tasks?boardID=<uuid>&page=1&per=25` returns a paginated task list.
- `POST /tasks` creates a task.
- `PATCH /tasks/:taskID` replaces editable task fields.
- `POST /tasks/:taskID/move` moves and reorders a task in a transaction.
- `DELETE /tasks/:taskID` deletes a task.
- `GET /health` reports service health.
