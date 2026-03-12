# Phase 0 Requirements Document
## Agent Harness - Foundation + Observability + Docker

**Document Version:** 1.0  
**Phase:** 0  
**Last Updated:** 2026-03-11

---

## 1. Overview

### 1.1 What Phase 0 Achieves

Phase 0 establishes the foundational infrastructure for the Agent Harness project — a minimal working chat bot with full observability and containerization. This phase delivers:

- **Core async runtime** using Ruby 4+ with the `async` gem for I/O concurrency
- **Message routing** through interface-driven adapters (InputAdapter, LLMProvider, OutputAdapter)
- **Telegram integration** as the primary input/output channel
- **Multi-provider LLM integration**: Kimi Coding, MiniMax, OpenAI, and Grok (X) API
- **Observability stack** with structured JSON logs, Prometheus metrics, and optional WebUI
- **Secrets management** with AES-256-GCM encryption at rest
- **Docker containerization** from day one
- **Loadout system** with 3 base presets: minimal, chat-bot, observer

### 1.2 Out of Scope (Phase 0)

The following features are explicitly **NOT** part of Phase 0:
- Tool system (bash, file operations) — Phase 1
- Session management / context persistence — Phase 2
- Permission system / approval queues — Phase 3
- Subagent dispatch — Phase 4
- Background job queues — Phase 1+

---

## 2. Success Criteria

### 2.1 Functionality

| # | Criterion | Verification |
|---|-----------|--------------|
| F1 | Telegram bot responds to messages (< 3s p95 latency) | Manual test + metrics |
| F2 | Async loop handles 100+ concurrent connections | Load test |
| F3 | Structured JSON logs written to stdout and file | Log inspection |
| F4 | Metrics endpoint shows request latency histograms | Prometheus scrape |
| F5 | WebUI (if enabled) shows real-time traffic via SSE | Browser verification |
| F6 | Docker container passes health checks | `docker ps` health status |
| F7 | Secrets encrypted at rest, accessible via CLI | Decrypt and verify |
| F8 | Zero secret values in env vars or process list | Security audit |
| F9 | Loadout system: 3 base presets (minimal, chat-bot, observer) | CLI verification |
| F10 | LLM provider swappable (Kimi Coding, MiniMax, OpenAI, Grok) | Code test |
| F11 | User can customize loadout via YAML or CLI | Configuration test |

### 2.2 Testing

| # | Criterion | Coverage Target |
|---|-----------|-----------------|
| T1 | Unit tests for all interface implementations | 100% |
| T2 | Contract tests for InputAdapter, OutputAdapter, LLMProvider | 100% |
| T3 | Mock adapters for testing harness in isolation | All adapters |
| T4 | Integration test: full message flow with mocks | Core flow |
| T5 | Async testing utilities working | N/A |
| T6 | Test coverage | > 80% |
| T7 | CI pipeline running tests on push | N/A |

### 2.3 Performance

| Metric | Target |
|--------|--------|
| Response latency (p95) | < 3s |
| Concurrent connections | 100+ |
| Uptime | 99.9% |
| Observability coverage | 100% events |

---

## 3. Architecture

### 3.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Agent Harness                                │
│                      (Async Supervisor)                              │
└─────────────────────────────────────────────────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          ▼                         ▼                         ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  Input Adapter  │      │   LLM Provider   │      │ Output Adapter │
│   (Telegram)    │──────│    (OpenAI)      │──────│   (Telegram)    │
└─────────────────┘      └─────────────────┘      └─────────────────┘
          │                                           │
          │              ┌─────────────────┐          │
          └──────────────│  Message Router │──────────┘
                         └─────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          ▼                         ▼                         ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Observability │      │     Secrets     │      │   WebUI (Opt)   │
│  (Logs/Metrics)  │      │   (AES-256-GCM) │      │    (Falcon)     │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

### 3.2 Interface Definitions

#### InputAdapter Protocol

```ruby
module AgentHarness
  module InputAdapter
    def listen(&block)
      # Start listening for incoming messages
      # Yields message hash to block
      raise NotImplementedError
    end

    def stop
      # Gracefully stop listening
      raise NotImplementedError
    end

    def stopped?
      # Returns true if adapter is stopped
      raise NotImplementedError
    end
  end
end
```

**Message Hash Structure:**
```ruby
{
  id: "unique-message-id",      # String
  text: "user message",         # String
  chat_id: 123456789,           # Integer
  sender_id: 987654321,         # Integer (optional)
  timestamp: "2026-03-11T04:20:00Z",  # ISO 8601
  metadata: {}                 # Hash (optional, adapter-specific)
}
```

#### LLMProvider Protocol

```ruby
module AgentHarness
  module LLMProvider
    def generate(messages, tools: [], &block)
      # Generate completion from messages
      # messages: Array of {role: "user|assistant", content: "..."}
      # tools: Array of tool definitions (optional)
      # Yields chunks for streaming (optional)
      # Returns: {content: "...", tool_calls: [], usage: {...}}
      raise NotImplementedError
    end

    def available?
      # Returns true if provider is configured and working
      raise NotImplementedError
    end
  end
end
```

#### OutputAdapter Protocol

```ruby
module AgentHarness
  module OutputAdapter
    def send(message, context: {})
      # Send message to destination
      # message: String content
      # context: {chat_id: ..., message_id: ..., ...}
      raise NotImplementedError
    end

    def supports_streaming?
      # Returns true if streaming is supported
      raise NotImplementedError
    end
  end
end
```

### 3.3 Core Harness Flow

```ruby
require 'async'

class Harness
  def initialize(input:, output:, llm:, config:, logger:, metrics:, secrets:)
    @input = input
    @output = output
    @llm = llm
    @config = config
    @logger = logger
    @metrics = metrics
    @secrets = secrets
  end

  def start
    Async do |task|
      @supervisor = task
      @logger.info("harness_started", { version: VERSION })

      # Start input listener (async fiber)
      task.async { listen_for_messages }
      
      # Start periodic tasks (health checks, metrics)
      task.async { run_periodic_tasks }
      
      # Start WebUI if enabled
      task.async { start_webui } if @config.webui_enabled
      
      # Wait forever (or until stopped)
      task.sleep
    end
  end
  
  private
  
  def listen_for_messages
    @input.listen do |message|
      @logger.info("message_received", {
        message_id: message[:id],
        chat_id: message[:chat_id],
        text_length: message[:text].to_s.length
      })
      
      # Each message gets its own fiber
      Async { process_message(message) }
    end
  end
  
  def process_message(message)
    # Async HTTP call to LLM
    response = Async::HTTP::Internet.post(
      @llm.endpoint,
      @llm.headers,
      JSON.dump(build_request(message))
    )
    
    result = JSON.parse(response.read)
    
    # Send response
    @output.send(extract_content(result), context: message)
    
    @logger.info("response_sent", { chat_id: message[:chat_id] })
    
  rescue => e
    @logger.error("harness_error", {
      error: e.message,
      message_id: message[:id]
    })
    @output.send("Sorry, an error occurred", context: message)
  end
  
  def run_periodic_tasks
    loop do
      @logger.debug("health_check", {
        input_status: @input.stopped? ? "stopped" : "running",
        llm_available: @llm.available?
      })
      Async.sleep(60)
    end
  end
end
```

---

## 4. Components Specification

### 4.1 Telegram Adapter

**Location:** `lib/adapters/telegram_adapter.rb`  
**Gem:** `telegram-bot-ruby` (wrapped with async HTTP)

**Configuration:**
```yaml
# config/harness.yml
adapters:
  telegram:
    bot_token: "secrets:telegram.bot_token"
    api_url: "https://api.telegram.org"
```

**Implementation Notes:**
- Implements both InputAdapter and OutputAdapter
- Wraps `telegram-bot-ruby` with Async-compatible HTTP
- Maps Telegram Message objects to standard message hash format

### 4.2 LLM Providers

Phase 0 supports multiple LLM providers with a unified interface. All providers implement the `LLMProvider` protocol.

#### 4.2.1 Kimi Coding Provider

**Location:** `lib/adapters/kimi_coding_llm.rb`  
**HTTP:** `Async::HTTP` (non-blocking)

**Configuration:**
```yaml
# config/harness.yml
llm:
  provider: kimi_coding
  kimi_coding:
    api_key: "secrets:kimi_coding.api_key"
    model: "kimi-coding/k2p5"
    base_url: "https://api.moonshot.cn/v1"
    max_tokens: 8192
    temperature: 0.7
```

#### 4.2.2 MiniMax Provider

**Location:** `lib/adapters/minimax_llm.rb`  
**HTTP:** `Async::HTTP` (non-blocking)

**Configuration:**
```yaml
# config/harness.yml
llm:
  provider: minimax
  minimax:
    api_key: "secrets:minimax.api_key"
    group_id: "secrets:minimax.group_id"
    model: "MiniMax-M2.5"
    base_url: "https://api.minimax.chat/v1"
    max_tokens: 8192
    temperature: 0.7
```

#### 4.2.3 OpenAI Provider

**Location:** `lib/adapters/openai_llm.rb`  
**HTTP:** `Async::HTTP` (non-blocking)

**Configuration:**
```yaml
# config/harness.yml
llm:
  provider: openai
  openai:
    api_key: "secrets:openai.api_key"
    model: "gpt-4o-mini"
    base_url: "https://api.openai.com/v1"
    max_tokens: 2048
    temperature: 0.7
```

#### 4.2.4 Grok (X) Provider

**Location:** `lib/adapters/grok_llm.rb`  
**HTTP:** `Async::HTTP` (non-blocking)

**Configuration:**
```yaml
# config/harness.yml
llm:
  provider: grok
  grok:
    api_key: "secrets:grok.api_key"
    model: "grok-2"
    base_url: "https://api.x.ai/v1"
    max_tokens: 8192
    temperature: 0.7
```

### 4.3 Observability (Self-Hosted)

All observability components run **self-hosted** — no cloud services, no external dependencies. The stack runs entirely within the Docker container or local deployment.

**Self-Hosted Stack:**
| Component | Technology | Purpose |
|-----------|------------|---------|
| **Metrics Storage** | Prometheus (TSDB) | Time-series metrics, local retention |
| **Visualization** | Grafana | Dashboards, charts, alerts |
| **Log Storage** | File + optional Loki | Structured JSON logs, aggregation |
| **Tracing** | OpenTelemetry + Jaeger | Distributed request traces |

**Architecture:**
```
Agent Harness (instrumentation)
         │
         ├─→ Prometheus (scrape /metrics)
         ├─→ File logs (JSON structured)
         └─→ Jaeger (trace spans)
                  │
                  ▼
           Grafana (dashboards)
```

#### Structured Logging

**Location:** `lib/observability/logger.rb`

**Event Schema:**
```ruby
{
  timestamp: "2026-03-11T04:20:00Z",
  level: "info",
  component: "harness",
  event: "message_received",
  trace_id: "abc-123-def",
  context: {
    message_id: 123,
    chat_id: 456,
    text_length: 42
  }
}
```

**Required Events:**
| Event | Context Keys |
|-------|--------------|
| `harness_started` | `{version: string}` |
| `message_received` | `{message_id: string, chat_id: int, text_length: int}` |
| `llm_request_started` | `{chat_id: int, message_count: int}` |
| `llm_request_completed` | `{latency_ms: float}` |
| `llm_request_failed` | `{error: string, retry_count: int}` |
| `response_sent` | `{chat_id: int}` |
| `harness_error` | `{error: string, backtrace: array}` |

#### Metrics (Prometheus — Self-Hosted)

**Location:** `lib/observability/metrics.rb`  
**Server:** Prometheus runs locally (Docker container or host)

**Required Metrics:**
| Metric | Type | Description |
|--------|------|-------------|
| `harness_messages_total` | Counter | Total messages processed |
| `harness_llm_request_duration_seconds` | Histogram | LLM request latency |
| `harness_errors_total` | Counter | Error count by type |
| `harness_up` | Gauge | Harness running (1/0) |
| `harness_active_sessions` | Gauge | Active session count |

**Endpoints:**
- Metrics: `GET 0.0.0.0:9090/metrics`
- Health: `GET 0.0.0.0:3000/health`

### 4.4 Secrets Management

**Location:** `lib/secrets/file_provider.rb`

**Configuration:**
```yaml
# config/harness.yml
secrets:
  provider: file
  file:
    master_key_path: config/master.key
    secrets_path: config/secrets.yml.enc
```

**CLI Commands:**
```bash
bin/harness secrets:edit       # Open in $EDITOR, encrypt on save
bin/harness secrets:list       # Show names (not values)
bin/harness secrets:rotate <name>
```

**Security:**
- Master key: `config/master.key` (chmod 600, never committed)
- Audit log: Every access logged (name only, not value)
- Memory: Cleared on shutdown via `at_exit`

### 4.5 WebUI (Optional, Self-Hosted)

**Location:** `lib/webui/server.rb`  
**Server:** `falcon` (async HTTP, local only)

**Enabled via:** `ENABLE_WEBUI=true` environment variable  
**Access:** `http://localhost:8080` (binds to 127.0.0.1 by default, no external exposure)

**Endpoints:**
| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | WebUI static HTML |
| GET | `/health` | Health check |
| GET | `/metrics` | Prometheus metrics |
| GET | `/events` | SSE stream |

**WebUI Features (Phase 0):**
- Real-time message flow display
- Active sessions count
- LLM latency (last 10 requests)
- Error count
- Connection health status

### 4.6 Loadout System

**Location:** `lib/loadout/manager.rb`

See [LOADOUT-SYSTEM.md](./LOADOUT-SYSTEM.md) for detailed specification.

**Phase 0 Loadouts:**
| Loadout | Purpose | Components |
|---------|---------|------------|
| `minimal` | Barebones | Telegram + default LLM only |
| `chat-bot` | Standard chat | Full Phase 0 features |
| `observer` | Logging only | No LLM, logs all messages |

**Supported LLM Providers per Loadout:**
| Loadout | Default Provider | Alternate Providers |
|---------|------------------|---------------------|
| `minimal` | Kimi Coding | MiniMax, OpenAI, Grok |
| `chat-bot` | Configurable | All supported |
| `observer` | N/A (no LLM) | N/A |

---

## 5. File Structure

```
agent-harness/
├── bin/
│   └── harness                    # Main entry point
├── config/
│   ├── harness.yml               # Main config
│   ├── loadouts/
│   │   ├── minimal.yml
│   │   ├── chat-bot.yml
│   │   └── observer.yml
│   ├── master.key                # Secret encryption key (gitignored)
│   └── secrets.yml.enc           # Encrypted secrets
├── lib/
│   ├── agent_harness.rb          # Main entry
│   ├── version.rb
│   ├── harness/
│   │   ├── harness.rb            # Core async loop
│   │   └── router.rb             # Message routing
│   ├── interfaces/
│   │   ├── input_adapter.rb
│   │   ├── output_adapter.rb
│   │   └── llm_provider.rb
│   ├── adapters/
│   │   ├── telegram_adapter.rb
│   │   ├── kimi_coding_llm.rb
│   │   ├── minimax_llm.rb
│   │   ├── openai_llm.rb
│   │   └── grok_llm.rb
│   ├── observability/
│   │   ├── logger.rb
│   │   └── metrics.rb
│   ├── webui/
│   │   ├── server.rb
│   │   └── views/
│   │       ├── index.html
│   │       └── app.js
│   ├── secrets/
│   │   └── file_provider.rb
│   └── loadout/
│       └── manager.rb
├── logs/                         # Persistent logs (gitignored)
├── spec/                         # Tests
├── Dockerfile
├── docker-compose.yml
└── Gemfile
```

---

## 6. Dependencies

### Gemfile

```ruby
source "https://rubygems.org"
ruby ">= 4.0.0"

# Core
gem "async", "~> 2.0"
gem "async-http", "~> 0.60"
gem "falcon", "~> 0.45"

# Telegram
gem "telegram-bot-ruby", "~> 0.27"

# Configuration
gem "dry-configurable", "~> 1.0"
gem "dry-validation", "~> 1.0"

# Observability
gem "prometheus-client", "~> 4.0"

# Encryption
gem "rbnacl", "~> 5.0"

# Testing
group :development, :test do
  gem "minitest", "~> 5.25"
end
```

---

## 7. Testing Strategy

### Testing Philosophy

| Principle | Implementation |
|-----------|----------------|
| Interface mocking | Mock any adapter/provider via interface |
| Dependency injection | All dependencies injected |
| Async testing | Use `Async::Test` for async code |
| Contract tests | Ensure all providers satisfy interface |

### Contract Testing Example

```ruby
# spec/interfaces/input_adapter_contract.rb
module InputAdapterTests
  def test_receives_messages
    messages = []
    @adapter.listen { |msg| messages << msg }
    sleep 0.1
    
    assert messages.first.key?(:id)
    assert messages.first.key?(:text)
    assert messages.first.key?(:chat_id)
  end

  def test_stops_cleanly
    @adapter.stop
    assert @adapter.stopped?
  end
end
```

---

## 8. Docker Setup

### Dockerfile

```dockerfile
FROM ruby:4.0-slim as base
WORKDIR /app
RUN apt-get update && apt-get install -y curl

FROM base as dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

FROM base
COPY --from=dependencies /app/vendor ./vendor
COPY --from=dependencies /usr/local/bundle ./.bundle
COPY . .

EXPOSE 3000 9090
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["bundle", "exec", "ruby", "bin/harness"]
```

### docker-compose.yml

```yaml
version: '3.8'
services:
  agent-harness:
    build: .
    environment:
      - LOG_LEVEL=info
      - ENABLE_WEBUI=true
    ports:
      - "3000:3000"
      - "9090:9090"
    volumes:
      - ./config:/app/config:ro
      - ./logs:/app/logs
      - ./data:/app/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 3s
      retries: 3
    restart: unless-stopped
```

---

## 9. Implementation Checklist

### Week 1: Core Infrastructure
- [ ] Create repository with folder structure
- [ ] Set up Gemfile and dependencies (Ruby 4.0+)
- [ ] Create interface modules (InputAdapter, OutputAdapter, LLMProvider)
- [ ] Implement Kimi Coding LLM provider
- [ ] Implement MiniMax LLM provider
- [ ] Implement OpenAI LLM provider
- [ ] Implement Grok (X) LLM provider
- [ ] Implement Telegram adapter
- [ ] Create core async harness loop
- [ ] Implement message router

### Week 2: Observability
- [ ] Implement structured JSON logger
- [ ] Implement Prometheus metrics
- [ ] Add health endpoint
- [ ] Instrument harness with logging events

### Week 3: WebUI + Loadouts
- [ ] Implement Falcon server
- [ ] Create SSE endpoint
- [ ] Build static WebUI (HTML + vanilla JS)
- [ ] Create loadout manager
- [ ] Define 3 base loadouts

### Week 4: Secrets + Docker + Polish
- [ ] Implement file-based secrets provider
- [ ] Create secrets CLI
- [ ] Write Dockerfile and docker-compose.yml
- [ ] Write comprehensive tests
- [ ] CI pipeline setup
- [ ] Documentation review

---

## References

- Main Phases Document: [PHASES.md](./PHASES.md)
- Loadout System: [LOADOUT-SYSTEM.md](./LOADOUT-SYSTEM.md)
- Ruby Concurrency: [ruby-concurrency.md](./ruby-concurrency.md)
