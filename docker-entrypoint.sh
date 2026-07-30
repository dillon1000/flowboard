#!/bin/sh
set -eu

# Railway mounts a persistent volume as root. Grant the application user access
# to SQLite and the legacy/local upload directory before commands run.
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

# An explicit command supports local development and maintenance tasks. The
# default production path applies pending migrations before it starts serving.
if [ "$#" -gt 0 ]; then
    exec gosu vapor ./App "$@"
fi

gosu vapor ./App migrate --yes --env production
exec gosu vapor ./App serve --env production --hostname 0.0.0.0 --port "${PORT:-8080}"
