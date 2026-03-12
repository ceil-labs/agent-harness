# Agent Harness

Multi-provider LLM agent harness with Ruby 4+, async runtime, and extensible observability.

## Status

**Phase:** 0 — Foundation (In Progress)  
**Last Updated:** 2026-03-12  
**Test Status:** 48 tests, 103 assertions, 0 failures

## What's Working

### ✅ Completed

| Component | Status | Notes |
|-----------|--------|-------|
| Interface Contracts | ✅ | InputAdapter, OutputAdapter, LLMProvider |
| Core Harness | ✅ | Async supervisor, message routing, DI container |
| Secrets Management | ✅ | AES-256-GCM encryption, audit logging |
| Kimi Coding LLM | ✅ | Full implementation, Anthropic-compatible API |
| Test Infrastructure | ✅ | Contract tests, mocks, 48 tests passing |

### 🚧 In Progress

| Component | Status |
|-----------|--------|
| Telegram Adapter | Planned |
| Configuration System | Not Started |
| Real Observability | Null objects only |
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

# Use the harness (see examples/)
```

## Usage

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

puts response[:content]           # => "Hello! How can I help?"
puts response[:usage][:total_tokens]  # => 27
```

### Using the Harness Core

```ruby
# Create adapters
input = MyInputAdapter.new
tput = MyOutputAdapter.new
llm = AgentHarness::Adapters::KimiCodingLLM.new(secrets: secrets)

# Initialize harness
harness = AgentHarness::Harness.new(
  agent_id: "my-agent-001",
  input: input,
  output: output,
  llm: llm,
  config: { system_prompt: "You are a helpful assistant." }
)

# Start (blocks until stop)
harness.start
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
```

## Project Structure

```
lib/
├── agent_harness.rb          # Main entry point
├── interfaces/
│   ├── input_adapter.rb      # Input contract
│   ├── output_adapter.rb     # Output contract
│   └── llm_provider.rb       # LLM contract
├── harness/
│   └── harness.rb            # Core async supervisor
├── adapters/
│   └── kimi_coding_llm.rb    # Kimi Coding implementation
├── secrets/
│   └── file_provider.rb      # Encrypted secrets
└── observability/
    └── null_observability.rb # Placeholders for Phase 4

spec/
├── interfaces/               # Contract tests
├── harness/                  # Core tests
├── adapters/                 # Adapter tests
└── secrets/                  # Security tests
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

- [Phase 0 Requirements](./PHASE0-REQUIREMENTS.md) — Detailed specification
- [STATUS.md](./STATUS.md) — Current implementation status
- Original research: `~/.openclaw/workspace/researches/in-progress/agent-harness/`

## License

MIT
