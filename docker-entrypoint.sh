#!/bin/sh
set -eu

# Railway mounts the SQLite and legacy attachment volume as root. Grant the
# application user access before migrations or either server starts.
mkdir -p /data/uploads
chown vapor:vapor /data /data/uploads
for database_file in \
    "$DATABASE_PATH" \
    "$DATABASE_PATH-shm" \
    "$DATABASE_PATH-wal"
do
    if [ -e "$database_file" ]; then
        chown vapor:vapor "$database_file"
    fi
done

# An explicit command supports local development and Vapor maintenance tasks.
# The default path migrates once, then starts Vapor privately and SvelteKit publicly.
if [ "$#" -gt 0 ]; then
    exec gosu vapor ./App "$@"
fi

# Railway uses production by default. Local HTTP runs can select development so
# Vapor does not mark the session cookie as Secure.
app_environment="${APP_ENVIRONMENT:-production}"
gosu vapor ./App migrate --yes --env "$app_environment"

backend_port="${BACKEND_PORT:-8081}"
public_port="${PORT:-8080}"
gosu vapor ./App serve --env "$app_environment" --hostname 127.0.0.1 --port "$backend_port" &
backend_pid=$!

gosu vapor env \
    HOST=0.0.0.0 \
    PORT="$public_port" \
    BACKEND_URL="http://127.0.0.1:$backend_port" \
    BODY_SIZE_LIMIT=11M \
    PROTOCOL_HEADER=x-forwarded-proto \
    HOST_HEADER=x-forwarded-host \
    ADDRESS_HEADER=x-forwarded-for \
    XFF_DEPTH=1 \
    node frontend/build &
frontend_pid=$!

# Stop both servers when Railway stops the container or either server exits.
shutdown() {
    kill -TERM "$backend_pid" "$frontend_pid" 2>/dev/null || true
    wait "$backend_pid" "$frontend_pid" 2>/dev/null || true
}
trap shutdown INT TERM EXIT

while kill -0 "$backend_pid" 2>/dev/null && kill -0 "$frontend_pid" 2>/dev/null; do
    sleep 1
done
exit 1
