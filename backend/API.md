# Flowboard REST API

The JSON API is available under `/api/v1`. It accepts the same session cookie as
the web application or an API key in `Authorization: Bearer <key>`. Call
`POST /api/v1/auth/login` with an email address and a password to create a
session. All board data is private. Board roles control each read and write
operation.

Dates use ISO 8601. IDs are UUID strings. Validation failures return JSON with
an HTTP `400` or `422` status. Missing resources and resources that the current
user cannot access both return `404`, which prevents disclosure of private IDs.

## Authentication

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/auth/register` | Create an account and a first board. |
| `POST` | `/auth/login` | Create a session. |
| `POST` | `/auth/logout` | Delete the current session. |
| `GET` | `/auth/me` | Read the current account. |
| `PATCH` | `/auth/me` | Update the current account. |
| `GET` | `/auth/api-keys` | List API key metadata. |
| `POST` | `/auth/api-keys` | Create an API key. |
| `DELETE` | `/auth/api-keys/{apiKeyID}` | Revoke an API key. |

API key management needs a browser session. A Bearer key cannot create or revoke
another key. Create a key with a `name` and an optional future `expiresAt` date.
The response contains the raw `key` once. Flowboard stores its SHA-256 hash and a
short identifying prefix, so it cannot show the raw value again. List responses
include the prefix, creation date, optional expiry date, and last-used date.

## Tap actions

`POST /taps/execute` is the only API route that accepts a Tap bearer capability
without a user session. Send a `token` and a UUID `requestID`. A repeated request
with the same ID returns the first result and does not change a task twice.

Flowboard puts the raw token in the fragment of the URL written to the NFC tag.
Do not move it into a path or query because those values can enter proxy access
logs. Board administrators create, reassign, disable, rotate, expire, and delete
Tap actions in board settings. The server stores only the token SHA-256 hash and
shows each complete tag URL once.

## Boards

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/boards` | List accessible boards. |
| `POST` | `/boards` | Create a board. |
| `GET` | `/boards/default` | Read the first active board. |
| `GET` | `/boards/{boardID}` | Read a board and its tasks. |
| `PATCH` | `/boards/{boardID}` | Update a name, description, or archive state. |
| `DELETE` | `/boards/{boardID}` | Delete an owned board. |

`GET /boards` accepts `q` for name, description, and slug search. It accepts an
optional `archived=true|false` filter. A PATCH request changes only the supplied
fields. Send `description: null` to clear the description. Archive changes need
administrator access, and board deletion needs owner access.

Board child resources are available at these paths:

| Resource | Paths |
| --- | --- |
| Members | `GET, POST /boards/{boardID}/members`; `PATCH, DELETE /boards/{boardID}/members/{memberID}` |
| Views | `GET, POST /boards/{boardID}/views`; `GET, PATCH, DELETE /boards/{boardID}/views/{viewID}` |
| Templates | `GET, POST /boards/{boardID}/templates`; `GET, PATCH, DELETE /boards/{boardID}/templates/{templateID}` |

Call `POST /boards/{boardID}/templates/{templateID}/instantiate` to create a
task from a template. Member and configuration changes need administrator
access. Board viewers can read views and templates.

## Tasks

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/tasks` | List and filter tasks with pagination. |
| `GET` | `/tasks/search?q={query}` | Search task titles, descriptions, and public IDs. |
| `POST` | `/tasks` | Create a task. |
| `GET` | `/tasks/{taskID}` | Read one task. |
| `PATCH` | `/tasks/{taskID}` | Update supplied task fields. |
| `POST` | `/tasks/{taskID}/move` | Move a task to a status and zero-based index. |
| `DELETE` | `/tasks/{taskID}` | Delete a task and its stored attachments. |

Task list and search routes accept `page`, `per`, `boardID`, `status`,
`priority`, `assigneeID`, and `archived`. Archived tasks are excluded unless
`archived=true` is present. PATCH supports `title`, `description`, `status`,
`priority`, `labels`, `startAt`, `dueAt`, `assigneeID`, `properties`, and
`isArchived`. Send `null` to clear a nullable field.

Task child resources are available at these paths:

| Resource | Paths |
| --- | --- |
| Comments | `GET, POST /tasks/{taskID}/comments`; `PATCH, DELETE /tasks/{taskID}/comments/{commentID}` |
| Checklist | `GET, POST /tasks/{taskID}/checklist`; `PATCH, DELETE /tasks/{taskID}/checklist/{itemID}` |
| Followers | `GET /tasks/{taskID}/followers`; `POST, DELETE /tasks/{taskID}/followers/me` |

Call `POST /tasks/{taskID}/checklist/{itemID}/move` with `targetIndex` to reorder
a checklist. Commenters can create comments, but only the comment author or a
board administrator can change them. Task edits and checklist changes need
editor access. Following a visible task needs viewer access.

## Example

```sh
curl -i -c flowboard.cookies \
  -H 'Content-Type: application/json' \
  -d '{"email":"person@example.com","password":"correct-horse-battery"}' \
  http://localhost:8080/api/v1/auth/login

curl -b flowboard.cookies \
  'http://localhost:8080/api/v1/tasks/search?q=release&priority=high'

curl -b flowboard.cookies \
  -H 'Content-Type: application/json' \
  -d '{"name":"Release automation"}' \
  http://localhost:8080/api/v1/auth/api-keys

curl -H 'Authorization: Bearer fbk_REPLACE_WITH_THE_CREATED_KEY' \
  'http://localhost:8080/api/v1/boards'
```
