# syntax=docker/dockerfile:1
# Janus - LinuxServer.io (LSIO) style image
# Yggdrasil Connect server for Blessing Skin Server
# Modeled after SnowMoonSS/blessing-skin-server-lsio

ARG BUILDPLATFORM=linux/amd64
# Node.js major version used at build time & runtime (must be >= 22).
ARG NODE_MAJOR=24

###############################################################################
# Stage: deps — clone Janus source and install npm dependencies
###############################################################################
FROM --platform=${BUILDPLATFORM} node:${NODE_MAJOR}-slim AS deps
WORKDIR /opt/janus

ARG JANUS_REPO=https://github.com/bs-community/janus.git
ARG JANUS_VERSION=master
ARG JANUS_SOURCE=git

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates openssl curl && \
    rm -rf /var/lib/apt/lists/* && \
    if [ "${JANUS_SOURCE}" = "git" ]; then \
      echo "Cloning ${JANUS_REPO} @ ${JANUS_VERSION}" && \
      git clone --depth 1 --branch "${JANUS_VERSION}" "${JANUS_REPO}" . && \
      rm -rf .git; \
    else \
      echo "Only git source is supported for Janus"; \
      exit 1; \
    fi && \
    echo "Installing npm dependencies" && \
    npm ci

###############################################################################
# Stage: build — prepare default schema, generate Prisma client, compile NestJS
###############################################################################
FROM --platform=${BUILDPLATFORM} node:${NODE_MAJOR}-slim AS build
WORKDIR /opt/janus

# openssl is needed so Prisma can detect the right engine at build time (used
# for TS type-checking). The runtime later regenerates the client for its own OS.
RUN apt-get update && \
    apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=deps /opt/janus ./

# schema.prisma must exist for prisma generate. We ship the example and use it
# as-is for the default (no DB_PREFIX) case. At runtime, init-janus-config
# regenerates the client if DB_PREFIX is provided.
RUN cp prisma/schema.prisma.example prisma/schema.prisma && \
    npx prisma generate && \
    echo "Building NestJS app" && \
    npm run build && \
    rm -f prisma/schema.prisma && \
    echo "Build ready"

###############################################################################
# Stage: runtime — LinuxServer.io base + Node + production deps + dist
###############################################################################
FROM ghcr.io/linuxserver/baseimage-debian:trixie

ARG NODE_MAJOR=24

ENV S6_VERBOSITY=1

# Install Node.js (>= 22.12) from NodeSource's apt repository (arch aware).
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      openssl \
      gnupg \
      netcat-openbsd; \
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs; \
    node --version; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Copy the built application (dist/, node_modules incl. prisma CLI, prisma dir,
# package.json, schema templates & migrations).
COPY --from=build /opt/janus /app

# Bring in s6-overlay services
COPY root/ /

RUN chmod +x /etc/s6-overlay/s6-rc.d/init-janus-config/run && \
    chmod +x /etc/s6-overlay/s6-rc.d/svc-janus/run && \
    echo "Setup complete"

EXPOSE 3000
VOLUME ["/config", "/data"]
