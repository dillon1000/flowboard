# syntax=docker/dockerfile:1

# Build the browser bundle with the same pnpm version used by this checkout.
FROM node:22-bookworm-slim AS frontend

RUN corepack enable \
    && corepack prepare pnpm@11.10.0 --activate

WORKDIR /workspace/frontend

COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

COPY frontend/ ./
RUN mkdir -p /workspace/backend/Public \
    && pnpm build

# Build a release Vapor executable and stage only its runtime files.
FROM swift:6.3-noble AS build

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY backend/Package.* ./
RUN --mount=type=cache,target=/root/.cache/org.swift.swiftpm \
    swift package resolve --force-resolved-versions

COPY backend/Sources ./Sources
COPY backend/Resources ./Resources
COPY --from=frontend /workspace/backend/Public ./Public

RUN --mount=type=cache,target=/build/.build \
    swift build -c release \
        --product App \
        --static-swift-stdlib \
        -Xlinker -ljemalloc \
    && mkdir /staging \
    && cp "$(swift build -c release --show-bin-path)/App" /staging/App \
    && find -L "$(swift build -c release --show-bin-path)" \
        -regex '.*\.resources$' -exec cp -Ra {} /staging \; \
    && cp -R Resources Public /staging/ \
    && cp /usr/libexec/swift/linux/swift-backtrace-static /staging/

# Run the server with the libraries that Vapor, Fluent SQLite, and Swift need.
FROM ubuntu:noble AS runtime

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
        ca-certificates \
        libcurl4 \
        libjemalloc2 \
        libsqlite3-0 \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system \
        --skel /dev/null --home-dir /app vapor

WORKDIR /app

COPY --from=build --chown=vapor:vapor /staging /app
COPY --chown=vapor:vapor docker-entrypoint.sh /app/docker-entrypoint.sh

# SQLite and attachments share one mount so a container replacement keeps all
# user data. The symlink matches the upload path used by the Vapor application.
RUN mkdir -p /data/uploads \
    && chown -R vapor:vapor /data \
    && ln -s /data/uploads /app/Uploads \
    && chmod +x /app/docker-entrypoint.sh \
    && chmod -R a-w /app/Resources /app/Public

ENV DATABASE_PATH=/data/flowboard.sqlite
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

VOLUME ["/data"]
EXPOSE 8080

USER vapor:vapor

ENTRYPOINT ["./docker-entrypoint.sh"]
