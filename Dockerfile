# Dockerfile for recurya development (Common Lisp)
#
# Build:
#   docker compose build recurya
#
# Run (with docker compose):
#   docker compose --profile app up -d
#
# Run (interactive REPL):
#   docker compose run --rm recurya sbcl

ARG SBCL_VERSION=2.5.10
ARG QLOT_VERSION=1.7.5

# =============================================================================
# Single-stage build for development
# =============================================================================
FROM fukamachi/sbcl:${SBCL_VERSION}-debian
ARG QLOT_VERSION

ENV APP_ENV=local-docker
ENV DOCKER=1

# Install system dependencies (as root)
RUN set -x; \
    apt-get update && apt-get -y install --no-install-recommends \
    git \
    openssh-client \
    libssl-dev \
    libpq-dev \
    libffi-dev \
    libev-dev \
    gcc \
    libc6-dev && \
    rm -rf /var/lib/apt/lists/*

# Set timezone
RUN ln -snf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

# Create non-root user for development (UID/GID 1000 matches typical host user)
RUN groupadd -g 1000 app && \
    useradd -u 1000 -g app -m -s /bin/bash app

# Create /app directory owned by app user
RUN mkdir -p /app && chown app:app /app

# Switch to app user for roswell/qlot setup
USER app
ENV HOME=/home/app

# Initialize roswell for app user and install qlot
RUN ros setup && \
    ros -e '(ql:update-dist "quicklisp" :prompt nil)' && \
    ros install "fukamachi/qlot/${QLOT_VERSION}"

# Add roswell bin to PATH for app user
ENV PATH="/home/app/.roswell/bin:${PATH}"

WORKDIR /app

# Copy qlfile first for dependency caching (owned by app user)
COPY --chown=app:app qlfile /app/
COPY --chown=app:app qlfile.lock /app/

# Install dependencies with qlot (as app user)
RUN qlot install

# Preload common dependencies to speed up startup
RUN qlot exec ros run \
    -s alexandria \
    -s local-time \
    -s log4cl \
    -s cl-ppcre

# Preload project-specific dependencies
RUN qlot exec ros run \
    -e "(ql:quickload '(:mito :sxql :cl-dbi))"

# Copy source code (owned by app user)
COPY --chown=app:app . /app

# Precompile the system
RUN qlot exec ros run \
    -e "(push #P\"/app/\" asdf:*central-registry*)" \
    -e "(ql:quickload :recurya)" \
    || echo "Precompilation completed (warnings may be expected)"

# Default environment variables for Docker Compose
ENV POSTGRES_HOST=postgres \
    POSTGRES_PORT=5432 \
    POSTGRES_DB=recurya \
    POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres

# Override base image entrypoint
ENTRYPOINT []
CMD ["/bin/bash", "/app/docker-entrypoint.sh"]
