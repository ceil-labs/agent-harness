# Agent Harness

Multi-provider LLM agent harness with Ruby 4+, async runtime, and extensible observability.

## Status

**Phase:** 0 — Foundation (Complete)  
**Last Updated:** 2026-03-14  
**Test Status:** 184 tests, 440 assertions, 0 failures

## What's Working

### ✅ Completed

| Component | Status | Notes |
|-----------|--------|-------|
| Interface Contracts | ✅ | InputAdapter, OutputAdapter, LLMProvider |
| Core Harness | ✅ | Async supervisor, message routing, DI container |
| Secrets Management | ✅ | AES-256-GCM encryption, audit logging |
| Observability | ✅ | JSON logger, Prometheus metrics, metrics server |
| Kimi Coding LLM | ✅ | Full implementation, Anthropic-compatible API |
| OpenCode-go LLM | ✅ | Multi-provider adapter (GLM, Kimi, MiniMax) |
| Telegram Adapter | ✅ | Full implementation with streaming support |
| Configuration | ✅ | ENV-based config with `.env` support |
| Docker Deployment | ✅ | Single-command start with docker-compose |
| Integration Tests | ✅ | 64 tests covering full flows, error paths |

## Quick Start

### Option 1: Docker (Recommended)

```bash
# Clone and enter directory
cd agent-harness

# Copy config template
cp .env.example .env
# Edit .env to set AGENT_ID, MODEL_PROVIDER, etc.

# Initialize secrets
bin/harness secrets_init
bin/harness secrets_edit
# Add: telegram.bot_token, kimi_coding.api_key (or opencode_go.api_key)

# Start everything
docker compose up -d

# View logs
docker compose logs -f harness
```

### Option 2: Local Development

```bash
# Install dependencies (Ruby 4.0+)
bundle install

# Initialize secrets
bin/harness secrets_init
bin/harness secrets_edit

# Copy config
cp .env.example .env

# Run tests
bundle exec rake test

# Start harness
bundle exec ruby run_phase0.rb
```

## Usage

### Using Observability

The harness supports both real observability (production) and null implementations (testing).

#### Production Mode (with observability)

```ruby
require "agent_harness"

# Create full observability stack
obs = AgentHarness::ObservabilityFactory.create_default(
  log_level: :info,
  log_file: "/app/logs/agent.log",
  metrics_port: 9090
)

# Use in harness
harness = AgentHarness::Harness.new(
  agent_id: "bot-001",
  input: telegram_adapter,
  output: telegram_adapter,
  llm: kimi_llm,
  logger: obs[:logger],
  metrics: obs[:metrics]
)

# Start metrics server (in separate fiber)
Async { obs[:metrics_server].start }

# Start harness
harness.start
```

**Metrics endpoints:**
- `GET /metrics` - Prometheus format
- `GET /health` - Health check

### Observability Stack (Prometheus + Grafana)

The harness includes a full observability stack via Docker Compose:

```bash
# Start harness + Prometheus + Grafana
docker compose up -d

# Access Prometheus UI (raw metrics)
open http://127.0.0.1:9091

# Access Grafana dashboards (visualization)
open http://127.0.0.1:3000
# Login: harness / harness (change in .env)
```

**Grafana Dashboard includes:**
- Message rate over time
- Harness up/down status
- Error rate with color thresholds
- LLM request duration (p50/p95/p99)
- Total messages & errors counters

**Configuration:**
- Prometheus scrapes harness metrics every 15s
- All services on shared Docker network (`agent-harness-network`)
- Ports bound to `127.0.0.1` for security
- Persistent volumes for data retention

#### Testing Mode (minimal overhead)

```ruby
# Use null implementations for tests
null_obs = AgentHarness::ObservabilityFactory.create_null()

harness = AgentHarness::Harness.new(
  agent_id: "test",
  input: mock_input,
  output: mock_output,
  llm: mock_llm,
  logger: null_obs[:logger],    # No-op
  metrics: null_obs[:metrics]   # No-op
)
```

### Using the Kimi Coding LLM Adapter

```ruby
require "agent_harness"

# Setup secrets
secrets = AgentHarness::Secrets::FileProvider.new(
  master_key_path: "config/master.key",
  secrets_path: "config/secrets.yml.enc"
)

# Create LLM adapter
llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets)

# Check availability
puts llm.available?  # => true

# Generate response
response = llm.generate([
  { role: "user", content: "Hello!" }
])

puts response[:content]               # => "Hello! How can I help?"
puts response[:usage][:total_tokens]  # => 27
```

## Testing Observability

### Test the Logger

```ruby
# Create logger
logger = AgentHarness::ObservabilityFactory.create_logger(
  level: :info,
  file_path: "/tmp/test.log"
)

# Log events
logger.info("test.started", { agent_id: "test-001" })
logger.warn("test.slow", { latency_ms: 5000 })

# Check output
cat /tmp/test.log
# => {"timestamp":"2026-03-12T...","level":"info","event":"test.started",...}
```

### Test the Metrics Server

```ruby
# Terminal 1: Start server
metrics = AgentHarness::ObservabilityFactory.create_metrics
server = AgentHarness::ObservabilityFactory.create_metrics_server(
  metrics: metrics, port: 9090
)

# Record some metrics
metrics.increment(:messages_total, labels: { agent_id: "test" })

# Start server
server.start  # Blocks
```

```bash
# Terminal 2: Query endpoints
curl http://localhost:9090/health
curl http://localhost:9090/metrics
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Agent Harness                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │ Async        │  │ Message      │  │ Error Handling           │  │
│  │ Supervisor   │  │ Router       │  │ (structured logging)     │  │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          ▼                         ▼                         ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  Input Adapter  │      │   LLM Provider  │      │ Output Adapter  │
│  (Telegram/Web) │      │ (Kimi/MiniMax/  │      │  (Telegram/Web) │
│                 │──────│  OpenAI/Grok)   │──────│                 │
└─────────────────┘      └─────────────────┘      └─────────────────┘
          │                       │
          └───────────────────────┴──────┐
                                         ▼
                              ┌─────────────────────┐
                              │   Observability     │
                              │  ┌───────────────┐  │
                              │  │ JSON Logger   │  │
                              │  │ Prometheus    │  │
                              │  │ Metrics       │  │
                              │  └───────────────┘  │
                              └─────────────────────┘
```

## Project Structure

```
lib/
├── agent_harness.rb              # Main entry + ObservabilityFactory
├── interfaces/
│   ├── input_adapter.rb          # Input contract
│   ├── output_adapter.rb         # Output contract
│   └── llm_provider.rb           # LLM contract
├── harness/
│   └── harness.rb                # Core async supervisor
├── adapters/
│   ├── kimi_coding_llm.rb        # Kimi Coding implementation
│   ├── opencode_go_llm.rb        # OpenCode-go implementation
│   └── telegram_adapter.rb       # Telegram bot adapter
├── secrets/
│   └── file_provider.rb          # Encrypted secrets
└── observability/
    ├── logger.rb                 # JSON structured logging
    ├── metrics.rb                # Prometheus metrics
    ├── metrics_server.rb         # HTTP server (/metrics, /health)
    └── null_observability.rb     # Null objects (testing/minimal)

spec/
├── interfaces/                   # Contract tests
├── harness/                      # Core tests
├── adapters/                     # Adapter tests
├── observability/                # Logger + metrics tests
└── secrets/                      # Security tests

config/
├── secrets.yml.enc               # Encrypted secrets
└── master.key                    # Encryption key (gitignored)

.observability/
├── prometheus.yml                # Prometheus scrape config
└── grafana/
    └── provisioning/             # Auto-configured dashboards
```

## Security

| Feature | Implementation |
|---------|----------------|
| Secrets at rest | AES-256-GCM encryption |
| Master key | 32-byte random, file permissions 0600 |
| Audit logging | Access logged to `config/.audit.log` |
| Temp files | `Tempfile` with 0600, not world-readable `/tmp` |
| Dependencies | `bundler-audit` for vulnerability scanning |

## CLI

```bash
bin/harness secrets_init      # Generate master.key
bin/harness secrets_edit      # Edit encrypted secrets
bin/harness secrets_list      # List secret names
bin/harness security_audit    # Run bundler-audit
```

## LLM Providers

| Provider | Status | Models | Format | Secret Key |
|----------|--------|--------|--------|------------|
| Kimi Coding | ✅ Ready | k2p5 | Anthropic-compatible | `kimi_coding.api_key` |
| OpenCode-go | ✅ Ready | glm-5, kimi-k2.5, minimax-m2.5 | OpenAI-compatible | `opencode_go.api_key` |

### Switching Providers

Set the `MODEL_PROVIDER` environment variable in `.env`:

```bash
# Use OpenCode-go (supports GLM, Kimi, MiniMax)
MODEL_PROVIDER=opencode_go
MODEL=kimi-k2.5

# Or use Kimi direct
MODEL_PROVIDER=kimi_coding
MODEL=k2p5
```

**Note:** Each provider requires its own API key in secrets:
- For `kimi_coding`: `bin/harness secrets_edit` → add `kimi_coding.api_key`
- For `opencode_go`: `bin/harness secrets_edit` → add `opencode_go.api_key`

Get your OpenCode-go API key at: https://opencode.ai/docs/providers/#opencode-go

## Development

```bash
# Run all unit tests
bundle exec rake test

# Run integration tests (Telegram → Harness → LLM flows)
bundle exec rake test:integration

# Run all tests (unit + integration)
bundle exec rake test:all

# Run with verbose output
bundle exec rake test_verbose

# Security audit
bin/security-audit
```

### Integration Tests

The integration test suite validates the complete message flow:

```
Telegram Message → Harness → LLM Provider → Response → Telegram
```

**Coverage:**
- **64 integration tests** — all passing
- Both providers: Kimi Coding (k2p5) and OpenCode-go (GLM-5, Kimi, MiniMax)
- Error paths: timeouts, auth failures, rate limits, invalid JSON
- Mock infrastructure for isolated testing (no real API calls)

**Key Files:**
```
spec/integration/
├── harness_flow_test.rb        # Full flow tests
├── kimi_coding_flow_test.rb    # Kimi provider tests
├── opencode_go_flow_test.rb    # OpenCode-go provider tests
├── telegram_to_llm_flow_test.rb # Telegram handling tests
└── error_path_flow_test.rb     # Error scenario tests
```

## Tailscale Access (Recommended)

Expose the observability stack securely over your Tailnet using [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve):

```bash
# Expose Grafana on its own HTTPS port
tailscale serve --bg --https=8443 http://127.0.0.1:3000

# Verify configuration
tailscale serve status
```

**Access via Magic DNS:**
- Grafana: `https://<your-hostname>.tailcd23a1.ts.net:8443`
- Prometheus: `https://<your-hostname>.tailcd23a1.ts.net:9091` (if exposed)
- Harness metrics: `https://<your-hostname>.tailcd23a1.ts.net:9090/metrics`

### Why Separate Ports?

We recommend **separate HTTPS ports** instead of path-based routing (`--set-path`):

| Approach | Command | Pros | Cons |
|----------|---------|------|------|
| **Separate ports** (Recommended) | `tailscale serve --https=8443 http://localhost:3000` | No app config needed, clean URLs, no path conflicts | Multiple ports to remember |
| Path-based | `tailscale serve --set-path /grafana http://localhost:3000` | Single port | Requires app subpath config, path conflicts |

**Example multi-service setup:**
```bash
# Main harness (local only - no tailscale needed)
# Grafana
tailscale serve --bg --https=8443 http://127.0.0.1:3000
# Prometheus (optional)
tailscale serve --bg --https=9091 http://127.0.0.1:9091
```

**Security:** All Tailscale serve endpoints are **tailnet-only** by default (not public internet). Perfect for agent networks and internal dashboards.

---

## Documentation

- [STATUS.md](./STATUS.md) — Current implementation status + testing guide
- [Phase 0 Requirements](./PHASE0-REQUIREMENTS.md) — Detailed specification
- Original research: `~/.openclaw/workspace/researches/in-progress/agent-harness/`

## License

MIT
