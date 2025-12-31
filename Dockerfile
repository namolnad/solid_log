# Build stage
FROM ruby:3.3-slim AS builder

# Database adapter to build for: sqlite, postgres, or mysql
ARG DB_ADAPTER=sqlite

# Install build dependencies based on adapter
# Retry apt-get update to handle transient network issues
RUN apt-get update -qq || apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libyaml-dev && \
    if [ "$DB_ADAPTER" = "sqlite" ] || [ "$DB_ADAPTER" = "all" ]; then \
      apt-get install --no-install-recommends -y libsqlite3-dev; \
    fi && \
    if [ "$DB_ADAPTER" = "postgres" ] || [ "$DB_ADAPTER" = "all" ]; then \
      apt-get install --no-install-recommends -y libpq-dev; \
    fi && \
    if [ "$DB_ADAPTER" = "mysql" ] || [ "$DB_ADAPTER" = "all" ]; then \
      apt-get install --no-install-recommends -y default-libmysqlclient-dev; \
    fi && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy gemspecs and dependency files first for better caching
COPY solid_log-core/solid_log-core.gemspec solid_log-core/Gemfile* ./solid_log-core/
COPY solid_log-core/lib/solid_log/core/version.rb ./solid_log-core/lib/solid_log/core/version.rb

COPY solid_log-service/solid_log-service.gemspec solid_log-service/Gemfile* ./solid_log-service/
COPY solid_log-service/lib/solid_log/service/version.rb ./solid_log-service/lib/solid_log/service/version.rb

# Copy rest of the gems
COPY solid_log-core ./solid_log-core
COPY solid_log-service ./solid_log-service

# Build gems (but don't install yet - let bundler handle it)
WORKDIR /build/solid_log-core
RUN gem build solid_log-core.gemspec

WORKDIR /build/solid_log-service
RUN gem build solid_log-service.gemspec

# Install all dependencies via bundler (respects Gemfile.lock)
# This prevents duplicate gem versions
ARG DB_ADAPTER=sqlite
RUN bundle config set --local without 'development test' && \
    bundle config set --local path '/usr/local/bundle' && \
    bundle install && \
    gem install /build/solid_log-core/solid_log-core-*.gem && \
    gem install /build/solid_log-service/solid_log-service-*.gem && \
    if [ "$DB_ADAPTER" = "sqlite" ]; then \
      gem install sqlite3 -v '>= 2.1'; \
    elif [ "$DB_ADAPTER" = "postgres" ]; then \
      gem install pg -v '>= 1.1'; \
    elif [ "$DB_ADAPTER" = "mysql" ]; then \
      gem install mysql2 -v '>= 0.5'; \
    elif [ "$DB_ADAPTER" = "all" ]; then \
      gem install sqlite3 -v '>= 2.1' && \
      gem install pg -v '>= 1.1' && \
      gem install mysql2 -v '>= 0.5'; \
    fi

# Runtime stage
FROM ruby:3.3-slim

# Database adapter (must match builder stage)
ARG DB_ADAPTER=sqlite

# Install runtime dependencies based on adapter
# Retry apt-get update to handle transient network issues
RUN apt-get update -qq || apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libyaml-0-2 && \
    if [ "$DB_ADAPTER" = "sqlite" ] || [ "$DB_ADAPTER" = "all" ]; then \
      apt-get install --no-install-recommends -y libsqlite3-0; \
    fi && \
    if [ "$DB_ADAPTER" = "postgres" ] || [ "$DB_ADAPTER" = "all" ]; then \
      apt-get install --no-install-recommends -y libpq5; \
    fi && \
    if [ "$DB_ADAPTER" = "mysql" ] || [ "$DB_ADAPTER" = "all" ]; then \
      apt-get install --no-install-recommends -y default-mysql-client; \
    fi && \
    rm -rf /var/lib/apt/lists/*

# Create app user with UID 1000 (Rails convention)
RUN groupadd --gid 1000 solidlog && \
    useradd --uid 1000 --gid solidlog --shell /bin/bash --create-home solidlog

WORKDIR /app

# Copy installed gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application files
COPY --from=builder --chown=solidlog:solidlog /build/solid_log-service ./

# Create necessary directories and set ownership
RUN mkdir -p /app/storage /app/log /app/tmp && \
    chown -R solidlog:solidlog /app && \
    chmod -R go+rX /usr/local/bundle

# Switch to non-root user
USER solidlog

# Expose port
EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3001/health || exit 1

# Set default environment
ENV RACK_ENV=production \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    SKIP_BUNDLER=true \
    SOLIDLOG_PORT=3001 \
    SOLIDLOG_BIND=0.0.0.0

# Run the service using puma with SOLIDLOG_* env vars
# Using shell form to allow env var expansion
# Gems are installed globally, no bundle exec needed
CMD puma config.ru -b tcp://${SOLIDLOG_BIND}:${SOLIDLOG_PORT}
