# Luxembourg v2: Two-Model Architecture with On-Demand Tools

## Overview

**The System:**
- **Model 1 (Orchestrator):** Light decision-maker with tools
- **Model 2 (Worker):** Does the actual work with tools
- **Game:** Source of truth (project map, files, metadata)

**Philosophy:** Don't send everything upfront. Models pull what they need via tools. Like Claude Code, but optimized for Roblox and split across 2 models for token efficiency.

**Inspired by:** Claude Code's architecture (single model + tools in a loop). We split into 2 models because users pay for tokens (BYOK) and fresh worker context = better output.

---

## Architecture

```
GAME (Roblox Studio Plugin)
  └─ Sends: Project map (names + types ONLY) + user request
     Cost: ~5k tokens (lightweight)

SERVER (FastAPI + LangGraph)
  │
  ├─→ MODEL 1 (Orchestrator)
  │     ├─ Receives: Project map (names only) + user request
  │     ├─ Tool: get_metadata(script_name) → returns exports/imports
  │     ├─ Tool: list_scripts_in_folder(folder) → returns names
  │     ├─ Pulls metadata ONLY for candidates it cares about
  │     ├─ Creates clear task for Model 2
  │     └─ Cost: ~5-7k tokens
  │
  ├─→ MODEL 2 (Worker)
  │     ├─ Receives: Clear task from Model 1
  │     ├─ Tool: get_full_script(name) → returns full code
  │     ├─ Pulls ONLY the files it needs to complete task
  │     ├─ Does the work
  │     ├─ Returns result
  │     └─ Cost: ~10-15k tokens
  │
  ├─ MODEL 1 validates: "Does it fit?"
  │     ├─ If yes → Implement
  │     └─ If no → Send fix task to fresh Model 2
  │     └─ Cost: ~1-2k tokens
  │
  └─ GAME implements changes
```

---

## Why On-Demand Tools (Not Upfront Data)

**Old approach (wasteful):**
```
Game sends: Project map + ALL metadata for 100 scripts
Cost: ~20k tokens
Model 1 uses: 3 scripts' metadata
Waste: ~17k tokens of irrelevant metadata
```

**New approach (efficient):**
```
Game sends: Project map (just names + types)
Cost: ~5k tokens
Model 1 calls: get_metadata("PlayerMovement.lua")
Model 1 calls: get_metadata("Humanoid.lua")
Cost: ~1k tokens (only what's needed)
Waste: ~0 tokens
```

**Savings: 70% on initial step**

---

## The Workflow (Example: "Add Double Jump")

### Step 1: Game Sends Lightweight Data

**Game sends:**
```json
{
  "user_request": "Add double jump",
  "project_map": [
    {"name": "PlayerMovement.lua", "type": "LocalScript", "parent": "Player"},
    {"name": "Humanoid.lua", "type": "ModuleScript", "parent": "ServerStorage"},
    {"name": "Input.lua", "type": "ModuleScript", "parent": "ServerStorage"},
    {"name": "EnemyAI.lua", "type": "Script", "parent": "ServerScriptService"},
    {"name": "UIManager.lua", "type": "LocalScript", "parent": "StarterGui"},
    // ... 95 more scripts (just names + types + parents)
  ]
}
```

**Token cost: ~5k tokens (just names, no metadata, no code)**

---

### Step 2: Model 1 Explores (On-Demand)

**Model 1 sees:**
```
User wants: "Add double jump"
I see 100 scripts in map. Names and locations only.

"PlayerMovement" sounds relevant to jumping.
"Humanoid" sounds relevant to character physics.
"Input" might handle key presses.

Let me check these.
```

**Model 1 calls tools:**
```python
get_metadata("PlayerMovement.lua")
→ {"exports": ["jump", "walk", "sprint"], "imports": ["Humanoid", "Input"]}

get_metadata("Humanoid.lua")
→ {"exports": ["setVelocity", "applyForce"], "imports": ["Physics"]}
```

**Model 1 thinks:**
```
PlayerMovement exports "jump" ← definitely relevant
It imports Humanoid and Input ← I should understand these too
Humanoid sets velocity ← needed for jump physics

I have enough info to create a task.
I don't need to check all 100 scripts.
```

**Model 1 creates task for Model 2:**
```
TASK: Add double jump to the player movement system.

Context:
- PlayerMovement.lua handles jump (exports: jump, walk, sprint)
- It imports Humanoid (velocity) and Input (key presses)
- Humanoid exports: setVelocity, applyForce

Requirements:
- Detect second space press while in air
- Apply 1.5x jump velocity on double jump
- Add debounce to prevent spam
- Maintain landing reset logic
- Keep existing jump/walk/sprint working

Files to read: PlayerMovement.lua, Humanoid.lua
Files to modify: PlayerMovement.lua (likely)
New files: Possibly a new ServerScript for server-side validation
```

**Token cost: ~5-7k tokens total (map read + 2 metadata calls + task creation)**

---

### Step 3: Model 2 Executes (Fresh Context)

**Model 2 receives ONLY the task. Fresh context, no conversation history.**

**Model 2 thinks:**
```
Task says I need to read PlayerMovement.lua and Humanoid.lua.
Let me get them.
```

**Model 2 calls tools:**
```python
get_full_script("PlayerMovement.lua")
→ Returns full code (200 lines)

get_full_script("Humanoid.lua")
→ Returns full code (100 lines)
```

**Model 2 reads code, sees:**
```
PlayerMovement uses Humanoid:setVelocity for jumping.
Input.onKeyPress detects space.
No debounce exists.
No double jump exists.

I also see it uses a RemoteEvent called "JumpValidation".
Let me check that.
```

**Model 2 calls tool:**
```python
get_full_script("JumpValidation.lua")
→ Returns server-side validation script
```

**Model 2 now has full picture of the jump system.**

**Model 2 generates:**
```lua
-- Modified PlayerMovement.lua
local Humanoid = require(game:GetService("ServerStorage").Humanoid)
local Input = require(game:GetService("ServerStorage").Input)

local jumpCount = 0
local maxJumps = 2
local isGrounded = true
local debounceTime = 0.2
local lastJumpTime = 0

function jump()
    local now = tick()
    if now - lastJumpTime < debounceTime then return end

    if isGrounded then
        jumpCount = 0
    end

    if jumpCount < maxJumps then
        jumpCount = jumpCount + 1
        lastJumpTime = now

        local power = jumpCount == 1 and 50 or 75
        Humanoid:setVelocity(Vector3.new(0, power, 0))
        isGrounded = false
    end
end

function onLand()
    isGrounded = true
    jumpCount = 0
end

Input.onKeyPress("Space", jump)
Humanoid.onLand(onLand)
```

**Model 2 returns:**
```
RESULT:
  Modified: PlayerMovement.lua [code above]
  Unchanged: Humanoid.lua (compatible, no changes needed)
  Unchanged: JumpValidation.lua (server validation still works)

  Notes:
  - Added maxJumps variable (easy to change to triple jump later)
  - Added debounce (0.2s between jumps)
  - Second jump is 1.5x power (75 vs 50)
  - Landing resets jump count
```

**Token cost: ~10-15k tokens (task read + 3 file reads + generation)**

---

### Step 4: Model 1 Validates

**Model 1 receives result from Model 2.**

**Model 1 checks:**
```
My task was: Add double jump with debounce
Result includes:
  ✓ Double jump logic (jumpCount, maxJumps)
  ✓ Debounce (0.2s cooldown)
  ✓ Landing reset
  ✓ Existing functionality preserved
  ✓ Clean code, readable
  ✓ Uses correct APIs (Humanoid:setVelocity)

Does it fit? YES → Implement
```

**Token cost: ~1-2k tokens**

---

### Step 5: Game Implements

**Server sends to plugin:**
```json
{
  "action": "implement",
  "changes": [
    {
      "script": "PlayerMovement.lua",
      "action": "replace",
      "code": "... [new code] ..."
    }
  ],
  "message": "Double jump added! Press space twice to double jump. Second jump is 1.5x power.",
  "metadata_update": {
    "PlayerMovement.lua": {
      "exports": ["jump", "walk", "sprint"],
      "imports": ["Humanoid", "Input"],
      "handles": ["double-jump", "debounce"]
    }
  }
}
```

**Plugin writes code, updates metadata attribute, shows message to user.**

---

## Token Cost Breakdown (Updated with On-Demand Tools)

| Step | Model | Action | Tokens | Notes |
|------|-------|--------|--------|-------|
| 1 | Game | Send project map (names only) | 5k | Lightweight, no metadata |
| 2 | Model 1 | Read map | 1k | Just names |
| 3 | Model 1 | Call get_metadata() × 2 | 1k | On-demand, only candidates |
| 4 | Model 1 | Create task | 1-2k | Clear instructions |
| 5 | Model 2 | Read task | 1k | |
| 6 | Model 2 | Call get_full_script() × 3 | 3-5k | Only needed files |
| 7 | Model 2 | Generate code | 5-8k | Modified scripts |
| 8 | Model 1 | Validate result | 1-2k | Quick check |
| **TOTAL** | | | **18-25k** | **Per request** |

**vs. Old approach: 33-39k per request**
**Savings: ~35-40%**

---

## Follow-Up Messages

### Message 2: "Make the jump higher" (Same Topic)

```
Model 1: "We just did double jump. User wants it higher."
Model 1: Doesn't need to re-read map or metadata.
  Already knows: PlayerMovement handles jump.

Task: "Increase jump velocity. First jump: 50→65, double jump: 75→95"

Model 2:
  get_full_script("PlayerMovement.lua") → reads fresh copy
  Changes 2 variables
  Returns

Model 1: Validates → Implement

Tokens: ~8-10k
```

### Message 3: "Now add UI health bar" (Topic Switch)

```
Model 1: "Different topic. Let me check map."
Model 1: Reads project map names.
  "I see UIManager.lua in StarterGui"
  get_metadata("UIManager.lua") → {"exports": ["showMenu", "hideMenu"]}
  "No health bar yet. Need new system."

Task: "Create health bar UI. Check UIManager for patterns."

Model 2:
  get_full_script("UIManager.lua") → reads existing UI code
  Creates new HealthBar script
  Returns both

Model 1: Validates → Implement

Tokens: ~13-15k
```

### Message 4: "Make it triple jump" (Back to Jump Topic)

```
Model 1: "We did jump before. Let me re-read to verify."
  get_metadata("PlayerMovement.lua") → handles: ["double-jump"]
  "Yep, has double jump. Just needs maxJumps = 3"

Task: "Change maxJumps from 2 to 3 in PlayerMovement.lua"

Model 2:
  get_full_script("PlayerMovement.lua") → reads fresh
  Changes 1 variable
  Returns

Model 1: Validates → Implement

Tokens: ~6-8k
```

---

## Token Budget for Full Chat (Updated)

```
Message 1: "Add double jump"          → 22k tokens
Message 2: "Make it higher"           → 9k tokens
Message 3: "Triple jump"              → 7k tokens
Message 4: "Add UI health"            → 14k tokens
Message 5: "Make health bar red"      → 5k tokens
Message 6: "Add enemy AI"             → 18k tokens
Message 7: "Enemy shoots"             → 8k tokens
Message 8: "Add sound effects"        → 13k tokens
Message 9: "Tweak volume"             → 4k tokens
Message 10: "Add main menu"           → 15k tokens

Total: ~115k tokens
Budget: 200k tokens
Remaining: 85k tokens

Can do ~8 more messages (18 total per chat)
```

**vs. Old approach: 133k for 10 messages, ~12-15 total per chat**
**Improvement: 18 messages per chat (vs 12-15)**

---

## Error Handling

**If Model 2 produces bad code:**

```
Model 1 checks: "Does this work?"
Result: NO (missing debounce)

Model 1 sends fix task to FRESH Model 2:
  "Previous attempt missed debounce.
   Add debounce with 0.2s cooldown.
   Here's the code to fix: [code]"

Fresh Model 2: Fixes, returns
Model 1: Re-validates

Loop cost: ~5k tokens per fix iteration
Usually 1 fix needed, rarely 2+
```

---

## Comparison: Approaches

| Approach | Tokens/Message | Latency | Complexity |
|----------|----------------|---------|------------|
| **2-Model + On-Demand Tools** | **10-18k** | **Fast** | **Low** |
| 2-Model + All Metadata Upfront | 15-25k | Fast | Low |
| 3-Model (Verify) | 20-35k | Slow | High |
| Single Model + All Context | 25-40k | Medium | Medium |

**Winner: 2-Model + On-Demand Tools**

---

## Available Tools

### Model 1's Tools (Lightweight)
```python
get_metadata(script_name: str) → dict
  # Returns: exports, imports, handles
  # Cost: ~200 tokens per call

list_scripts_in_folder(folder: str) → list
  # Returns: script names in folder
  # Cost: ~100 tokens per call
```

### Model 2's Tools (Full Access)
```python
get_full_script(script_name: str) → str
  # Returns: Full script code
  # Cost: ~500-2000 tokens per call (depends on script size)

write_script(script_name: str, code: str) → dict
  # Writes code to project
  # Cost: ~100 tokens

create_instance(parent: str, class_name: str, properties: dict) → dict
  # Creates new instance in game
  # Cost: ~100 tokens
```

---

## Session Management

### Per Chat Session
```
Message 1: ~22k tokens (cold start, initial exploration)
Messages 2-18: ~5-15k tokens each (reuse context)
Total for 18 messages: ~200k tokens (full budget)
```

### When to Start New Chat
```
Approaching 180k tokens:
  "Getting close to limit. Start fresh?"

Or user clicks: "New chat"
  Previous context summarized
  New session begins
```

### Context Compression (Alternative to New Chat)
```
At 170k tokens:
  Summarize conversation:
    "We built: double jump system, health bar UI, enemy AI"
    "Current state: [summary of changes]"

  Clear old messages
  Continue with summary as context

  Cost: ~5k tokens for summary
  Freed: ~100k tokens of old conversation
```

---

## Real-World Costs

### Per Request (BYOK via OpenRouter)
```
Gemini Flash (cheap):
  Input: $0.075 per 1M tokens
  Output: $0.30 per 1M tokens

  Per message (15k in, 5k out):
    Input: $0.001
    Output: $0.002
    Total: ~$0.003 per message

  Per chat (18 messages): ~$0.05
  Per month (300 chats): ~$15

Gemini Pro (better quality):
  Input: $1.25 per 1M tokens
  Output: $5.00 per 1M tokens

  Per message (15k in, 5k out):
    Input: $0.019
    Output: $0.025
    Total: ~$0.044 per message

  Per chat (18 messages): ~$0.80
  Per month (300 chats): ~$240

Claude Sonnet (high quality):
  Input: $3.00 per 1M tokens
  Output: $15.00 per 1M tokens

  Per message (15k in, 5k out):
    Input: $0.045
    Output: $0.075
    Total: ~$0.12 per message

  Per chat (18 messages): ~$2.16
  Per month (300 chats): ~$648
```

### Recommendation
```
Model 1 (Orchestrator): Use Gemini Flash (cheap, fast, light work)
Model 2 (Worker): Use Gemini Pro or Claude Sonnet (better quality for code)

Hybrid cost per message:
  Model 1 (Flash): $0.003
  Model 2 (Pro): $0.044
  Total: ~$0.05 per message

Per chat: ~$0.90
Per month: ~$270

Affordable for serious Roblox developers.
```

---

## Implementation Checklist

- [ ] Server receives project map (names only) from plugin
- [ ] Model 1 reads map, decides candidates
- [ ] Model 1 calls get_metadata() for candidates only
- [ ] Model 1 creates clear task for Model 2
- [ ] Model 2 receives task (fresh context)
- [ ] Model 2 calls get_full_script() for needed files
- [ ] Model 2 discovers dependencies in code, requests more if needed
- [ ] Model 2 generates code
- [ ] Model 1 validates result
- [ ] If invalid: Fresh Model 2 fixes
- [ ] If valid: Server sends changes to plugin
- [ ] Plugin implements changes + updates metadata
- [ ] Token tracking (warn at 180k, suggest new chat)
- [ ] Context compression option (summarize + continue)

---

**This is the final architecture. Simple, efficient, production-ready.**
