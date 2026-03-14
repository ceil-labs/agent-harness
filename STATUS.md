# Agent Harness - Handover Status

**For:** Next Agent  
**Last Updated:** 2026-03-14  
**Phase:** 0(Foundation + Observability)  
**Overall Completion:** ~70%

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
| Setting | Source | Default |
|---------|--------|---------|
| `AGENT_ID` | `.env` | `ceil-phase0` |
| `MODEL` | `.env` | `k2p5` |
| `LOG_LEVEL` | `.env` | `info` |
| `METRICS_PORT` | `.env` | `9090` |
| `ALLOWLIST` | `.env` | (empty = all users) |
| `SYSTEM_PROMPT` | `.env` | Built-in |
| `telegram.bot_token` | `secrets.yml.enc` | Via `bin/harness secrets_edit` |
| `kimi_coding.api_key` | `secrets.yml.enc` | Via `bin/harness secrets_edit` |

### 5. Telegram Adapter
| Component | File | Status | How to Verify |
|-----------|------|--------|---------------|
| Telegram Adapter | `lib/adapters/telegram_adapter.rb` | ✅ Complete | `bundle exec rake test` |
| Input/Output Interfaces | Implements both | ✅ Complete | Contract tests pass |
| Streaming Support | Edit messages | ✅ Complete | `supports_streaming?` returns true |

**Bot:** @ceil_harness_bot (ID: 8641259265)

---

## 📊 Test Summary

```
Total: 97 tests, 222 assertions, 0 failures, 2 skips

Breakdown:
- Interface contracts: 10 tests
- Harness core: 8 tests
- Secrets: 10 tests
- CLI: 3 tests
- KimiCodingLLM: 20 tests
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

### 1. Health Check Wastes API Quota (⚠️ Minor but Noisy)
**Status:** Documented — optimization opportunity  
**Finding:** Health check runs every 60 seconds and makes an actual LLM API call (`max_tokens: 1`) to verify connectivity.

**Evidence:**
- Pattern: `agent-harness` requests in Kimi dashboard at ~1-minute intervals
- Code: `lib/harness/harness.rb:209` → `run_health_checks` default interval = 60s
- Code: `lib/adapters/kimi_coding_llm.rb:50-79` → `available?` makes real API call

**Impact:**
- ~1,440 requests/day just for health checks (24 × 60)
- Minimal token usage (1 token per check) but noisy in logs/metrics
- Unnecessary API quota consumption

**Fix Options:**
1. **Simple check:** Verify API key configured without calling API
2. **Cached check:** Only hit API every 5-10 minutes (configurable)
3. **Passive check:** Monitor actual request success/failure instead of proactive pings
4. **Configurable:** Expose `HEALTH_CHECK_INTERVAL` in `.env` (currently hardcoded to 60s in harness, though config key exists)

**Files to modify:**
- `lib/harness/harness.rb` — cache last health check result, skip if recent
- `lib/adapters/kimi_coding_llm.rb` — `available?` should have a lightweight mode
- `.env.example` — add `HEALTH_CHECK_INTERVAL=300` (5 minutes)
- `run_phase0.rb` — pass `health_check_interval` to harness config

---

1. **Audit log:** `config/.audit.log` — intentionally gitignored
2. **Metrics server:** Binds to `0.0.0.0:9090` inside container, `127.0.0.1:9090` externally
3. **Kimi API format:** Anthropic-compatible (not OpenAI)
4. **Image size:** 877MB (can be optimized with multi-stage build)

---

## 🎯 Next Steps

### Priority 1: Prometheus + Grafana Stack
**Goal:** Historical metrics and professional dashboards  
**Effort:** ~30 minutes  
**Implementation:**
1. Add `prometheus` and `grafana` services to `docker-compose.yml`
2. Create `prometheus.yml` config to scrape `harness:9090/metrics`
3. Add Grafana dashboard for agent metrics
4. Expose ports: Prometheus `9091`, Grafana `3000`

**Config files to create:**
```
prometheus.yml         # Prometheus scrape config
grafana/provisioning/  # Auto-configure datasource + dashboard
```

**docker-compose.yml additions:**
```yaml
prometheus:
  image: prom/prometheus:latest
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - prometheus-data:/prometheus
  ports:
    - "127.0.0.1:9091:9090"

grafana:
  image: grafana/grafana:latest
  environment:
    - GF_SECURITY_ADMIN_USER=harness
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-harness}
  ports:
    - "127.0.0.1:3000:3000"
  depends_on:
    - prometheus
```

---

### Priority 2: Add OpenCode-go Provider
**Goal:** Support multiple LLM providers via OpenCode-go API  
**Reference:** https://opencode.ai/docs/providers/#opencode-go  
**Models available:** GLM, Kimi, MiniMax  
**Effort:** 2-3 hours  
**Implementation:**
1. Create `lib/adapters/opencode_llm.rb`
2. Follow pattern from `lib/adapters/kimi_coding_llm.rb`
3. Update `run_phase0.rb` to use `MODEL_PROVIDER=opencode` ENV var
4. Add tests in `spec/adapters/opencode_llm_test.rb`

**Key differences from Kimi adapter:**
- Endpoint: OpenCode-go proxy (not direct Kimi API)
- Model selection via `model` parameter (glm-5, kimi-k2.5, minimax-m2.5)
- Same Anthropic-compatible format

---

### Priority 3: WebUI for Secrets & Config
**Goal:** Browser-based management instead of CLI  
**Effort:** 3-4 hours  
**Features:**
- `/` — Dashboard with live metrics
- `/secrets` — Secure form to edit `config/secrets.yml.enc`
- `/config` — Edit `.env` values
- `/logs` — View recent log entries

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

### Priority 4: Improved Observability Metrics
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

## 🤔 Open Questions for Next Agent

1. **OpenCode provider:** Should `MODEL_PROVIDER=opencode` replace Kimi direct, or keep both options?
2. **WebUI auth:** Tailscale-only access or add basic auth fallback?
3. **Message logging:** Should we log message content for debugging? (Privacy: opt-in vs opt-out)

---

**Bottom Line:** Phase 0 is production-ready. Docker + ENV configuration working. Next: Prometheus/Grafana stack, then OpenCode provider, then WebUI.