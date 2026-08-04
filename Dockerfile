# syntax=docker/dockerfile:1

# Build the SvelteKit SSR server with the same pnpm version used by this checkout.
FROM node:22-bookworm-slim AS frontend

RUN corepack enable \
    && corepack prepare pnpm@11.10.0 --activate

WORKDIR /workspace/frontend

COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN --mount=type=cache,id=s/bf757565-64b8-44aa-9933-d12094ddf373-pnpm,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

COPY frontend/ ./
RUN pnpm build \
    && pnpm prune --prod

# Build a release Vapor executable and stage only its runtime files.
FROM swift:6.3-noble AS build

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY backend/Package.* ./
RUN --mount=type=cache,id=s/bf757565-64b8-44aa-9933-d12094ddf373-swiftpm,target=/root/.cache/org.swift.swiftpm \
    swift package resolve --force-resolved-versions

COPY backend/Sources ./Sources
COPY backend/Tests ./Tests

RUN --mount=type=cache,id=s/bf757565-64b8-44aa-9933-d12094ddf373-swift-build,target=/build/.build \
    swift build -c release \
        --product App \
        --static-swift-stdlib \
        -Xlinker -ljemalloc \
    && mkdir /staging \
    && cp "$(swift build -c release --show-bin-path)/App" /staging/App \
    && find -L "$(swift build -c release --show-bin-path)" \
        -regex '.*\.resources$' -exec cp -Ra {} /staging \; \
    && cp /usr/libexec/swift/linux/swift-backtrace-static /staging/

# Run the server with the libraries that Vapor, Fluent SQLite, and Swift need.
FROM ubuntu:noble AS runtime

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
        ca-certificates \
        gosu \
        libcurl4 \
        libjemalloc2 \
        libsqlite3-0 \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system \
        --skel /dev/null --home-dir /app vapor

WORKDIR /app

COPY --from=build --chown=vapor:vapor /staging /app
COPY --from=frontend /usr/local/bin/node /usr/local/bin/node
COPY --from=frontend --chown=vapor:vapor /workspace/frontend/build /app/frontend/build
COPY --from=frontend --chown=vapor:vapor /workspace/frontend/package.json /app/frontend/package.json
COPY --from=frontend --chown=vapor:vapor /workspace/frontend/node_modules /app/frontend/node_modules
COPY --chown=vapor:vapor docker-entrypoint.sh /app/docker-entrypoint.sh

# Production attachments use Railway object storage. The local directory exists
# only for development containers and is not part of the persistent SQLite volume.
RUN mkdir -p /data /app/Uploads \
    && chown -R vapor:vapor /data /app/Uploads \
    && chmod +x /app/docker-entrypoint.sh \
    && chmod -R a-w /app/frontend

ENV DATABASE_PATH=/data/flowboard.sqlite
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

EXPOSE 8080

# The entrypoint starts as root because Railway mounts new volumes as root.
# It fixes only the writable data paths and then uses gosu to run App as vapor.
ENTRYPOINT ["./docker-entrypoint.sh"]
