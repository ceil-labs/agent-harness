# Agent Harness

Multi-provider LLM agent harness with Ruby 4+, async runtime, and extensible observability.

## Status

**Phase:** 0 — Foundation (In Progress)  
**Last Updated:** 2026-03-12  
**Test Status:** 82 tests, 210 assertions, 0 failures

## What's Working

### ✅ Completed

| Component | Status | Notes |
|-----------|--------|-------|
| Interface Contracts | ✅ | InputAdapter, OutputAdapter, LLMProvider |
| Core Harness | ✅ | Async supervisor, message routing, DI container |
| Secrets Management | ✅ | AES-256-GCM encryption, audit logging |
| Observability | ✅ | JSON logger, Prometheus metrics, metrics server |
| Kimi Coding LLM | ✅ | Full implementation, Anthropic-compatible API |
| Test Infrastructure | ✅ | Contract tests, mocks, 82 tests passing |

### 🚧 In Progress

| Component | Status |
|-----------|--------|
| Telegram Adapter | Planned |
| Configuration System | Not Started |
| Docker | Not Started |

## Quick Start

```bash
# Install dependencies
bundle install

# Initialize secrets
bin/harness secrets_init
bin/harness secrets_edit
# Add: kimi_coding: { api_key: "your-key" }

# Run tests
bundle exec rake test
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
│   └── kimi_coding_llm.rb        # Kimi Coding implementation
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

| Provider | Status | Model | Format |
|----------|--------|-------|--------|
| Kimi Coding | ✅ Ready | k2p5 | Anthropic-compatible |
| MiniMax | ⬜ Planned | MiniMax-M2.5 | - |
| OpenAI | ⬜ Planned | gpt-4o-mini | OpenAI |
| Grok (X) | ⬜ Planned | grok-2 | OpenAI |

## Development

```bash
# Run all tests
bundle exec rake test

# Run with verbose output
bundle exec rake test_verbose

# Security audit
bin/security-audit
```

## Documentation

- [STATUS.md](./STATUS.md) — Current implementation status + testing guide
- [Phase 0 Requirements](./PHASE0-REQUIREMENTS.md) — Detailed specification
- Original research: `~/.openclaw/workspace/researches/in-progress/agent-harness/`

## License

MIT
