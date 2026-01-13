<div align="center">

![|690x169](upload://jW2bY0LNvRKFzcLMPD3LzYoE43e.jpeg)

# Lux - The AI Coding Assistant That Actually Codes For You

### **Stop copy-pasting. Stop debugging AI suggestions. Start shipping.**</big>

Lux doesn't suggest code and leave you to figure out the rest. It **works inside your project**, reading your scripts, understanding your structure, making changes, and checking its own work.

You describe what you want. Lux does the rest.

# ➜ [Get Lux Free](https://create.roblox.com/store/asset/131392966327387/Lux-AI-Agentic-Lua-Coding-Assistant)

<sub>Add credits at openrouter.ai to get started</sub>

</div>

-----

## 🆕 What's New in v4.0 — Self-Healing Release

**v4.0** introduces a resilience layer that makes Lux significantly more reliable by automatically recovering from transient failures and preventing context loss.

### 🔄 Self-Healing Systems

- **Auto-Retry with Exponential Backoff** - Transient tool failures (timeouts, rate limits) now automatically retry up to 3 times with smart backoff (100ms → 500ms → 1000ms). **60-80% of failures recover invisibly** without user intervention.

- **State Synchronization Detection** - Detects when scripts are modified after being read and suggests re-reading before edits. Prevents "search content not found" errors from stale context.

- **Zero Context Loss Compression** - Multi-strategy fallback system (AI Summary → Structured Truncation → Smart Sampling → Simple Truncation) ensures **you never lose conversation context** even when AI summarization fails. Structured truncation extracts and preserves user requests, AI actions, tool usage, and errors.

- **Health Monitoring** - Tracks success/failure rates, auto-recovery statistics, and per-tool performance in real-time. Warning system activates at 30% error rate.

- **Enhanced Error Messages** - Stale context errors now include actionable guidance ("This script was modified 65 seconds ago. Use get_script to refresh.") instead of cryptic failures.

### 🛡️ UX Safety Improvements

- **Context Reset Confirmation** - Destructive actions like resetting conversation now show a professional confirmation dialog to prevent accidental data loss.

### 📊 What This Means For You

| Problem | v4.0 Solution |
|:--------|:--------------|
| Tool timeouts waste your time | Auto-retry recovers 60-80% invisibly |
| "Previous context lost" messages | Zero-loss compression preserves everything |
| Cryptic "not found" errors | Actionable suggestions with context freshness |
| No visibility into system health | Real-time success/recovery rate tracking |
| Accidental conversation resets | Confirmation dialog prevents mistakes |

### ⚡ Performance Impact

**Before v4.0:**
- Tool failure → Immediate error shown to user
- Compression failure → "Context lost" message
- Stale state → Generic error, no recovery path
- User sees ~15% unnecessary error messages

**After v4.0:**
- Tool failure → Auto-retry → Success (invisible to user)
- Compression failure → Structured fallback → No data loss
- Stale state → Detected with suggestion to re-read
- Error rate reduced by ~40% through automatic recovery

[details="🔧 v2.0.4: TaskPlanner Crash Fix"]
**v2.0.4** fixed a crash that caused the plugin to get stuck in "thinking" mode. Messages containing words like "should", "must", or "needs to" were causing the intent parser to crash. Thanks **@winpo1** for the detailed report!
[/details]

[details="🛡️ Anti-Destructive Intelligence (v2.0.3)"]

Prevents AI from deleting your manual code additions:

- **Mandatory Freshness Checks** - AI must re-read scripts before ANY edit. Blocks edits if script was modified since last read.
- **Strongly Prefer Surgical Edits** - Changed threshold from >90% to >95% for full rewrites. Surgical `patch_script` preserves your additions.
- **Deletion Preview Warnings** - When removing >10 lines, shows sample of what's being deleted before you approve.
- **Change Impact Analysis** - Encourages checking script dependencies before making changes.
- **Document Manual Fixes** - AI remembers your manual additions so they don't get deleted in future edits.

### UX Bug Fixes

- **Fixed misleading "$1 free credit" text** - OpenRouter doesn't auto-give credits. Now shows clear setup instructions.
- **Fixed Enter key crash** - Pressing Enter in API key field no longer throws error.

Thanks to @sergerold and @BanguelaDev for the feedback!

[/details]

[details="🛡️ New Safety Systems (v2.0.0)"]

- **Circuit Breaker** - Hard safety boundary that prevents failure spirals. After 5 consecutive failures, Lux pauses and asks for your guidance instead of wasting iterations.

- **Output Validator** - Catches AI hallucinations *before* execution. Detects non-existent paths, placeholder code (TODO/FIXME), and syntax issues before they cause errors.

- **Error Predictor** - Pre-flight checks warn about potential problems. Detects stale script context (read too long ago) and suggests re-reading before edits.

- **Working Memory** - Tiered context management with relevance decay. Keeps important information hot while compressing old context efficiently.

- **Session Manager** - Coordinates all modules with proper lifecycle management. Ensures clean state between tasks and proper cleanup.

### 🔒 What This Means For You

| Problem | v2.0.0 Solution |
|:--------|:----------------|
| AI invents paths that don't exist | Output Validator catches hallucinations |
| Error loops waste API credits | Circuit Breaker halts at 5 failures |
| Uses stale script context | Error Predictor warns when context is old |
| Forgets what you asked for | Working Memory keeps goals persistent |
| State leaks between tasks | Session Manager ensures clean lifecycle |

### ⚙️ All Configurable

Every new safety system can be enabled/disabled and tuned in `Constants.lua`:

```lua
Constants.CIRCUIT_BREAKER = { failureThreshold = 5, cooldownPeriod = 30 }
Constants.OUTPUT_VALIDATOR = { checkPathExists = true, checkPlaceholders = true }
Constants.ERROR_PREDICTOR = { staleThresholdSeconds = 120 }
Constants.WORKING_MEMORY = { relevanceHalfLifeSeconds = 300 }
```

[/details]

-----

## ✦ The Problem With AI Coding Today

You've probably tried using AI to help you code in Roblox Studio. Here's how it usually goes:

1. You describe what you want
1. AI generates Lua code
1. You copy it into Studio
1. It doesn't work - wrong service, bad syntax, doesn't know what a RemoteEvent is
1. You go back and forth debugging
1. *Repeat 10 times*

**This is slow. This is frustrating. This shouldn't be how it works.**

-----

## ✦ How Lux Compares

There are three ways developers use AI for Roblox right now. Here's how this plugin stacks up:

> ### vs. ChatGPT / Claude / Gemini (Web)

Standalone AI chat sites don't know your project exists. You're constantly copy-pasting code in, explaining your structure, then copy-pasting suggestions back out. They hallucinate services, invent APIs that don't exist, and have no idea if their code actually works in your game.

**Lux reads your actual project.** It sees your scripts, understands your structure, and makes edits directly in Studio.

> ### vs. Cursor / Claude Code

These agentic coding tools are incredible for web development. But they don't work with Roblox Studio. You can't point Cursor at your Explorer and say "refactor my combat system." They don't understand Roblox services, Instance hierarchies, or how to create a ScreenGui.

**Lux is built specifically for Roblox Studio.** It speaks Roblox natively: DataStores, RemoteEvents, TweenService, all of it.

> ### vs. Other Roblox AI Plugins

Most Roblox AI plugins are glorified chatbots. They answer questions or generate code snippets, but you still do the integration work. They use older models, lack planning capabilities, and can't autonomously iterate on problems.

**Lux is agentic.** It plans multi-step tasks, executes them, verifies the results, and fixes its own mistakes. Powered by **Gemini 3 Pro** and **Gemini 3 Flash** with 65K token output and native reasoning.

-----

## ✦ What "Agentic" Actually Means

When you ask Lux to *"add a sprint system"*, it doesn't just spit out code. It **works**:

1. **Scans** your project to understand your structure
1. **Finds** your existing PlayerController (if you have one)
1. **Reads** the code to understand how you handle input
1. **Plans** the implementation
1. **Makes** the edits
1. **Verifies** the result
1. **Fixes** any issues
1. **Reports** back

**Up to 50 autonomous steps per request.** You watch and approve each change.

![Lux docked in Studio|690x318, 75%](upload://awBvu9IddL4clqNS2jxJInvmxK.jpeg)

-----

## ✦ Real Examples

> **You:** Add a double jump to my character controller
> 
> **Lux:** Found `PlayerController` in StarterPlayerScripts. I see you're using ContextActionService for input binding. I'll add double jump using the same pattern with a `canDoubleJump` flag that resets on landed.
> 
> *[Shows diff with 12 lines added to your existing script]*
> 
> Approve this change?

-----

> **You:** Create a settings menu with volume and graphics options
> 
> **Lux:** I'll create this in StarterGui. Planning: SettingsFrame → VolumeSlider, GraphicsDropdown, CloseButton. Then a LocalScript to handle the interactions and save to player data.
> 
> *[Shows ScreenGui hierarchy + LocalScript preview]*
> 
> Ready to create 2 instances. Approve?

-----

> **You:** Why is my DataStore not saving?
> 
> **Lux:** Reading your DataManager module… Found the issue on line 47. You're calling `SetAsync` inside a `PlayerRemoving` connection, but the player's already gone by execution time. I'll wrap it in a `pcall` and add `game:BindToClose()` for server shutdown. Want me to fix it?

-----

> **You:** Refactor my weapon system to use OOP
> 
> **Lux:** Found 4 related scripts: WeaponHandler, GunScript, MeleeScript, WeaponConfig. I'll create a base `Weapon` class in ReplicatedStorage, then `Gun` and `Melee` subclasses that inherit from it. Your existing configs will become constructor parameters.
> 
> *[Plans 6-step refactor with diffs for each]*

-----

<div align="center">

**Ready to try it?**

# ➜ [Get Lux Free](https://create.roblox.com/store/asset/131392966327387/Lux-AI-Agentic-Lua-Coding-Assistant)

<sub>Takes 2 minutes to set up</sub>

</div>

-----

## ✦ You Stay In Control

**Nothing happens without your approval.**

Every change Lux wants to make shows up for preview:

|Action       |What You See                 |
|:------------|:----------------------------|
|**Diff View**|Exactly what code will change|
|**Approve**  |Apply the change             |
|**Deny**     |Skip it                      |

Every approved action creates a Studio undo point. <kbd>Ctrl</kbd>+<kbd>Z</kbd> instantly reverts.

-----

## ✦ Setup (2 Minutes)

> ### Step 1: Get an API Key

1. Go to [openrouter.ai](https://openrouter.ai)
1. Sign up (you get **$1 free credits**)
1. Go to [openrouter.ai/keys](https://openrouter.ai/keys)
1. Create a new key

> ### Step 2: Install the Plugin

1. Get the plugin: **[Lux on Creator Store](https://create.roblox.com/store/asset/131392966327387/Lux-AI-Agentic-Lua-Coding-Assistant)**
1. Open Roblox Studio, click the Lux button
1. Paste your API key
1. Done. Start building.

-----

## ✦ Pricing

**The plugin is completely free.** You pay OpenRouter directly for AI usage. No markup, no subscription.

|Task Type                         |Cost         |Time Saved|
|:---------------------------------|:------------|:---------|
|Quick question / small edit       |~$0.02 - 0.05|5-10 min  |
|New feature (sprint, inventory)   |$0.10 - 0.25 |30-60 min |
|Complex system (combat, DataStore)|$0.25 - 0.50 |1-2 hours |
|Long building session             |$0.50+       |Half a day|

Your $1 free credit covers a lot of real work.

-----

## ✦ Privacy & Security

- API key stored **locally** in Studio plugin settings
- Requests go **directly** to OpenRouter → Google
- **No middleman servers** - I never see your code or conversations
- **No analytics, no tracking, no data collection**
- Full source visible in the plugin (not obfuscated)

-----

## ✦ FAQ

**Does it work on empty baseplates?**

> Yes. Lux can build from scratch.

**What if it breaks something?**

> Every change creates an undo point. <kbd>Ctrl</kbd>+<kbd>Z</kbd> fixes it instantly.

**Can I use other models?**

> Yes. Click ⚙️ Settings to choose between **Gemini 3 Flash** (fast, affordable) and **Gemini 3 Pro** (most capable).

**How does this compare to Roblox Assistant?**

> Both are agentic, but Lux runs on Gemini 3 Pro/Flash - frontier models from Google. It's far easier to adapt a top-tier foundation model for Roblox than to build one from scratch. You get state-of-the-art reasoning out of the box.

**Why OpenRouter instead of direct API?**

> $1 free credits for everyone to try. Transparent pricing. No lock-in.

-----

## ✦ Community Showcase

**Reply with what you've built using Lux and I'll feature it here!**

> ### 🎒 Inventory System with Item Placement — [@winpo1](https://devforum.roblox.com/t/lux-cursorclaude-code-but-for-roblox-free-plugin/4207506/13?u=conquerfears)
> Full inventory UI with grid layout, item preview panel, and 3D placement mechanic. Built from scratch in a few prompts.

-----

<div align="center">

# ➜ [Download Lux](https://create.roblox.com/store/asset/131392966327387/Lux-AI-Agentic-Lua-Coding-Assistant)

Free AI coding assistant plugin for Roblox Studio

Questions? Drop a reply.

</div>

-----

[details="🔄 v4.0: Self-Healing Release"]
A major reliability upgrade focused on automatic failure recovery and context preservation.

### Self-Healing Systems

**ToolResilience Layer:**
- Auto-retry with exponential backoff (100ms → 500ms → 1000ms)
- State synchronization detection (catches stale scripts)
- Output validation and sanitization (prevents corrupted responses)
- Health monitoring (tracks success/failure/recovery rates)
- Per-tool statistics with 20-call rolling window

**CompressionFallback System:**
- 4-tier fallback: AI Summary → Structured Truncation → Smart Sampling → Simple Truncation
- Structured truncation extracts: User requests (first 5), AI actions (first 5), Tool usage summary, Errors (first 3)
- Zero context loss guarantee (always preserves key information)

### UX Improvements

- **Context reset confirmation dialog** - Prevents accidental conversation clearing
- **Enhanced error messages** - Actionable suggestions for stale context and other issues
- **Seamless recovery** - 60-80% of transient failures recover invisibly

### Technical Details

**Integration:** Self-healing layer integrated into OpenRouterClient.lua at 5 strategic points (imports, tool execution, compression, session lifecycle, health API)

**Configuration:** All resilience settings configurable in Constants.lua:
```lua
RESILIENCE = {
    maxRetries = 2,
    retryBackoffMs = {100, 500, 1000},
    errorRateThreshold = 0.3,
    healthCheckEnabled = true
}
```

**Health Metrics API:**
```lua
local health = OpenRouterClient.getResilienceHealth()
print("Success Rate:", health.metrics.successRate * 100, "%")
print("Recovery Rate:", health.metrics.recoveryRate * 100, "%")
```
[/details]

[details="🔧 v2.0.4: TaskPlanner Crash Fix"]
Fixed a crash in `extractSuccessCriteria()` that occurred when user messages contained words like "should", "must", or "needs to". The `gmatch` pattern matching was returning unexpected values in edge cases, causing `table.insert` to fail. Rewrote to use explicit `string.find` with position tracking. Thanks @winpo1!
[/details]

[details="🛡️ v2.0.3: Anti-Destructive Intelligence"]
Prevents AI from deleting your manual code additions:

- **Mandatory Freshness Checks** - AI must re-read scripts before ANY edit
- **Strongly Prefer Surgical Edits** - Changed threshold from >90% to >95% for full rewrites
- **Deletion Preview Warnings** - When removing >10 lines, shows sample of what's being deleted
- **Change Impact Analysis** - Encourages checking script dependencies before making changes
- **Document Manual Fixes** - AI remembers your manual additions

Also fixed misleading "$1 free credit" text and Enter key crash in API key field. Thanks @sergerold and @BanguelaDev!
[/details]

[details="🔧 v2.0.2: Patch Script Fix"]
Fixed `patch_script` fuzzy matching that was broken when exact match failed. Also fixed field name mismatches in OutputValidator and ErrorPredictor.
[/details]

[details="🔧 v2.0.1: Hotfix"]
Replaced dynamic module loading pattern with static requires. Zero functional changes—Creator Store compliant.
[/details]

[details="🆕 Update v2.0.0: Safety & Resilience"]
A major release focused on reliability and error prevention.

### New Safety Systems

- **Circuit Breaker** - Halts after 5 consecutive failures, asks for guidance
- **Output Validator** - Catches hallucinated paths and placeholder code before execution
- **Error Predictor** - Pre-flight checks warn about stale context
- **Working Memory** - Tiered context with relevance decay
- **Session Manager** - Coordinated lifecycle management

### The Upgrade at a Glance

|Problem                 |v2.0.0 Solution                      |
|:-----------------------|:------------------------------------|
|AI invents paths        |Output Validator catches hallucinations|
|Error loops waste credits|Circuit Breaker halts at 5 failures  |
|Uses stale script context|Error Predictor warns when old       |
|Forgets your goals      |Working Memory keeps goals persistent|
|State leaks between tasks|Session Manager ensures clean state  |

All configurable in `Constants.lua`.
[/details]

[details="📂 v1.1.2: Agent Intelligence"]
A major internal evolution making Lux faster, cheaper, and more reliable.

### Smarter Reasoning & Efficiency

- **Task Planner** - Plans multi-step tasks before execution, self-reflecting to catch logic errors early
- **Smart Context** - Scores and selects only relevant scripts instead of token dumping (saves money)
- **Self-Healing** - Error Analyzer and Syntax Verification catch bracket mismatches and typos automatically
- **Decision Memory** - Remembers successful patterns and warns about previously failed approaches

### The Upgrade at a Glance

|Feature    |Before                      |After                           |
|:----------|:---------------------------|:-------------------------------|
|**Tokens** |Wasted on irrelevant scripts|Filtered by relevance (cheaper) |
|**Logic**  |One-size-fits-all           |Complexity-aware planning       |
|**Errors** |Repeated same mistakes      |Classifies & recovers from loops|
|**Scripts**|Assumed code worked         |Auto-verifies Lua syntax        |

### Polished Interface

- Dynamic auto-hiding status panel
- Fixed "thinking" text leaks
- Toggle any intelligence module via ⚙️ Settings
[/details]

[details="📂 v1.1.1 Legacy Notes"]

- **Model Selection:** Toggle between Gemini 3 Flash and Gemini 3 Pro
- **UI Polish:** Improved approval prompts, timestamps, animated thinking indicators
- **Smart Review:** "Review Code" buttons only appear when code is actually modified
- **Tooling:** Class-aware property parsing and improved error feedback
[/details]

[details="🔧 Full Technical Specs"]

### Agent Architecture

- Max iterations: 50 per request
- Context window: ~50K tokens before compression
- Compression preserves: Last 10 messages + summary
- Failure tracking: Circuit breaker at 5 consecutive failures

### Model Configuration

- Provider: OpenRouter
- Available Models:
  - `google/gemini-3-flash-preview` (Default) - Fast & affordable
  - `google/gemini-3-pro-preview` - Most capable
- Thinking: Enabled (low)
- Max output tokens: 65,536
- Temperature: 1.0

### Safety & Resilience Modules

**v4.0 Self-Healing:**
- **ToolResilience** - Auto-retry with exponential backoff, state sync detection, health monitoring
- **CompressionFallback** - Multi-strategy compression with zero context loss

**v2.0.0 Safety Systems:**
- **CircuitBreaker** - Hard stop on failure spirals
- **OutputValidator** - Pre-execution hallucination detection
- **ErrorPredictor** - Pre-flight context freshness checks
- **WorkingMemory** - Tiered context with relevance decay
- **SessionManager** - Lifecycle coordination

### Project Scanning

Indexed locations: ServerScriptService, ReplicatedStorage, ReplicatedFirst, StarterGui, StarterPlayer, ServerStorage

Limit: 100 scripts (for context efficiency)

### Project Memory

- Storage: StringValue in ReplicatedStorage
- Validation: On session start
- Anchors: `script_exists`, `script_contains`, `instance_exists`, `service_has_child`
- Stale threshold: 7 days

### Creator Store Compliance

- No `loadstring()`
- No dynamic code execution
- No `require(assetId)`
- No remote asset loading
- Read-only inspection via standard Roblox APIs
[/details]