# syntax=docker/dockerfile:1
FROM ruby:4.0.1-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

# Copy application code
COPY lib ./lib
COPY bin ./bin
COPY config ./config
COPY run_simple.rb ./

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

# Start the harness
CMD ["ruby", "run_simple.rb"]
