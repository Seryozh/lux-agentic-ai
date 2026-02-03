# Context Filtering: The Real Problem & Solution

You identified a REAL hole in the plan. Let me address it properly.

---

## The Problem You Identified

**Simple tag matching doesn't work:**

```
User: "I want enemies that chase the player"
Plugin tries tag matching: Find scripts with "enemy" tag
Result: EnemyAI.lua, EnemySpawner.lua

But what about:
- PhysicsEngine.lua (enemies need physics)
- PlayerDetection.lua (enemies need to see player)
- AnimationHandler.lua (enemies need animations)
- AIBehavior.lua (enemies need decision logic)

If we ONLY send the 2 tagged scripts, the AI might generate code that needs these other files but they're not available.
```

**You're right: We can't blindsight it.**

---

## Why This Matters

LangGraph needs to understand the WHOLE system to make good decisions:

```
User: "Add double jump"

If we send ONLY:
- PlayerMovement.lua (has jump)

LangGraph doesn't see:
- Humanoid.lua (controls character)
- Animation.lua (plays jump animation)
- Physics.lua (applies gravity)
- Input.lua (detects key press)

Result: AI generates code that doesn't know about these systems.
Broken code.
```

---

## The Real Solution: LangGraph Decides What It Needs

**Don't filter on plugin side. Filter on backend side.**

### The Better Flow

```
Step 1: Plugin scans project
  Reads all 100 scripts
  Creates lightweight metadata for EACH:
  {
    "name": "PlayerMovement.lua",
    "tags": ["jump", "movement"],
    "first_50_lines": "...",  // Just the summary, not full code
    "imports": ["Humanoid", "Input", "Physics"],
    "exports": ["jump", "walk"]
  }

Step 2: Plugin sends to backend
  NOT the full scripts
  ONLY the metadata summaries + imports/exports
  (This is small - maybe 50kb for 100 scripts)

Step 3: LangGraph reads metadata
  Understands: "Okay, here's the whole system"
  Reads user request: "Add double jump"

  Thinks:
  "I see PlayerMovement exists
   It imports Humanoid, Input, Physics
   It exports jump, walk functions

   To add double jump, I need to:
   1. Read full PlayerMovement.lua (to understand current jump)
   2. Read Humanoid.lua (to understand character state)
   3. Read Input.lua (to detect double tap)

   Let me REQUEST these from the plugin"

Step 4: Backend asks plugin for specific scripts
  Backend → Plugin: "Send me PlayerMovement.lua, Humanoid.lua, Input.lua"
  Plugin: "Here they are"
  Backend: "Now I have full context"

Step 5: LangGraph generates with full context
  Has metadata of entire system
  Has full code of relevant parts
  Generates code that knows what's available
```

---

## Why This Solves The Problem

### Old Way (Dumb Filtering)
```
Plugin: "User said 'jump', here's jump-tagged scripts"
LangGraph: Blind, doesn't know what else exists
Result: Misses dependencies
```

### New Way (Smart Filtering)
```
Plugin: "Here's metadata of ALL systems"
LangGraph: "I can see the full picture"
LangGraph: "I need these specific scripts"
Plugin: "Here they are"
LangGraph: Now has full context
Result: Better code
```

---

## What Gets Sent

### Plugin → Backend (First Call)

**Lightweight metadata (small, fast):**
```json
{
  "all_scripts": [
    {
      "name": "PlayerMovement.lua",
      "type": "LocalScript",
      "tags": ["jump", "movement", "input"],
      "size": 2500,
      "imports": ["Humanoid", "Input", "Physics"],
      "exports": ["jump", "walk", "sprint"],
      "first_100_chars": "local Humanoid = ...local Input = require..."
    },
    {
      "name": "Humanoid.lua",
      "type": "ModuleScript",
      "tags": ["movement", "health"],
      "size": 1200,
      "imports": ["Physics"],
      "exports": ["takeDamage", "setHealth"],
      "first_100_chars": "..."
    },
    // 98 more scripts like this
  ],
  "user_message": "Add double jump",
  "session_id": "abc123"
}
```

**Size:** ~100-200kb for a whole project (manageable)

### Backend → Plugin (Second Call, if needed)

**Request full scripts:**
```json
{
  "session_id": "abc123",
  "script_names_needed": [
    "PlayerMovement.lua",
    "Humanoid.lua",
    "Input.lua"
  ]
}
```

**Plugin responds with full scripts:**
```json
{
  "scripts": {
    "PlayerMovement.lua": "local Humanoid = ...\nfunction jump() ...",
    "Humanoid.lua": "...",
    "Input.lua": "..."
  }
}
```

---

## The Token Math

### Option A: Send Everything (Naive)
```
All 100 scripts full content: ~100k tokens
Per request: ~100k tokens used
Cost: ~$1-2 per request
Too expensive
```

### Option B: Tag Filtering Only (Your Concern)
```
Send 5 tagged scripts: ~5k tokens
LangGraph is blind, misses dependencies
Result: Bad code
```

### Option C: Smart Two-Stage (THE ANSWER)
```
Stage 1: Send metadata for all (~10k tokens, cheap)
  LangGraph reads and understands system

Stage 2: LangGraph requests specific scripts (~5k tokens, focused)
  LangGraph knows exactly what to ask for
  Avoids blind spots

Total: ~15k tokens, better quality
Cost: Cheap + Smart
```

---

## How LangGraph Decides What To Request

LangGraph reads metadata and uses logic:

```python
def decide_what_to_request(metadata, user_request):
    """LangGraph decides what full scripts it needs"""

    # Parse user request
    if "double jump" in user_request.lower():
        keywords = ["jump", "movement", "input"]

    # Find matching scripts
    matching = []
    for script in metadata:
        if any(tag in script["tags"] for tag in keywords):
            matching.append(script)

    # Add dependencies
    dependencies = set()
    for script in matching:
        dependencies.update(script["imports"])

    # Get the scripts that match the dependencies
    for dep in dependencies:
        for script in metadata:
            if script["name"] == dep:
                matching.append(script)

    # Remove duplicates
    matching = list({s["name"] for s in matching})

    # Request these from plugin
    return matching
```

**This is smart because:**
1. Matches on keywords + tags
2. Follows dependency graph automatically
3. Doesn't blindly filter
4. Requests WHAT IT NEEDS, not what we guess

---

## Conversation History Integration

**You're right: Conversation history matters.**

```
User (Message 1): "Add jump system"
  LangGraph context: "User wants jump"
  Requests: [PlayerMovement, Input, Physics]

User (Message 2): "Now make double jump"
  LangGraph context: Remembers Message 1
  Knows: Jump system exists
  Requests: [PlayerMovement, Input, Animation]
  (Doesn't re-request everything)

User (Message 3): "Make it look cool with animations"
  LangGraph context: Remembers Messages 1-2
  Knows: Jump + double jump exist
  Requests: [Animation, VFX]
  (Focuses on the new ask)
```

**LangGraph has conversation history built-in.** It remembers what happened.

---

## What If LangGraph Needs Everything?

**Sometimes it will. That's okay.**

```
User: "Optimize my whole game"
LangGraph thinks: "I need to see everything to optimize"
LangGraph requests: All 100 scripts
Backend: "Okay, here they are"

vs.

User: "Add double jump"
LangGraph thinks: "I just need movement + input"
LangGraph requests: 3 scripts
Backend: "Here they are"
```

**LangGraph asks for what it needs. Trust it.**

---

## The Algorithm (Simplified)

```
1. Plugin sends metadata for all scripts
2. Backend receives metadata + user message
3. LangGraph THINKS:
   - What does user want?
   - What scripts are relevant?
   - What do those depend on?
   - What might I need?
4. LangGraph REQUESTS specific scripts from backend
5. Backend asks plugin for those scripts
6. Plugin sends full scripts
7. LangGraph GENERATES with full context
8. Done
```

---

## This Solves Your Concerns

**"We can't blindsight it"**
✅ We don't. LangGraph sees metadata for everything, decides what to read fully.

**"What if it needs the whole map?"**
✅ It can request everything. We let it decide.

**"Tag matching is dumb"**
✅ We don't rely on it. LangGraph uses tags + dependencies + context.

**"Conversation history"**
✅ LangGraph tracks it automatically.

**"An AI model deciding relevance"**
✅ LangGraph IS that model. It's smarter than a separate filter.

---

## For MVP Implementation

```python
# Backend receives call from plugin
@app.post("/chat")
def chat(request):
    # Step 1: Receive metadata (all scripts)
    all_metadata = request.metadata

    # Step 2: LangGraph thinks about what it needs
    agent = LangGraphAgent(api_key, all_metadata)

    # Step 3: Agent might ask for more
    # Inside LangGraph loop:
    #   "I need PlayerMovement.lua, send it"
    # Backend calls tool:
    #   tool_RequestScript("PlayerMovement.lua")
    # Plugin returns full script

    # Step 4: Agent generates with full context
    result = agent.run(request.user_message)

    return result
```

**Key:** Plugin provides metadata for all scripts upfront. Backend/LangGraph requests specifics as needed.

---

## The Real Architecture (Corrected)

```
Plugin (Lua)
  ├─ Scans all scripts
  ├─ Sends metadata for all 100 scripts (lightweight)
  └─ Listens for requests: "Send me these 3 scripts"

Backend (Python)
  ├─ Receives metadata
  ├─ LangGraph reads metadata (understands system)
  ├─ LangGraph decides: "I need PlayerMovement.lua, Humanoid.lua"
  ├─ Backend requests those from plugin
  ├─ Plugin sends them
  ├─ LangGraph generates with full context
  └─ Returns result

LangGraph (The Brain)
  ├─ Sees ALL metadata
  ├─ Understands dependencies
  ├─ Requests what it needs
  ├─ Generates smart code
  └─ Never blindsighted
```

---

## Summary

**You were right about the hole. This fixes it.**

Instead of:
- Plugin guessing what's relevant ❌

We do:
- Plugin provides full picture (metadata) ✅
- LangGraph sees full picture ✅
- LangGraph decides what to read fully ✅
- LangGraph generates with full context ✅

**This is the right approach.**
