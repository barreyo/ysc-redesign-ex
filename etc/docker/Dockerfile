# ===============================================
# Stage 1: Build the Elixir/Phoenix application
# ===============================================
FROM elixir:1.19-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    python3 \
    nodejs \
    npm \
    zstd

# Set environment variables
ENV MIX_ENV=prod \
    NODE_ENV=production

# Prepare build directory and install hex + rebar
WORKDIR /app
RUN mix local.hex --force && \
    mix local.rebar --force

# Install mix dependencies (with BuildKit cache mount for better caching)
COPY mix.exs mix.lock ./
RUN mkdir -p config
COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN --mount=type=cache,target=/root/.mix \
    mix deps.get --only prod && \
    mix deps.compile

# Ensure priv/static directory exists
RUN mkdir -p priv/static

# Copy application files needed for asset compilation
COPY rel rel
COPY priv priv
COPY assets assets

# Compile assets (with BuildKit cache mount for npm packages)
RUN --mount=type=cache,target=/root/.npm \
    mix sentry.package_source_code && \
    if [ -f priv/static/site.webmanifest ]; then \
    cp priv/static/site.webmanifest priv/static/site.webmanifest.orig; \
    fi && \
    mix assets.deploy && \
    if [ -f priv/static/site.webmanifest.orig ]; then \
    cp priv/static/site.webmanifest.orig priv/static/site.webmanifest && \
    rm priv/static/site.webmanifest.orig; \
    fi && \
    # Clean up npm/node artifacts to reduce image size
    rm -rf assets/node_modules /tmp/* /var/tmp/*

# Copy application source code
COPY lib lib

# Compile the application
RUN mix do compile --warnings-as-errors + release

# ===============================================
# Stage 2: Create the final production image
# ===============================================
FROM alpine:3.22 AS app

# Install runtime dependencies and create user in one layer
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    ca-certificates \
    tini \
    imagemagick && \
    adduser -D app && \
    mkdir -p /app && \
    chown app:app /app

WORKDIR /app

# Copy the release from the builder stage
COPY --from=builder --chown=app:app /app/rel rel
COPY --from=builder --chown=app:app /app/_build/prod/rel/ysc ./
COPY --from=builder --chown=app:app /app/priv/static ./priv/static

# Ensure bin scripts have execute permissions
RUN chmod +x bin/* 2>/dev/null || true

# Set environment variables before switching user
ENV PORT=4000 \
    LANG=C.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true

# Use the non-root user
USER app

ENTRYPOINT ["/sbin/tini", "-s", "--"]

# Set the default command
CMD ["/app/bin/server", "start"]

# Expose the port
EXPOSE 4000
