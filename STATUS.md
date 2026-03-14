# Agent Harness - Handover Status

**For:** Next Agent
**Last Updated:** 2026-03-14
**Phase:** 0 (Foundation + Observability)
**Overall Completion:** ~85%

---

## ✅ What's Working (Verified)

### 1. Core Infrastructure
| Component | File | Status | How to Verify |
|-----------|------|--------|---------------|
| Harness Core | `lib/harness/harness.rb` | ✅ | `bundle exec rake test` (8 tests pass) |
| Interface Contracts | `lib/interfaces/*.rb` | ✅ | `bundle exec rake test` (10 contract tests) |
| Secrets Management | `lib/secrets/file_provider.rb` | ✅ | `bin/harness secrets_list` shows keys |
| Kimi Coding LLM | `lib/adapters/kimi_coding_llm.rb` | ✅ | See verification script below |

### 2. Observability
| Component | File | What It Does | How to Test |
|-----------|------|--------------|-------------|
| JSON Logger | `lib/observability/logger.rb` | Structured logging to stdout/file | See "Test Logger" below |
| Prometheus Metrics | `lib/observability/metrics.rb` | Counters, histograms, gauges | See "Test Metrics" below |
| Metrics Server | `lib/observability/metrics_server.rb` | HTTP server on port 9090 | `curl localhost:9090/metrics` |
| Null Objects | `lib/observability/null_observability.rb` | No-ops for testing | Use in tests |

### 3. Docker Deployment (✅ 2026-03-14)
| Component | Status | Notes |
|-----------|--------|-------|
| Image | ✅ Single image: `agent-harness:latest` | Consolidated from multiple tags |
| docker-compose.yml | ✅ Clean configuration | ENV support added |
| `.env.example` | ✅ Created | Template for non-secret config |
| One-command start | ✅ Working | `docker compose up -d` |

**Verified:**
```bash
docker ps | grep agent-harness
# agent-harness   Up X (healthy)   agent-harness:latest

curl http://127.0.0.1:9090/health
# {"status":"healthy"}
```

### 4. Configuration (✅ 2026-03-14)
| Setting | Source | Default | Options |
|---------|--------|---------|---------|
| `AGENT_ID` | `.env` | `ceil-phase0` | Any string |
| `MODEL_PROVIDER` | `.env` | `kimi_coding` | `kimi_coding`, `opencode_go` |
| `MODEL` | `.env` | Provider-dependent | See below |
| `LOG_LEVEL` | `.env` | `info` | `debug`, `info`, `warn`, `error` |
| `METRICS_PORT` | `.env` | `9090` | Any port |
| `ALLOWLIST` | `.env` | (empty = all) | Comma-separated Telegram IDs |
| `SYSTEM_PROMPT` | `.env` | Built-in | Any string |
| `telegram.bot_token` | `secrets.yml.enc` | Via `bin/harness secrets_edit` | - |
| `kimi_coding.api_key` | `secrets.yml.enc` | Via `bin/harness secrets_edit` | For `kimi_coding` provider |
| `opencode_go.api_key` | `secrets.yml.enc` | Via `bin/harness secrets_edit` | For `opencode_go` provider |

**Model Selection by Provider:**
- `kimi_coding`: `k2p5`
- `opencode_go`: `glm-5`, `kimi-k2.5`, `minimax-m2.5`

### 5. Telegram Adapter
| Component | File | Status | How to Verify |
|-----------|------|--------|---------------|
| Telegram Adapter | `lib/adapters/telegram_adapter.rb` | ✅ Complete | `bundle exec rake test` |
| Input/Output Interfaces | Implements both | ✅ Complete | Contract tests pass |
| Streaming Support | Edit messages | ✅ Complete | `supports_streaming?` returns true |

**Bot:** @ceil_harness_bot (ID: 8641259265)

---

## ✅ Recently Completed

### OpenCode-go Provider (✅ 2026-03-14)
**Branch:** `feat/opencode-go-provider` → ready to merge
**Tested by:** Manual testing with GLM-5

**What was built:**
- New `OpenCodeGoLLM` adapter for OpenCode-go API
- Supports models: `glm-5`, `kimi-k2.5`, `minimax-m2.5`
- OpenAI-compatible request/response format
- Provider switching via `MODEL_PROVIDER` ENV variable
- Removed periodic health checks (now config-only validation)
- Passive error tracking via metrics

**Files changed:**
- `lib/adapters/opencode_go_llm.rb` - New adapter
- `lib/adapters/opencode_go_llm_test.rb` - 22 tests
- `lib/agent_harness.rb` - Added require
- `run_phase0.rb` - Provider switching support
- `.env.example` - Documented provider options
- `README.md` - Provider documentation
- `lib/harness/harness.rb` - Removed periodic health checks
- `spec/harness/harness_test.rb` - Removed health check tests

**Key decisions:**
- Config-only `available?` (no HTTP health checks)
- Passive error monitoring via Grafana
- Model IDs: `glm-5`, `kimi-k2.5`, `minimax-m2.5` (not prefixed)
- Endpoint: `https://opencode.ai/zen/go/v1/chat/completions`

**Test Results:**
- All 120 tests pass (278 assertions)
- Manual test: Successfully responded via Telegram using GLM-5

---

### Prometheus + Grafana Stack (✅ 2026-03-14)
**Branch:** `feat/prometheus-grafana` → merged to `main`
**Reviewed by:** GLM 5

**What was built:**
- Added Prometheus service (scrapes harness metrics every 15s)
- Added Grafana with auto-provisioned dashboards
- Dashboard includes: message rate, error rate, LLM duration (p50/p95/p99), up status, totals
- All services on shared Docker network with persistent volumes
- Security: ports bound to 127.0.0.1
- Documented in README

**Files changed:**
- `docker-compose.yml` - Added prometheus and grafana services
- `prometheus.yml` - Scrape configuration
- `grafana/provisioning/` - Auto-configured datasource and dashboard
- `grafana/dashboards/harness-dashboard.json` - Dashboard definition
- `.env.example` - Added Grafana credentials
- `README.md` - Added observability stack documentation

**Access:**
- Prometheus: http://127.0.0.1:9091
- Grafana: http://127.0.0.1:3000 (harness/harness)

---

### Health Check Optimization (✅ 2026-03-14)
**Branch:** `fix/health-check-cache` → merged to `main`
**Reviewed by:** GLM 5

**What was fixed:**
- Health checks now run every 5 minutes (configurable via `HEALTH_CHECK_INTERVAL`) instead of 60 seconds
- Added lightweight mode to `available?` - only checks API key config, no HTTP call
- Periodic health checks use lightweight mode; full connectivity check only at startup
- ~80% reduction in API calls (1,440/day → 289/day)

**Files changed:**
- `lib/harness/harness.rb` - Added health check caching with TTL
- `lib/adapters/kimi_coding_llm.rb` - Added `lightweight:` parameter to `available?`
- `.env.example` - Added `HEALTH_CHECK_INTERVAL=300`
- `run_phase0.rb` - Wired up configuration
- Tests - Added 4 new tests for caching behavior

---

## 📊 Test Summary

```
Total: 120 tests, 278 assertions, 0 failures, 2 skips

Breakdown:
- Interface contracts: 10 tests
- Harness core: 8 tests (removed 4 health check tests)
- Secrets: 10 tests
- CLI: 3 tests
- KimiCodingLLM: 20 tests
- OpenCodeGoLLM: 22 tests (new)
- Observability: 34 tests (logger + metrics + server)
- Telegram adapter: Contract tests

Run: bundle exec rake test
```

---

## 🚀 Quick Start

```bash
cd ~/.openclaw/agent-harness

# 1. Configure secrets (first time only)
bin/harness secrets_init
bin/harness secrets_edit# Add telegram.bot_token and kimi_coding.api_key

# 2. Configure non-secret options
cp .env.example .env
# Edit .env as needed

# 3. Start
docker compose up -d

# 4. Verify
curl http://127.0.0.1:9090/health
docker logs agent-harness --tail 20
```

---

## 🎯 Phase 0 Definition of Done

| Criterion | Status | How to Verify |
|-----------|--------|---------------|
| F1: Telegram bot responds | ✅ Complete | Message @ceil_harness_bot |
| F2: 100+ concurrent connections | ✅ Core supports | Load test |
| F3: Structured JSON logs | ✅ Complete | `docker logs agent-harness` |
| F4: Metrics endpoint | ✅ Complete | `curl http://127.0.0.1:9090/metrics` |
| F5: Docker one-command start | ✅ Complete | `docker compose up -d` |
| F6: ENV configuration | ✅ Complete | `.env` file |
| F7: Secrets encrypted | ✅ Complete | `bin/harness secrets_list` |

---

## 📝 Key Files

| File | Purpose |
|------|---------|
| `run_phase0.rb` | Main entry point (ENV-aware) |
| `docker-compose.yml` | Container orchestration |
| `.env.example` | Configuration template |
| `config/secrets.yml.enc` | Encrypted API keys |
| `config/master.key` | Encryption key (gitignored) |
| `bin/harness` | CLI for secrets management |

---

## ⚠️ Known Issues / Notes

1. **Audit log:** `config/.audit.log` - intentionally gitignored
2. **Metrics server:** Binds to `0.0.0.0:9090` inside container, `127.0.0.1:9090` externally
3. **Kimi API format:** Anthropic-compatible (not OpenAI)
4. **Image size:** 877MB (can be optimized with multi-stage build)

---

## 🎯 Next Steps

### Priority 1: Integration Tests
**Goal:** Add first end-to-end integration test (Telegram → Harness → LLM → Response)
**Effort:** 2-3 hours
**Why now:** Fills testing gap; validates full message flow works with both providers

**Implementation Plan:**
1. Create `spec/integration/harness_flow_test.rb`
2. Add WebMock/VCR for HTTP stubbing
3. Create test fixtures for Telegram messages
4. Test full flow: `telegram_message → harness → llm → response`

**Files to create:**
```
spec/integration/harness_flow_test.rb    # Full flow test
spec/fixtures/telegram_messages.yml      # Sample message payloads
spec/support/mock_telegram.rb            # Telegram client mocks
spec/support/mock_llm.rb                 # LLM provider mocks
```

---

### Priority 2: WebUI for Secrets & Config
**Goal:** Browser-based management instead of CLI
**Effort:** 3-4 hours
**Features:**
- `/` - Dashboard with live metrics
- `/secrets` - Secure form to edit `config/secrets.yml.enc`
- `/config` - Edit `.env` values
- `/logs` - View recent log entries

**Architecture:**
```
Harness WebUI (:8080)
├── Falcon/Rack routes
├── Auth via Tailscale (or basic auth)
└── Calls existing Secrets::FileProvider
```

**New files:**
```
lib/webui/server.rb        # Falcon-based HTTP server
lib/webui/routes.rb        # Route definitions
lib/webui/views/           # ERB templates
webui/dashboard.erb        # Metrics dashboard
webui/secrets.erb         # Secrets editor form
webui/config.erb          # Config editor form
```

---

### Priority 3: Improved Observability Metrics
**Goal:** Better visibility into agent behavior
**Effort:** 1-2 hours
**Add to `lib/observability/metrics.rb`:**

| Metric | Type | Purpose |
|--------|------|---------|
| `messages_in_flight` | Gauge | Concurrent messages being processed |
| `llm_tokens_total` | Counter | Token usage by type (input/output) |
| `response_size_bytes` | Histogram | Response message sizes |

**Update `lib/harness/harness.rb` to track:**
- Increment `messages_in_flight` on message start
- Decrement on message complete
- Record token usage from LLM response

---

## 📦 Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Harness Container                      │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ Telegram    │───▶│ Harness     │───▶│ Telegram    │     │
│  │ (Input)     │    │ (Core)      │    │ (Output)    │     │
│  └─────────────┘    └──────┬──────┘    └─────────────┘     │
│                            │                                │
│                      ┌─────▼─────┐                          │
│                      │ LLM       │◄── OpenCode-go (GLM/    │
│                      │           │    Kimi/MiniMax)        │
│                      └───────────┘                          │
│                                                            │
│  ┌─────────────┐    ┌─────────────┐                        │
│  │ WebUI       │    │ Metrics     │                        │
│  │ :8080       │    │ :9090       │                        │
│  │ /secrets    │    │ /metrics    │───► Prometheus         │
│  │ /config     │    └─────────────┘     :9091             │
│  │ /metrics    │                              │            │
│  │ /logs       │                              ▼            │
│  └─────────────┘                          Grafana         │
│                                            :3000           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧪 Testing Strategy

**Current State:** 97 unit tests passing, 0 integration tests

**Challenges:**
- Telegram API - can't use real bot in automated tests
- LLM API - expensive/slow to call real LLM in tests
- Secrets - can't hardcode tokens in repo
- Async code - testing async/await patterns

**Recommended Approach: Hybrid**
- **Unit tests:** Full mocking (fast, isolated)
- **Integration tests:** Mock external APIs, test internal wiring
- **E2E tests:** Manual only (too expensive to automate)

**Implementation Plan:**
1. Create `spec/integration/` directory
2. Add WebMock/VCR for HTTP stubbing
3. Create test fixtures for Telegram messages
4. Add integration test for full message flow: `telegram_message → harness → llm → response`

**Files to create:**
```
spec/integration/harness_flow_test.rb    # Full flow test
spec/fixtures/telegram_messages.yml      # Sample message payloads
spec/support/mock_telegram.rb            # Telegram client mocks
spec/support/mock_llm.rb                 # LLM provider mocks
```

---

## 🤔 Open Questions for Next Agent

1. **OpenCode provider:** Should `MODEL_PROVIDER=opencode` replace Kimi direct, or keep both options?
2. **WebUI auth:** Tailscale-only access or add basic auth fallback?
3. **Message logging:** Should we log message content for debugging? (Privacy: opt-in vs opt-out)

---

**Bottom Line:** Phase 0 is production-ready. Docker + ENV configuration working. Next: Prometheus/Grafana stack, then OpenCode provider, then WebUI.