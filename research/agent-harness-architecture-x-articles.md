# Research: Agent Harness Architecture

**Source:** X Articles ingestion  
**Date:** 2026-03-12  
**Topics:** Cloud Agents, Agent Harness Design, Multi-Agent Systems

---

## Article 1: You're thinking about cloud agents wrong

**Author:** Zach Lloyd (@zachlloydtweets)  
**Date:** March 10, 2026  
**URL:** https://x.com/zachlloydtweets/status/2031501189486121276

### Key Arguments

#### The Problem with "Cloud Computers"

Current "cloud computer" abstractions for agents have two problems:

1. **Statefulness** — Servers are stateful, which is inherently fragile (lose state when server dies) and not scalable
2. **Identity/Authentication model** — Single agent with universal permissions vs. multiple agents with scoped identities

#### The Better Abstraction: "Cloud Agents"

Instead of cloud computers, we need:
- **Scoped authentication** — Per-agent permissions, not universal user access
- **Team orchestration** — Multiple agents with separate identities and goals
- **Audit trails** — Track what agents do vs. what humans do

#### Proposed Architecture

```
Manager Agent (triggered by schedule/Slack/GitHub)
    ↓
Reads instructions
    ↓
Delegates to Subagents
    ↓
Each Subagent runs in isolated container
    ↓
Shared messaging via database/distributed filesystem
    ↓
Everything tracked, logged, steerable
```

**Key Components:**
- Database/persistent store with role-based permissions
- Timers and triggers to spin up agents
- Subagents with scoped permissions
- Messaging system for coordination

#### Relevance to Agent Harness

- Validates our multi-provider, interface-driven approach
- Supports the need for scoped permissions per agent
- Aligns with Docker/containerization strategy
- Emphasizes audit trails and observability

---

## Article 2: The Anatomy of an Agent Harness

**Author:** Viv Trivedy (@Vtrivedy10)  
**Date:** March 10, 2026  
**URL:** https://x.com/Vtrivedy10/status/2031408954517971368

### Core Definition

**Agent = Model + Harness**

> "The model contains the intelligence and the harness makes that intelligence useful."

A harness is every piece of code, configuration, and execution logic that isn't the model itself.

### Harness Components

| Component | Purpose |
|-----------|---------|
| **System Prompts** | Guide model behavior |
| **Tools, Skills, MCPs** | Extend model capabilities |
| **Infrastructure** | Filesystem, sandbox, browser |
| **Orchestration Logic** | Subagent spawning, handoffs, routing |
| **Hooks/Middleware** | Deterministic execution (compaction, lint checks) |

### Core Harness Primitives

#### 1. Filesystems for Durable Storage

**Why:** Models can only operate on knowledge within context window

**Benefits:**
- Workspace for reading data, code, documentation
- Incremental work offload (don't hold everything in context)
- Collaboration surface for multiple agents
- Git adds versioning, rollback, branching

**Key insight:** Filesystem is foundational for other harness features

#### 2. Bash + Code Execution

**Why:** General-purpose tool for autonomous problem solving

Instead of pre-building every tool, give agents bash to:
- Design tools on the fly via code
- Solve problems autonomously
- Not be constrained to fixed tool set

#### 3. Sandboxes for Safe Execution

**Why:** Running agent-generated code locally is risky

**Benefits:**
- Secure, isolated execution
- On-demand environment creation
- Scale across many tasks
- Allow-list commands, network isolation

#### 4. Memory & Search

**Why:** Models have no knowledge beyond weights and context

**Approaches:**
- **Memory files** (AGENTS.md) — Injected into context on start
- **Web Search** — Access beyond knowledge cutoff
- **MCP tools** (Context7) — Query up-to-date context

#### 5. Context Management (Battling Context Rot)

**Problem:** Models degrade as context window fills

**Solutions:**
- **Compaction** — Summarize context when near limit
- **Tool call offloading** — Keep head/tail, offload full output to filesystem
- **Skills** — Progressive disclosure, not all tools loaded at start

#### 6. Long Horizon Execution

**Requirements:**
- Durable state (filesystem, git)
- Planning (decompose goals into steps)
- Self-verification (tests, error loops)
- **Ralph Loop** — Intercept exit, reinject prompt in clean context

### Future of Harnesses

#### Model-Harness Co-evolution

- Agent products post-trained with models + harnesses in loop
- Models improve at actions harness designers prioritize
- Creates feedback loop: discover primitive → add to harness → train next model

**Trade-off:** Overfitting — models become tied to specific harness implementations

#### Harness Engineering Trends

- Orchestrating hundreds of agents in parallel
- Agents analyzing own traces to fix failure modes
- Dynamic tool/context assembly just-in-time

### Key Insight

> "A well-configured environment, the right tools, durable state, and verification loops make any model more efficient regardless of its base intelligence."

---

## Synthesis for Agent Harness Project

### Validated Design Decisions

| Our Approach | Article Support |
|--------------|-----------------|
| Interface-driven adapters | Harness = code around model |
| Multi-provider LLM support | Model-harness co-evolution |
| Async runtime with containers | Sandboxes, isolated subagents |
| Self-hosted observability | Audit trails, tracking, logging |
| File-based memory (AGENTS.md) | Memory files standard |
| Docker from day one | Cloud agents need isolation |

### New Considerations

1. **Context compaction** — Phase 2+ feature for long-running sessions
2. **Ralph Loop pattern** — For continuing work across context windows
3. **Progressive tool disclosure** (Skills) — Don't load all tools at start
4. **Self-verification hooks** — Pre-defined test suites, error loops
5. **Dynamic tool assembly** — Just-in-time tool/context configuration

### Implementation Notes

**Phase 0:**
- ✅ Filesystem abstraction via Docker volumes
- ✅ Scoped LLM providers (no universal access)
- ✅ Structured logging for audit trails
- ✅ Prometheus metrics for observability

**Phase 1+:**
- Subagent spawning with isolated permissions
- Context compaction strategies
- Tool offloading to filesystem
- Self-verification loops

### Open Questions

1. How do we implement the Ralph Loop in Ruby/async?
2. Should skills be dynamically loaded or pre-configured?
3. What's our compaction strategy for long sessions?
4. How do we track agent-specific audit trails vs. human actions?

---

**Related:** See `PHASE0-REQUIREMENTS.md` for implementation details  
**Next:** Review harness component design against these patterns
