# Lux

> **Agentic AI coding assistant for Roblox Studio**

Lux is a production-ready AI plugin that reads your Roblox project, understands your architecture, and makes code changes through natural conversation. Unlike traditional AI chatbots, Lux operates directly inside Studio with full awareness of your scripts, instances, and structure..

![Lux in Studio](https://devforum-uploads.s3.dualstack.us-east-2.amazonaws.com/uploads/original/5X/a/w/b/v/awBvu9IddL4clqNS2jxJInvmxK.jpeg)

## Features

### Agentic Architecture
- **Multi-step planning** - Breaks complex tasks into autonomous steps
- **Context-aware** - Understands your existing code before making changes
- **Self-correcting** - Verifies results and fixes its own mistakes
- **Tool calling loop** - Up to 50 iterations per request with full transparency

### Safety & Reliability
- **Self-healing** - Auto-retries transient failures with exponential backoff
- **Zero context loss** - Multi-strategy compression preserves conversation history
- **Human-in-the-loop** - Every destructive action requires explicit approval
- **Undo support** - Full integration with Studio's ChangeHistoryService

### Intelligence Modules
- **Task Planner** - Complexity-aware planning with self-reflection
- **Context Selector** - Relevance scoring to reduce token waste
- **Error Analyzer** - Classifies failures and suggests recovery strategies
- **Decision Memory** - Learns successful patterns across sessions

## Installation

### 1. Get OpenRouter API Key
Lux uses the BYOK (Bring Your Own Key) model for transparency and cost control.

1. Visit [openrouter.ai](https://openrouter.ai) and sign up
2. Navigate to [Keys](https://openrouter.ai/keys)
3. Create a new API key

### 2. Install Plugin
Download from the [Roblox Creator Store](https://create.roblox.com/store/asset/131392966327387/Lux-AI-Agentic-Lua-Coding-Assistant)

### 3. Configure
1. Click the Lux button in Studio
2. Paste your API key when prompted
3. Wait for project scan
4. Start building

## Usage

### Basic Examples

**Add a feature:**
```
You: "Add double jump to my character controller"
```

**Debug an issue:**
```
You: "Why isn't my DataStore saving?"
```

**Create UI:**
```
You: "Create a settings menu with volume slider and graphics dropdown"
```

**Refactor code:**
```
You: "Refactor my weapon system to use OOP"
```

### Approval Workflow

Every modification shows a preview:
- **Diff view** - Exact code changes
- **Approve** - Apply the change
- **Deny** - Skip and continue

Use <kbd>Ctrl</kbd>+<kbd>Z</kbd> to undo any approved action.

## Architecture

### Project Structure
```
Lux/
├── Main.lua                    # Plugin entry point
└── src/
    ├── OpenRouterClient.lua    # Core AI client with agentic loop
    ├── SystemPrompt.lua        # Base system instructions
    ├── ToolDefinitions.lua     # Tool schemas for AI
    ├── Tools.lua               # Tool implementations
    ├── Constants.lua           # Configuration
    │
    ├── Intelligence Modules
    ├── TaskPlanner.lua         # Multi-step task planning
    ├── ContextSelector.lua     # Relevance-based script filtering
    ├── ErrorAnalyzer.lua       # Failure classification
    ├── DecisionMemory.lua      # Pattern learning
    ├── Verification.lua        # Result validation
    │
    ├── Safety Modules
    ├── CircuitBreaker.lua      # Failure spiral prevention
    ├── OutputValidator.lua     # Hallucination detection
    ├── ErrorPredictor.lua      # Pre-flight checks
    ├── WorkingMemory.lua       # Context management
    ├── SessionManager.lua      # Lifecycle coordination
    │
    ├── Resilience Layer
    ├── ToolResilience.lua      # Auto-retry with health monitoring
    ├── CompressionFallback.lua # Multi-strategy context compression
    │
    └── UI/                     # Interface components
        ├── Builder.lua
        ├── ChatRenderer.lua
        ├── InputApproval.lua
        └── ...
```

### Agent Loop

```
User Request
    ↓
Task Planning (complexity analysis)
    ↓
Context Selection (relevance scoring)
    ↓
┌─────────────────────────────────┐
│ Agentic Loop (max 50 iterations)│
│                                  │
│  AI Thinks                       │
│    ↓                             │
│  Calls Tool (with resilience)    │
│    ↓                             │
│  [Approval Required?]            │
│    ↓ Yes → Wait for user         │
│    ↓ No  → Execute               │
│  Validates Output                │
│    ↓                             │
│  AI Reflects on Result           │
│    ↓                             │
│  [Task Complete?]                │
│    ↓ No  → Loop                  │
│    ↓ Yes → Exit                  │
└─────────────────────────────────┘
    ↓
Response to User
```

### Self-Healing System

**ToolResilience** wraps all tool execution:
- Retry transient failures (timeouts, rate limits) with exponential backoff
- Detect stale state (script modified since read)
- Validate output (prevent corrupted responses)
- Track health metrics (success/failure/recovery rates)

**CompressionFallback** prevents context loss:
1. Try AI summarization (best quality)
2. Fallback to structured truncation (extract key info)
3. Fallback to smart sampling (diverse message selection)
4. Final fallback to simple truncation (last N messages)

## Configuration

All behavior is configurable in `src/Constants.lua`:

```lua
-- Agent limits
Constants.MAX_AGENT_ITERATIONS = 50
Constants.COMPRESSION_THRESHOLD = 50000
Constants.MAX_SCRIPTS = 100

-- Intelligence modules
Constants.TASK_PLANNER = { enabled = true, complexity_threshold = 0.5 }
Constants.CONTEXT_SELECTOR = { enabled = true, relevance_threshold = 0.3 }
Constants.DECISION_MEMORY = { enabled = true, max_entries = 100 }

-- Safety systems
Constants.CIRCUIT_BREAKER = { failureThreshold = 5, cooldownPeriod = 30 }
Constants.OUTPUT_VALIDATOR = { checkPathExists = true, checkPlaceholders = true }
Constants.ERROR_PREDICTOR = { staleThresholdSeconds = 120 }

-- Resilience
Constants.RESILIENCE = {
    maxRetries = 2,
    retryBackoffMs = {100, 500, 1000},
    errorRateThreshold = 0.3,
    healthCheckEnabled = true
}
```

## Models

Lux supports Gemini 3 models via OpenRouter:

| Model | Speed | Intelligence | Cost (per 1M tokens) |
|-------|-------|--------------|---------------------|
| **Gemini 3 Flash** (default) | ⚡ Very Fast | 🧠 Good | $0.50 / $3.00 |
| **Gemini 3 Pro** | 🐌 Slow | 🧠🧠🧠 Excellent | $15 / $30 |

Switch models in Settings (⚙️) within the plugin.

## Pricing

The plugin is free. You pay OpenRouter directly:

| Task Type | Typical Cost | Time Saved |
|-----------|--------------|------------|
| Quick edit | $0.02 - $0.05 | 5-10 min |
| New feature | $0.10 - $0.25 | 30-60 min |
| Complex system | $0.25 - $0.50 | 1-2 hours |

## Privacy

- API key stored **locally** in Studio plugin settings
- Requests go **directly** to OpenRouter (no proxy servers)
- No analytics, tracking, or data collection
- Full source code available (this repository)

See [OpenRouter Privacy Policy](https://openrouter.ai/privacy) for their data handling.

## Development

### Running Locally

1. Clone this repository
2. Open Roblox Studio
3. Install as local plugin (Plugins folder)
4. Reload Studio

### Project Structure

See [Architecture](#architecture) section above.

### Contributing

Contributions welcome! Please open an issue or pull request.

## Changelog

### v4.0 - Self-Healing Release (2026-01-10)
- Auto-retry with exponential backoff
- State synchronization detection
- Zero context loss compression with multi-strategy fallback
- Health monitoring and metrics API
- Context reset confirmation dialog

## FAQ

**Q: Does it work on empty baseplates?**
A: Yes, Lux can scaffold projects from scratch.

**Q: What if it breaks something?**
A: Every change creates an undo point. Press <kbd>Ctrl</kbd>+<kbd>Z</kbd> to revert.

**Q: Can I use other AI models?**
A: Currently Gemini 3 Flash/Pro only. Model abstraction planned for future releases.

**Q: How does it compare to Roblox Assistant?**
A: Both are agentic AI assistants. Lux uses Gemini 3 models via OpenRouter with large context windows.

**Q: Why OpenRouter instead of direct API?**
A: Unified billing, transparent pricing, no vendor lock-in. You can add multiple model providers to your OpenRouter account.

## Support

- **Issues**: [GitHub Issues](https://github.com/skudeleenxyz/lux/issues)
- **DevForum**: [Lux Discussion Thread](https://devforum.roblox.com/t/lux-cursorclaude-code-but-for-roblox-free-plugin/4207506)
- **Documentation**: See this README and inline code comments

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

**Sergey Kudelin** - [GitHub](https://github.com/skudeleenxyz) • [DevForum](https://devforum.roblox.com/u/conquerfears)

## Acknowledgments

- Built with [OpenRouter](https://openrouter.ai) API aggregation
- Powered by [Google Gemini](https://deepmind.google/technologies/gemini/) models
- Inspired by [Cursor](https://cursor.sh) and [Claude Code](https://www.anthropic.com/claude)
- Community feedback from DevForum users

---

**[Download from Creator Store](https://create.roblox.com/store/asset/131392966327387/Lux-AI-Agentic-Lua-Coding-Assistant)** • **[DevForum Discussion](https://devforum.roblox.com/t/lux-cursorclaude-code-but-for-roblox-free-plugin/4207506)**
