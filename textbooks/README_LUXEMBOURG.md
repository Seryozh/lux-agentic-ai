# Luxembourg: AI Agent for Roblox Studio

**An agentic AI assistant that lives inside Roblox Studio. Users type natural language requests like "add double jump" and the AI modifies their game directly.**

[View Full Technical Textbook](./TEXTBOOK_LUXEMBOURG.md)

---

## What Makes This Interesting

Luxembourg solves an architectural constraint that seems impossible:

**The Problem:**
- Roblox Studio plugins can only make **outbound HTTP requests**
- Plugins cannot receive incoming connections
- The AI runs on a remote server; the game data lives in Roblox Studio
- How does the server get game data if it can't push requests to the plugin?

**The Solution:**
Polling-based request/response bridge. The plugin continuously asks the server "do you need anything from me?" allowing the AI to orchestrate data requests without bidirectional communication.

---

## Core Features

✅ **Natural Language Game Modification** — "Add double jump", "Make the sky red", "Create a damage system"
✅ **Two-Model Architecture** — Cheap orchestrator (planning) + smart worker (execution)
✅ **Project-Aware AI** — AI understands your game structure through project map
✅ **Token-Efficient** — Three-level exploration: structure → metadata → full code
✅ **User Approval** — Each action shows approve/skip/deny buttons
✅ **BYOK (Bring Your Own Key)** — Users provide their own OpenRouter API key

---

## Architecture

```
Plugin (Lua)           Backend (Python)         LLM
    ↓                       ↓                     ↓
Scan Game    →    FastAPI Server      →    LangGraph Agent
Read Scripts ←    Session Manager      ←    OpenRouter API
Execute Actions    Polling Bridge
```

### The Polling Bridge

```lua
Plugin: "Need anything?" → Server: "Send me Movement script"
Plugin: [reads script] → Server: "Analyzing..."
Plugin: "Ready?" → Server: "Modify this script with double jump"
Plugin: [executes action] → Server: "Done!"
```

---

## Technical Highlights

### Two-Model Orchestration (LangGraph)

**Model 1: Orchestrator (Fast, Cheap)**
- Sees: Full conversation history + project map
- Does: Plans what to explore, creates tasks
- Cost: ~$0.01 per request (Gemini Flash)

**Model 2: Worker (Smart, Capable)**
- Sees: Fresh context + specific task only
- Does: Reads code, generates modifications
- Cost: ~$0.05 per request (Claude/Gemini Pro)

This splits costs: cheap model handles 90% of requests, expensive model only for complex code generation.

### Session Management

```python
# In-memory sessions store:
- Conversation history
- Project map
- Cached scripts
- Pending requests (what AI is asking for)
- Response events (for async coordination)
```

When the AI needs data:
1. Creates pending request
2. Plugin polls and sees the request
3. Plugin reads the data (script content, metadata)
4. Plugin sends response
5. AI wakes up and continues

No WebSockets needed. Works within Roblox's constraints.

### The Action System

AI generates actions as JSON:

```json
{
  "type": "modify_script",
  "target": "game.StarterPlayer.StarterCharacterScripts.Movement",
  "source": "-- modified script with double jump --"
}
```

Other action types:
- `set_property` — Change instance properties
- `create_instance` — Create new parts/models
- `create_script` — Add new scripts
- `delete_instance` — Remove objects
- `move_instance` — Reparent instances

---

## Project Map (The AI's View of Your Game)

Instead of sending all script code upfront (expensive), the AI first sees a lightweight project map:

```
Game
  Workspace
    SpawnLocation
    Baseplate (Part)
    Enemy (Model)
      EnemyAI (Script)
  ServerScriptService
    GameManager (Script)
  StarterPlayer
    StarterCharacterScripts
      Movement (LocalScript)
```

The AI uses this to intelligently request only the scripts it needs. Token-efficient.

---

## How It Works: Full Flow

### User: "Add double jump"

1. **Plugin scans game** → Builds project map
2. **Plugin sends request** → Backend receives message + map
3. **Orchestrator thinks** → "I need to see the Movement script"
4. **Plugin polls** → Sees request for Movement metadata
5. **Plugin responds** → Sends ~100 word description of script
6. **Orchestrator plans** → Creates task for worker
7. **Worker executes** → Reads full Movement script code
8. **Worker generates** → Modifies script with double jump logic
9. **Backend returns** → Actions to execute
10. **Plugin shows approval UI** → "1 action proposed: Modify Movement script"
11. **User clicks Apply** → Plugin executes the action
12. **Done** → Game now has double jump

---

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| **Plugin** | Lua (Roblox) | Only option for Roblox Studio |
| **Backend** | Python + FastAPI | Fast, async-friendly, great for AI |
| **Agent** | LangGraph | Structured multi-step AI orchestration |
| **LLM** | OpenRouter | Multi-model support, cost optimized |
| **Deployment** | Railway/Heroku | Simple Python deployment |

---

## Development

### Local Setup

```bash
# Backend
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000

# Plugin (Rojo)
cd plugin
rojo build -o Luxembourg.rbxmx
# Install .rbxmx in Roblox plugins folder
```

### Key Files

- `backend/main.py` — FastAPI endpoints
- `backend/agent.py` — LangGraph orchestrator + worker
- `backend/session.py` — Polling bridge + session management
- `backend/tools.py` — Agent tools (get_metadata, get_full_script)
- `plugin/Main.server.lua` — UI, polling, action execution
- `plugin/ProjectMap.lua` — Game tree scanner
- `plugin/Backend.lua` — HTTP communication

---

## Debugging

### Backend Logs

```
21:04:25 [INFO] ORCHESTRATOR START
21:04:25 [INFO] User message: add double jump
21:04:26 [INFO] ORCHESTRATOR tool call: get_metadata('Movement')
21:04:29 [INFO] ORCHESTRATOR → worker task: Add double jump...
21:04:30 [INFO] WORKER START
21:04:35 [INFO] WORKER result: {"actions": [...]}
```

### Plugin Debug Messages

Look for gray text in the chat:
- "Scanning project..."
- "Sending to AI..."
- "Reading script: Movement"
- "2 actions proposed:"

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| "HTTP error: ConnectFail" | Backend not running | Start backend server |
| "Script not found" | Wrong path in response | Check script naming |
| "JSON parse failed" | Model returned malformed JSON | Retry (has fallback) |

---

## Why This Matters

Most AI tools for game development require manual back-and-forth: "what scripts do you need?" This system automatically discovers what it needs through intelligent exploration.

The polling bridge pattern is generally applicable to any one-way communication channel. Could be applied to other constrained environments (embedded systems, isolated networks, etc.).

---

## Future Improvements

- **Streaming responses** — Show AI thinking in real-time
- **Undo system** — Revert changes
- **Multi-file diffs** — Preview changes before applying
- **Model selection** — Let users choose preferred LLM
- **Context persistence** — Remember across Studio sessions
- **Team collaboration** — Shared sessions

---

## References

- [Full Technical Textbook](./TEXTBOOK_LUXEMBOURG.md) — 1200+ lines deep dive
- [Roblox Studio API Docs](https://developer.roblox.com/)
- [LangGraph Documentation](https://python.langchain.com/docs/langgraph)
- [OpenRouter API](https://openrouter.ai)

---

**Status:** Complete, production-ready code
**Demo:** Available upon request
**GitHub:** [Link to repo]
