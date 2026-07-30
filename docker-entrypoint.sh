#!/bin/sh
set -eu

# An explicit command supports local development and maintenance tasks. The
# default production path applies pending migrations before it starts serving.
if [ "$#" -gt 0 ]; then
    exec ./App "$@"
fi

./App migrate --yes --env production
exec ./App serve --env production --hostname 0.0.0.0 --port "${PORT:-8080}"
