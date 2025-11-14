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
    npm

# Set environment variables
ENV MIX_ENV=prod \
    NODE_ENV=production

# Prepare build directory
RUN mkdir -p /app
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy config files
COPY config config
COPY rel rel

# Copy assets
COPY priv priv
COPY assets assets

# Copy all application files
COPY lib lib

# Compile the application
RUN mix do compile --warnings-as-errors, release

# Ensure priv/static directory exists (phx.digest creates it, but let's be safe)
RUN mkdir -p priv/static

# Install asset tools
RUN mix assets.setup

# Compile assets
RUN mix sentry.package_source_code
RUN mix assets.deploy

# ===============================================
# Stage 2: Create the final production image
# ===============================================
FROM alpine:3.22 AS app

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    ca-certificates

# Set environment variables
ENV PORT=4000 \
    LANG=C.UTF-8 \
    MIX_ENV=prod

# Create non-root user
RUN adduser -D app

# Set working directory
RUN mkdir -p /app
WORKDIR /app

# Copy the release from the builder stage
COPY --from=builder --chown=app:app /app/rel rel
COPY --from=builder --chown=app:app /app/_build/prod/rel/ysc ./
COPY --from=builder --chown=app:app /app/priv/static ./priv/static

# Use the non-root user
USER app

# Set the default command
CMD ["bin/ysc", "start"]

# Expose the port
EXPOSE 4000
