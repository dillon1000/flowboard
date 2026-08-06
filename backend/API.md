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
| `GET` | `/auth/canvas-connections` | List owned Canvas connections. |
| `POST` | `/auth/canvas-connections` | Create a Canvas connection and one-time sync key. |
| `POST` | `/auth/canvas-connections/{connectionID}/rotate` | Rotate and return a new one-time sync key. |
| `DELETE` | `/auth/canvas-connections/{connectionID}` | Disconnect Canvas without deleting imported data. |

API key management needs a browser session. A Bearer key cannot create or revoke
another key. Create a key with a `name` and an optional future `expiresAt` date.
The response contains the raw `key` once. Flowboard stores its SHA-256 hash and a
short identifying prefix, so it cannot show the raw value again. List responses
include the prefix, creation date, optional expiry date, and last-used date.

Canvas connection management also needs a browser session. Create a connection
with `canvasOrigin`, which must be an HTTPS origin with no credentials, path,
query, or fragment. Creation and rotation return the raw `fcs_` sync key once.
Flowboard stores its SHA-256 hash and visible prefix. Deleting a connection
deletes its source links and locks, but it retains the imported boards and tasks.

## Canvas integration

The private Canvas extension uses a separate `fcs_` Bearer key. This key can
call only these routes:

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/integrations/canvas/status` | Read the connection origin, key prefix, and last sync state. |
| `POST` | `/integrations/canvas/sync` | Validate and apply one complete Canvas snapshot. |

An `fcs_` key fails on board, task, account, and API-key routes. A normal `fbk_`
API key cannot call the Canvas extension routes. The snapshot `canvasOrigin`
must equal the connection origin.

The sync body uses this version 1 shape:

```json
{
  "version": 1,
  "snapshotID": "one-unique-attempt-id",
  "canvasOrigin": "https://school.instructure.com",
  "capturedAt": "2026-08-06T12:00:00Z",
  "courses": [
    {
      "id": "42",
      "name": "Biology",
      "courseCode": "BIO-101",
      "termName": "Fall 2026",
      "htmlURL": "https://school.instructure.com/courses/42",
      "currentScore": 93.5,
      "currentGrade": "A",
      "assignments": [
        {
          "id": "9",
          "name": "Lab report",
          "descriptionText": "Submit the final report.",
          "htmlURL": "https://school.instructure.com/courses/42/assignments/9",
          "dueAt": "2026-09-01T20:00:00Z",
          "pointsPossible": 10,
          "submission": {
            "workflowState": "submitted",
            "grade": null,
            "score": null,
            "submittedAt": "2026-08-31T18:00:00Z",
            "late": false,
            "missing": false,
            "excused": false,
            "redoRequested": false
          }
        }
      ]
    }
  ]
}
```

The route accepts at most 5 MB, 100 courses, and 10,000 assignments. It rejects
duplicate remote IDs, invalid or cross-origin URLs, invalid dates, non-finite
scores, and oversized strings before a transaction writes data. A repeated
`snapshotID` returns success with `duplicate: true` and no writes. A snapshot
older than the last accepted capture time returns `409 Conflict`.

The response includes `snapshotID`, `duplicate`, `capturedAt`, `syncedAt`, and
counts for created, updated, archived, completed, and reopened records. The
server applies one accepted snapshot in one transaction, so a failed or partial
Canvas read must never call this route.

## Tap actions

`POST /taps/prepare` and `POST /taps/execute` accept a Tap bearer capability
without a user session. The preparation route returns the board-defined task
fields and their valid options. For a create-task action, send the scanner's
task values with the `token` and UUID `requestID` to the execution route. A
repeated request with the same ID returns the first result and does not change
a task twice. A successful response includes the user-written action name and
optional display description, plus the server result message.

Flowboard puts the raw token in the fragment of the URL written to the NFC tag.
Do not move it into a path or query because those values can enter proxy access
logs. Board administrators set the public title and description, then create,
reassign, disable, rotate, expire, and delete Tap actions in board settings.
The scanner enters task title, description, status, severity, dates, labels,
and configured board fields. The server stores only the token SHA-256 hash and
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
| Fields | `POST /boards/{boardID}/properties` |
| Workflow values | `POST /boards/{boardID}/task-options`, `PATCH /boards/{boardID}/task-options/{optionID}` |
| Tap actions | `POST /boards/{boardID}/tap-actions`; `PATCH, DELETE /boards/{boardID}/tap-actions/{tapActionID}` |

Call `POST /boards/{boardID}/templates/{templateID}/instantiate` to create a
task from a template. Member and configuration changes need administrator
access. Board viewers can read views and templates.

Call `POST /boards/{boardID}/duplicate` to copy a visible board into a new
private board. Call `GET /boards/{boardID}/export` to download a versioned JSON
document, or send that document as multipart field `file` to
`POST /boards/{boardID}/import`. Rotate a Tap credential with
`POST /boards/{boardID}/tap-actions/{tapActionID}/rotate`; the complete bearer
URL appears only in the create or rotate response.

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

For a Canvas-linked task, Canvas manages the title, description, due date, due
time, earned score, and points possible. PATCH requests for these fields return
`409 Conflict`. Status, archive state, and local planning fields remain editable.
Deleting a linked task or course also returns `409 Conflict` until its Canvas
connection is removed.

Task child resources are available at these paths:

| Resource | Paths |
| --- | --- |
| Comments | `GET, POST /tasks/{taskID}/comments`; `PATCH, DELETE /tasks/{taskID}/comments/{commentID}` |
| Checklist | `GET, POST /tasks/{taskID}/checklist`; `PATCH, DELETE /tasks/{taskID}/checklist/{itemID}` |
| Followers | `GET /tasks/{taskID}/followers`; `POST, DELETE /tasks/{taskID}/followers/me` |
| Attachments | `POST /tasks/{taskID}/attachments`; `GET, DELETE /attachments/{attachmentID}` |

Call `POST /tasks/{taskID}/checklist/{itemID}/move` with `targetIndex` to reorder
a checklist. Commenters can create comments, but only the comment author or a
board administrator can change them. Task edits and checklist changes need
editor access. Following a visible task needs viewer access.
Attachment uploads use multipart field `file` and accept at most 10 MB. Use
`GET /attachments/{attachmentID}/preview` for an inline preview of a supported
image, audio, video, or PDF file.

## Study planning

Study sessions belong to the signed-in user. A session has a `planned`,
`completed`, or `skipped` state. Completed sessions also contain
`actualMinutes` and `completedAt`. Only planned sessions can move, complete, or
skip.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/tasks/{taskID}/study-sessions` | List the current user's sessions for an assignment. |
| `POST` | `/tasks/{taskID}/study-sessions` | Add a planned session. |
| `PATCH` | `/study-sessions/{sessionID}` | Move a planned session or change its length. |
| `POST` | `/study-sessions/{sessionID}/complete` | Complete a session with `actualMinutes`. |
| `POST` | `/study-sessions/{sessionID}/skip` | Skip a session and return its work to the planning queue. |
| `DELETE` | `/study-sessions/{sessionID}` | Delete a session. |
| `POST` | `/study-sessions/plan` | Plan available work from assignment estimates and saved availability. |
| `POST` | `/study-sessions/repair` | Skip missed, late, or overloaded blocks and replan the returned work. |

`POST /study-sessions/plan` accepts optional `courseID` and
`dailyLimitMinutes` values. The daily limit remains available for old clients.
If it is absent, the planner uses the saved weekday capacity and subtracts
classes, work shifts, calendar conflicts, and blocked dates. Missed and skipped
sessions do not consume an assignment estimate, so the next plan includes that
work again.

The planning inputs and estimation inbox use these routes:

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/study-settings` | Read availability, estimate defaults, and onboarding state. |
| `PUT` | `/study-settings` | Replace availability, estimate defaults, and onboarding state. |
| `POST` | `/study-settings/estimates` | Save estimates for 1 to 200 assignments in one transaction. |

Weekday capacity is a map with keys `1` through `7`, where `1` is Sunday.
Recurring commitments accept `class` or `work` as their kind, a weekday list,
and `HH:mm` start and end times. Calendar conflicts use one `YYYY-MM-DD` date
and the same time format. Estimate defaults contain a stable ID, a name, a
minute value, and keywords that can match assignment titles.

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
