# Lux (Luxembourg) 

### AI-Powered Natural Language Game Development for Roblox Studio

[![Downloads](https://img.shields.io/badge/downloads-1500%2B-brightgreen)]()
[![Python](https://img.shields.io/badge/python-3.11-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

**Lux** is a production AI agent that enables game development in plain English. Describe what you want to build, and an autonomous AI analyzes your project, generates code, and executes modifications—all within Roblox Studio.

🎮 **[Install from Roblox Creator Store](https://create.roblox.com/store/asset/131392966327387/Lux-AI-Agentic-Lua-Coding-Assistant)** | 📖 **[Read Full Architecture Doc](./lux-architecture.md)**

---

## Why This Matters

Game development requires deep technical knowledge: Lua scripting, Roblox APIs, UI systems, networking, game architecture. **Lux removes that barrier.**

Instead of:
```lua
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
-- ...50 more lines for a sprint system
```

You write:
```
Add a sprint system with stamina that regenerates over time
```

Lux handles the rest.

---

## Key Features

### 🤖 Agentic AI Architecture
- **LangGraph orchestration** with autonomous decision-making
- **Tool system** for project exploration (search, list, metadata, full script access)
- **Continuous execution model**: Completes entire tasks in single response (no "continue" prompts)

### 🔄 Novel Communication Pattern
- **Polling bridge** enables bidirectional AI communication over Roblox's one-way HTTP constraint
- **Async event synchronization** for real-time agent data requests
- 100-300ms tool latency despite round-trip architecture

### 💰 Cost-Optimized
- **~90% reduction in API costs** via lazy loading (65k → 5.5k tokens/request)
- Progressive disclosure: Top-level structure free, on-demand deep exploration
- Hash-based deduplication prevents redundant operations

### 🔒 Privacy-First
- **Zero data retention**: Sessions stored in-memory only, deleted after 1 hour
- **BYOK (Bring Your Own Key)**: User controls LLM access and costs
- **Local execution**: All game modifications happen client-side

### ⚡ Production-Ready
- Hash-verified script modifications (prevents concurrent edit conflicts)
- Session management with TTL-based cleanup (1hr sessions, 5min cleanup)
- Graceful timeout handling (30s tool timeout) and fault tolerance
- Pydantic validation for all requests/responses

---

## How It Works

### System Architecture

```
┌─────────────────┐
│  ROBLOX STUDIO  │
│  ┌───────────┐  │
│  │  Chat UI  │  │ ◄─── User: "Add a health bar"
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │  Project  │  │ ◄─── Scans game structure (lazy)
│  │  Scanner  │  │
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │   HTTP    │  │
│  │  Client   │  │
│  └─────┬─────┘  │
└────────┼────────┘
         │ HTTPS
         ▼
┌─────────────────┐
│  CLOUD BACKEND  │
│  ┌───────────┐  │
│  │  FastAPI  │  │ ◄─── Routing, session management
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │ AI Agent  │  │ ◄─── LangGraph + LangChain
│  │(LangGraph)│  │      Reasoning + tool calling
│  └─────┬─────┘  │
└────────┼────────┘
         │ HTTPS
         ▼
┌─────────────────┐
│   OPENROUTER    │ ◄─── Gemini/Claude/GPT-4
└─────────────────┘
```

### The Polling Bridge Pattern

**The Problem:** Roblox plugins can only make outbound HTTP requests. They cannot receive incoming connections or use WebSockets.

**The Solution:** Async polling with event-based synchronization.

```
1. Plugin → Backend: "Add a health bar"
2. Backend → AI Agent: Start processing
3. AI Agent: "I need to see the current PlayerScript"
   ├─► Creates pending_request
   └─► Awaits asyncio.Event()  [BLOCKS]
4. Plugin → Backend: GET /poll (every 100ms)
   └─► Receives: {requests: ["fetch PlayerScript"]}
5. Plugin reads script from game
6. Plugin → Backend: POST /respond with script content
   └─► event.set()  [WAKES AGENT]
7. AI Agent: Continues with data, generates actions
8. Backend → Plugin: Response with actions
9. User clicks "Apply" → Changes execute in game
```

This enables true bidirectional communication within platform constraints.

**[→ See Interactive Demo](https://sergeykudelin.com/lux/polling-bridge)** (click to understand visually)

---

## Technical Highlights

### Agent Tools (4 Levels)

| Tool | Purpose | Cost |
|------|---------|------|
| **Project Map** | Top-level structure | FREE (auto-included) |
| **search_project(query)** | Semantic search across scripts | ~200 tokens |
| **get_metadata(script)** | Quick preview (type, lines, deps) | ~100 tokens |
| **get_full_script(script)** | Complete source + hash | ~1,000 tokens |

**Design:** Agents explore progressively from cheap to expensive operations.

### Action Types (8 Primitives)

All game modifications compose from 8 fundamental actions:

- `set_property` - Modify attributes (color, size, position)
- `create_instance` - Create new objects (Parts, UI, folders)
- `delete_instance` - Remove objects
- `move_instance` - Reparent in hierarchy
- `clone_instance` - Duplicate from templates
- `create_script` - Add new scripts
- `modify_script` - Update existing scripts (hash-verified)
- `delete_script` - Remove scripts

### Hash Verification

Script modifications require hash verification to prevent data loss:

```python
1. Agent requests: get_full_script("PlayerController")
2. Plugin returns: {source: "...", hash: "a3f2c1..."}
3. Agent modifies code, creates action with original_hash
4. Executor verifies current hash == original_hash
5. If match → apply changes
   If mismatch → reject (concurrent edit detected)
```

**[→ See Implementation Details](https://sergeykudelin.com/lux/hash-verification)** (code walkthrough)

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Plugin** | Lua/Roblox | UI, project scanning, action execution |
| **Backend** | Python 3.11 / FastAPI | API server, session management |
| **Agent Framework** | LangGraph | Stateful AI orchestration |
| **LLM Integration** | LangChain | Tool calling, LLM abstraction |
| **LLM Provider** | OpenRouter | Multi-model access (Gemini/Claude/GPT) |
| **Validation** | Pydantic | Request/response schemas |
| **Deployment** | Railway | Cloud hosting, auto-scaling |
| **Distribution** | Roblox Creator Store | Plugin delivery, auto-updates |

---

## Usage

### 1. Install Plugin
Download from [Roblox Creator Store](https://create.roblox.com/store/asset/)

### 2. Get API Key
Create account at [OpenRouter](https://openrouter.ai) and get API key

### 3. Configure
Open Lux in Roblox Studio → Paste API key → Save

### 4. Start Building
```
You: "Create a click-to-collect coin system"

Lux: I'll create a complete coin collection system with:
1. Create Part "Coin" in Workspace
2. Set Coin.Shape to Ball
3. Set Coin.BrickColor to "Bright yellow"
4. Create Script "CoinCollector" in ServerScriptService
   [Full script with touch detection and player points]

[✓ Apply All Actions]
```

---

## Architecture Deep Dive

### Session Management

```
Session
├── session_id              # Unique identifier (UUID)
├── conversation_history    # Last 20 messages (sliding window)
├── project_map             # Current game structure
├── cached_metadata         # Tool response cache
├── cached_scripts          # Script content cache
├── pending_requests        # Awaiting plugin data
├── fulfilled_data          # Received from plugin
├── action_queue            # Generated actions
└── executed_hashes         # Deduplication tracking
```

**Lifecycle:**
- Created on first request
- Stored in-memory only
- Expires after 1 hour of inactivity (configurable via `SESSION_TTL`)
- Cleaned up by background task every 5 minutes (configurable via `CLEANUP_INTERVAL`)

### Cost Optimization

**Before (Naive Approach):**
```
Every request includes:
• Full project tree (all levels)     ~5,000 tokens
• All script sources                 ~50,000 tokens
• Previous conversation              ~10,000 tokens
                                     ────────────
Total per request:                   ~65,000 tokens
```

**After (Luxembourg):**
```
Every request includes:
• Top-level structure only           ~500 tokens
• Conversation (last 20 msgs)        ~5,000 tokens
                                     ────────────
Base per request:                    ~5,500 tokens

On-demand (only when needed):
• Search results                     ~200 tokens
• Script metadata                    ~100 tokens
• Full script (per script)           ~1,000 tokens
```

**Result:** ~90% reduction in token usage

**[→ See Cost Analysis Breakdown](https://sergeykudelin.com/lux/cost-optimization)** (token math)

---

## Performance

| Operation | Typical Latency | Source |
|-----------|-----------------|--------|
| Polling interval | 100ms | `task.wait(0.1)` in pollLoop |
| Tool execution (round-trip) | 100-300ms | Polling + network latency |
| Tool timeout | 30s max | `settings.poll_timeout = 30` |
| LLM response | 1-5s | Model-dependent (OpenRouter) |
| Action execution | <50ms per action | Local Lua execution |
| **Full request cycle** | **2-10s** | Depends on tool calls needed |

**Provable:** All timing values come from actual `config.py` and `Main.server.lua` code.

**[→ See Performance Benchmarks](https://sergeykudelin.com/lux/performance)** (real traces)

---

## Security & Privacy

### What We Store
- ✓ Conversation history (in-memory, session-scoped)
- ✓ Project structure (in-memory, session-scoped)
- ✓ Tool response cache (in-memory, session-scoped)

### What We NEVER Store
- ✗ API keys (processed, never persisted)
- ✗ User identities
- ✗ Project content after session ends
- ✗ Conversation logs to disk

### Data Lifecycle
1. Created: On first request
2. Held: In memory only (no database)
3. Expired: After 1 hour of inactivity (`settings.session_ttl = 3600`)
4. Deleted: Permanently removed from memory

---

## Metrics

| Metric | Value | Source |
|--------|-------|--------|
| Active Installations | **1,500+** | Roblox Creator Store |
| Backend Lines of Code | 813 | Python/FastAPI |
| Plugin Lines of Code | 1,424 | Lua/Roblox |
| Supported Action Types | 8 | `models.py` Action enum |
| Available Tools | 4 | search, list, metadata, full_script |
| Session TTL | 1 hour | `config.py` line 10 |
| Tool Timeout | 30 seconds | `config.py` line 9 |
| Cleanup Interval | 5 minutes | `config.py` line 11 |
| Token Savings | **~90%** | 65k → 5.5k per request |

---

## Design Decisions

### Why Polling Instead of WebSockets?

| Aspect | Polling Bridge | WebSocket |
|--------|----------------|-----------|
| Roblox compatibility | ✓ Works | ✗ Not supported |
| Latency | ~100ms intervals | Real-time |
| Implementation | Complex (event sync) | Simple |

**Verdict:** WebSocket would be ideal, but Roblox constraints require polling.

### Why Single Model Instead of Orchestrator + Worker?

| Aspect | Single Model | Multi-Model |
|--------|--------------|-------------|
| Latency | Lower (1 call) | Higher (2+ calls) |
| Cost | Lower | Higher |
| Complexity | Simpler | More complex |

**Verdict:** Modern models (Gemini Flash, Claude) handle both planning and execution well. Tool system provides specialization without overhead.

### Why Continuous Execution Instead of Step-by-Step?

| Aspect | Step-by-Step | Continuous |
|--------|--------------|------------|
| User clicks | Many | One |
| UX friction | High | Low |
| Context usage | Lower | Higher |

**Verdict:** Continuous execution matches user mental model ("do this task") and reduces interaction overhead.

---

## Future Roadmap

### Potential Enhancements
- **Streaming Responses**: Progressive action display as LLM generates
- **Multi-File Operations**: Coordinated changes with rollback capability
- **Learning from Corrections**: Track user edits to improve future suggestions
- **Collaborative Features**: Multiple users in same session

### Scalability Roadmap
```
CURRENT
├── Single backend instance
├── In-memory sessions
└── Direct LLM calls

PHASE 2
├── Redis session store
├── Multiple backend instances
└── Load balancer

PHASE 3
├── Distributed caching
├── LLM response caching
└── Geographic distribution
```

---

## Contributing

This is a solo project, but feedback is welcome!

1. Open an issue for bugs or feature requests
2. Include Roblox Studio version and LLM model used
3. Provide example prompts that failed

---

## License

MIT License - See LICENSE file for details

---

## Links

- **Roblox Creator Store**: [Install Lux](https://create.roblox.com/store/asset/)
- **Technical Architecture**: [Full Documentation](./lux-architecture.md)
- **Author**: [Sergey Kudelin](https://sergeykudelin.com)
- **GitHub**: [github.com/Seryozh](https://github.com/Seryozh)
- **Interactive Demos**: [sergeykudelin.com/lux](https://sergeykudelin.com/lux)

---

**Built with:** Python • FastAPI • LangGraph • LangChain • OpenRouter • Railway

**Special thanks** to the 1,500+ developers using Lux in production.
