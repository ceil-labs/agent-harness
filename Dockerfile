# syntax=docker/dockerfile:1
FROM ruby:4.0.1-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle config set frozen false && \
    bundle config set without 'development test' && \
    bundle install

# Copy application code
COPY lib ./lib
COPY bin ./bin
COPY config ./config
COPY *.rb ./

# Create directories for runtime data
RUN mkdir -p /app/data /app/logs

# Environment
ENV RUBY_ENV=production
ENV AGENT_HARNESS_CONFIG=/app/config/harness.yml

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:9090/health || exit 1

# Run as non-root user
RUN useradd -m -s /bin/bash harness
RUN chown -R harness:harness /app
USER harness

# Expose metrics port
EXPOSE 9090

# Start the harness with unbuffered output
CMD ["ruby", "-e", "STDOUT.sync=true; load 'run_phase0.rb'"]
