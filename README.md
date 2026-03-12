# Agent Harness Project

Multi-provider LLM agent harness with Ruby 4+, async runtime, and full observability.

## Project Status

**Phase:** 0 — Foundation + Observability + Docker  
**Status:** Initialized  
**Started:** 2026-03-11

## Quick Links

- [Phase 0 Requirements](./PHASE0-REQUIREMENTS.md)
- Original Research: `/researches/in-progress/agent-harness/`

## LLM Providers

| Provider | Status | Model(s) |
|----------|--------|----------|
| Kimi Coding | Planned | kimi-coding/k2p5 |
| MiniMax | Planned | MiniMax-M2.5 |
| OpenAI | Planned | gpt-4o-mini |
| Grok (X) | Planned | grok-2 |

## Architecture

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
│   (Telegram)    │──────│  (Multi-provider)│──────│   (Telegram)    │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake spec

# Start with loadout
bin/harness start --loadout=chat-bot
```

---
*See PHASE0-REQUIREMENTS.md for full specification.*
