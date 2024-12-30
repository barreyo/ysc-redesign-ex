# ===============================================
# Stage 1: Build the Elixir/Phoenix application
# ===============================================
FROM hexpm/elixir:1.18.1-erlang-25.3.2.13-alpine-3.20.3 AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    python3

# Set environment variables
ENV MIX_ENV=prod \
    NODE_ENV=production

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy config files
COPY config config

# Copy assets
COPY priv priv
COPY assets assets

# Compile assets
RUN mix phx.digest

# Copy all application files
COPY lib lib

# Compile the application
RUN mix do compile, release

# ===============================================
# Stage 2: Create the final production image
# ===============================================
FROM alpine:3.21 AS app

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    ca-certificates

# Set environment variables
ENV PORT=4000 \
    LANG=C.UTF-8

# Create non-root user
RUN adduser -D app

# Set working directory
WORKDIR /app

# Copy the release from the builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/ysc ./
COPY --from=builder --chown=app:app /app/priv/static priv/static

# Use the non-root user
USER app

# Set the default command
CMD ["bin/ysc", "start"]

# Expose the port
EXPOSE 4000
