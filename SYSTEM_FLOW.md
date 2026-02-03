# Complete System Flow: Plugin → Backend → LangGraph

This document traces one user through the entire system, request by request.

---

## The Three Layers

**Plugin** (Roblox Studio, Lua)
The user-facing layer. Provides the chat UI, reads the game's project tree, and applies code changes. The plugin is the source of truth — it has access to all game objects, scripts, instances, and properties. It can only make outbound HTTP requests (Roblox limitation — it cannot receive incoming calls from the backend).

**Backend** (Python, FastAPI)
The coordination layer. Receives requests from the plugin, holds session state in memory, and orchestrates the two AI models. Within a session, it remembers the project map, any scripts that have been loaded, and the full conversation history. This is what makes follow-up messages smarter and cheaper.

**LangGraph Agent** (Two Models via OpenRouter)

- **Model 1 (Orchestrator):** A cheap, fast model (e.g. Gemini Flash). Looks at the project map, decides what to explore further, creates tasks for Model 2, and validates results. Maintains conversation history across the session.

- **Model 2 (Worker):** A smart, capable model (e.g. Gemini Pro or Claude Sonnet). Receives a single focused task from Model 1 with fresh context (no conversation history). Reads the actual script code, generates the solution, and returns it. Fresh context each time means cleaner output.

---

## What Is the Project Map?

The project map is the Roblox game tree. It's literally just the hierarchy of everything in the game — names, types, and parent-child relationships. Nothing more.

Example of what the plugin sends:

```
Game
├── Workspace
│   ├── SpawnLocation (SpawnLocation)
│   ├── Baseplate (Part)
│   └── Enemy (Model)
│       └── EnemyAI (Script)
├── ServerStorage
│   ├── Humanoid (ModuleScript)
│   ├── Input (ModuleScript)
│   └── Physics (ModuleScript)
├── ReplicatedStorage
│   ├── JumpValidation (RemoteEvent)
│   └── PlayerHit (RemoteEvent)
├── StarterPlayer
│   └── StarterCharacterScripts
│       └── PlayerMovement (LocalScript)
├── StarterGui
│   └── UIManager (LocalScript)
└── ServerScriptService
    └── GameManager (Script)
```

This includes:
- Scripts (with their type: LocalScript, ModuleScript, Script)
- UI elements
- RemoteEvents and RemoteFunctions
- Models and BaseParts that contain scripts
- Anything relevant to understanding the project structure

What it does NOT include:
- Script source code
- Metadata or descriptions
- Imports, exports, or tags
- Any analysis of what scripts do

It's cheap to generate and cheap to send. The AI reads this tree and uses its own intelligence to figure out what's relevant — we don't pre-process or tag anything.

---

## Three Levels of Exploration

The AI explores the project in layers, going deeper only where it needs to. This is the core efficiency mechanism.

**Level 1: Project Map (always sent)**
The full game tree. Names, types, hierarchy. The AI sees everything that exists but knows nothing about what any script actually does. Cost: very low (~2-3k tokens for a 100-script project).

**Level 2: Script Metadata (requested on demand)**
When the AI spots scripts that look relevant by name or location, it asks the plugin for metadata about those specific scripts. Metadata is a ~100 word description of what the script does, what it depends on, and what it provides. The plugin generates this by reading the script and summarizing it (or reading stored attributes). Cost: ~200 tokens per script.

**Level 3: Full Script Code (requested on demand)**
When the AI needs to actually read or modify a script, it asks for the complete source code. This is the most expensive level but only happens for the few scripts that are directly relevant. Cost: ~500-2000 tokens per script depending on size.

The key insight: the AI drives this exploration. It looks at the map, uses its own judgment to identify candidates, requests metadata for those candidates, then requests full code for the ones it actually needs. We don't do keyword matching or tag filtering — the AI model is smart enough to do this itself.

Example of how this plays out:

```
AI sees project map
  → "PlayerMovement in StarterCharacterScripts — probably handles movement"
  → "Humanoid in ServerStorage — probably handles character physics"
  → "EnemyAI in Workspace.Enemy — probably not relevant to jumping"

AI requests metadata for PlayerMovement and Humanoid
  → PlayerMovement: "Handles player input and basic movement. Uses Humanoid
     module for physics. Currently supports walk and single jump."
  → Humanoid: "Character physics module. Provides velocity control,
     ground detection, and state management."

AI now understands the system well enough to create a task.
AI requests full code only for PlayerMovement (needs to modify it)
and Humanoid (needs to understand its API).
```

---

## How Tool Calls Reach the Plugin

The agent's tools (get_metadata, get_full_script, etc.) need data from the game. But the backend can't push requests to the plugin — Roblox only supports outbound HTTP.

The solution: the plugin continuously polls the backend. When the agent needs something, the backend stores that request. The plugin picks it up on its next poll, reads the data from the game, and sends it back.

```
Agent needs metadata for PlayerMovement.lua
  → Backend stores the request
  → Plugin polls: "Need anything?"
  → Backend: "Yes, send me metadata for PlayerMovement.lua"
  → Plugin reads the script, generates a summary
  → Plugin sends the metadata back
  → Backend passes it to the agent
  → Agent continues thinking
```

This adds a small delay per tool call (the polling interval, maybe 1-2 seconds), but it keeps things simple and works within Roblox's constraints.

---

## Request 1: "Add double jump"

### Step 1: Plugin sends the request

When the user first opens the plugin, it scans the game and builds the project map — just the tree structure. When the user types a message and hits send, the plugin sends the project map, the user's message, and their OpenRouter API key to the backend.

On follow-up messages, the plugin re-sends the project map (in case the game structure changed) but this is cheap since it's just names and hierarchy.

### Step 2: Backend creates a session

The backend receives the request. Since this is the first message, it creates a new session. The session stores:

- The project map
- An empty conversation history
- An empty collection of loaded scripts/metadata

This session lives in server memory for the duration of the chat.

### Step 3: Model 1 (Orchestrator) explores

Model 1 receives the project map and the user message: "Add double jump."

Model 1 reads the tree. It sees "PlayerMovement" as a LocalScript inside StarterCharacterScripts — that's almost certainly the movement handler. It sees "Humanoid" as a ModuleScript in ServerStorage — likely handles character physics. It sees "Input" nearby — probably handles key presses.

Model 1 doesn't know what any of these scripts actually do yet. It just sees names and locations. But based on its training and the naming conventions, it makes educated guesses about relevance.

Model 1 uses its tool: **get_metadata("PlayerMovement")**, **get_metadata("Humanoid")**

The backend relays these requests to the plugin via the polling mechanism. The plugin reads each script, generates a short description (~100 words), extracts the dependencies (require statements), and sends the metadata back.

Model 1 now sees:
- PlayerMovement handles basic movement and single jump, imports Humanoid and Input
- Humanoid provides velocity control and ground detection

Model 1 has enough context to create a clear task. It did NOT need to check all 100 objects in the tree — just the 2 that looked relevant. If the metadata had revealed unexpected dependencies (say PlayerMovement also imports a "Physics" module), Model 1 could request metadata for that too before proceeding.

### Step 4: Model 1 creates a task for Model 2

Model 1 writes a focused task describing:
- What the user wants (double jump)
- What exists (PlayerMovement handles jumping, uses Humanoid for velocity)
- What scripts to read (PlayerMovement, Humanoid)
- What needs to change (modify PlayerMovement to support double jump)
- Requirements (debounce, landing reset, second jump at higher power)

This task is everything Model 2 needs. It's a clear, self-contained work order.

### Step 5: Model 2 (Worker) executes

Model 2 receives **only** the task. No conversation history. No project map. Just the work order. This is intentional — fresh context produces cleaner code.

Model 2 uses its tool: **get_full_script("PlayerMovement")**, **get_full_script("Humanoid")**

The backend relays these to the plugin. The plugin sends back the complete source code.

Model 2 reads the actual code, understands the existing jump implementation, and generates the modified version with double jump support. It might also discover new dependencies in the code (like a RemoteEvent for server validation) and request those too.

Model 2 returns its result in a **structured JSON format**:
- Which files to modify and their new code
- Which new files to create (if any)
- A description of what changed
- Updated metadata for affected scripts

The structured format is critical — it ensures the response always parses correctly and the plugin knows exactly what to do with it.

### Step 6: Model 1 validates

Model 1 receives Model 2's output. Validation is not hardcoded regex or string matching — Model 1 is an AI model. It reads the generated code and checks:

- Does this actually implement double jump?
- Does it preserve existing movement functionality?
- Does it use the APIs correctly based on the metadata it already has?
- Is anything obviously broken or missing?

If Model 1 is satisfied: move to implementation.
If something is wrong: Model 1 creates a new task describing the fix needed and sends it to a fresh Model 2 instance. This retry rarely needs more than one iteration.

### Step 7: Backend returns response to plugin

The backend sends back a structured response containing:
- A message for the user
- Which scripts to modify (with their new complete source code)
- Which new scripts to create
- Updated metadata for affected scripts

The plugin receives this, writes the code into the actual game scripts, updates any stored metadata, and shows the user the result message.

### Step 8: Session updates

The backend adds this entire exchange to the session:
- The conversation history grows (user message + assistant response)
- The loaded scripts and metadata stay cached
- Model 1's context now includes this interaction for future reference

---

## Request 2: "I want triple instead"

### What's different

The session already exists. The backend already has the project map, the conversation history from Request 1, and the metadata + scripts that were loaded.

### Step 1: Plugin sends the request

Plugin re-sends the project map (cheap, in case it changed) along with the new message. Same session ID.

### Step 2: Model 1 analyzes with history

Model 1 now has conversation history. It sees:
- Previous: User asked for double jump, we added it to PlayerMovement
- Current: "I want triple instead"

Model 1 immediately understands the context. It doesn't need to re-explore the project map. It doesn't need to request metadata again. It already knows PlayerMovement handles jumping and that we just modified it.

Model 1 could request the latest metadata for PlayerMovement to confirm it was updated (the plugin re-generated metadata after the code change in Request 1). But for a simple follow-up like this, it likely skips that and goes straight to creating a task.

### Step 3: Model 2 gets a simpler task

Model 1 creates a focused task: "Change double jump to triple jump in PlayerMovement. Change maxJumps from 2 to 3. Add power scaling for the third jump."

Model 2 receives this with fresh context. It still calls **get_full_script("PlayerMovement")** — even though the backend has the script cached from Request 1. This is important: the script was MODIFIED by Request 1, so Model 2 needs to read the latest version from the game to see the current state of the code.

Model 2 makes the change and returns.

### Step 4: Same validation and response flow

Model 1 validates. Backend returns response. Plugin applies changes. Session history grows.

### Why this is cheaper

Request 1 cost ~18-25k tokens (full exploration, metadata requests, code generation).
Request 2 cost ~6-8k tokens (Model 1 already had context, task was simple, less exploration needed).

---

## Where Do Scripts Live? (Answering the "who has what" question)

This is important to understand clearly.

**The plugin** is the only thing that can actually read scripts from the game. Scripts live in Roblox Studio. The plugin has direct access to them.

**The backend** stores copies of scripts in session memory after the plugin sends them. These are snapshots — they might become stale if the user manually edits a script in Studio between messages.

**The agent** (Model 1 and Model 2) doesn't "have" scripts. It accesses them through tool calls, which go through the backend. If the backend already has a cached copy, it can serve it immediately. If not, the request goes to the plugin.

For follow-up messages within the same topic, the backend's cached copies are usually sufficient. But Model 2 always re-requests scripts from the plugin to ensure it has the latest version (since the previous request may have modified them).

```
Script lifecycle:

1. Script lives in Roblox Studio (source of truth)
2. Agent requests it via tool call
3. Backend checks: do I have it cached?
   → Yes: serve from cache (fast)
   → No: request from plugin via polling (slower)
4. Plugin reads from Studio, sends to backend
5. Backend caches it and passes to agent
6. Agent uses it for generation
7. After modification, plugin updates Studio
8. Cached copy in backend is now stale
9. Next request re-fetches from plugin
```

---

## Topic Switching

When the user switches topics (e.g., from jump system to health bar UI), Model 1 handles it naturally because it has the full conversation history AND the project map.

Model 1 sees: "We were working on jumping. Now user wants a health bar." It goes back to the project map, spots "UIManager" in StarterGui, requests metadata for it, and creates a fresh task for Model 2 focused entirely on UI.

Model 2 gets a clean task about health bars with no leftover jump code context. This separation is a key advantage of the two-model approach.

---

## Structured Output

All agent responses must be structured JSON so they parse reliably. This is not optional — if the output doesn't parse, the plugin can't apply changes.

Model 2's output format:

```
{
  "modified_scripts": {
    "ScriptName": "full new source code"
  },
  "created_scripts": {
    "NewScriptName": "full source code",
    "parent": "where to put it in the game tree"
  },
  "deleted_scripts": [],
  "description": "What was changed and why",
  "metadata_updates": {
    "ScriptName": "Updated description of what this script now does"
  }
}
```

This is enforced by the system prompt and the structured output capabilities of the AI models. If parsing fails, the backend asks Model 2 to retry with correct formatting.

---

## Session Lifecycle

```
User opens plugin
  → Plugin scans game tree, builds project map

User sends first message
  → Backend creates session (stores map, empty history)
  → Model 1 explores map → requests metadata → creates task
  → Model 2 reads scripts → generates code → returns
  → Model 1 validates → backend returns to plugin
  → Session stores: conversation history + loaded metadata/scripts

User sends follow-up (same topic)
  → Backend reuses session
  → Model 1 has conversation history (understands context)
  → Exploration is minimal (already knows what's relevant)
  → Cheaper and faster

User sends follow-up (new topic)
  → Model 1 re-explores project map for new topic
  → Requests new metadata, creates new task
  → Slightly more expensive but still has conversation context

User approaches token limit (~170k of 200k)
  → Backend can compress: summarize conversation history
  → Or suggest starting a new chat

User closes plugin / starts new chat
  → Session deleted from memory
  → Everything starts fresh
```

---

## Summary

| Component | Role | Remembers across messages? |
|-----------|------|---------------------------|
| **Plugin** | Source of truth. Sends project map, responds to script/metadata requests, applies code changes. | No (re-scans each time) |
| **Backend** | Session manager. Stores project map, conversation history, cached scripts/metadata in memory. | Yes (within a session) |
| **Model 1** | Orchestrator. Reads project map, explores via metadata requests, creates tasks, validates results. | Yes (full conversation history) |
| **Model 2** | Worker. Receives focused task, reads scripts, generates code. | No (fresh context every time) |

