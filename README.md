# Lux - Agentic AI for Roblox Studio

## What You're Building

An AI plugin for Roblox Studio that lets non-programmers build games through conversation.

**User says:** "Add a double jump system"
**Lux does:** Understands their project, generates code, implements it
**Result:** Working double jump in their game

---

## Architecture at a Glance

```
ROBLOX STUDIO PLUGIN (Lua)
    ↓ (HTTP)
BACKEND (Python + LangGraph + OpenRouter)
    ↓ (Tool calls)
OPENROUTER API (Claude, Gemini, etc.)
```

**Two-Model approach (optimized):**
- **Model 1 (Orchestrator):** Lightweight, decides what to do
- **Model 2 (Worker):** Powerful, does the actual work

See `SIMPLE_TWO_MODEL_APPROACH.md` for details.

---

## Files in This Project

### Architecture Docs (Read These First)
- **SIMPLE_TWO_MODEL_APPROACH.md** — Final architecture decision + token costs
- **CHALLENGES_AND_RISKS.md** — Real problems you'll hit during development
- **CONTEXT_FILTERING_EXPLAINED.md** — How to send only relevant context
- **INTELLIGENT_DEPENDENCY_RESOLUTION.md** — Smart script dependency tracking

### Implementation
- **IMPLEMENTATION_PLAN.md** — Step-by-step guide to build it (THIS IS YOUR ROADMAP)

---

## Quick Start

### 1. Understand the System (1-2 hours)
```bash
# Read in this order
1. This README.md
2. SIMPLE_TWO_MODEL_APPROACH.md (final architecture)
3. IMPLEMENTATION_PLAN.md (your roadmap)
```

### 2. Setup Environment (30 mins)
```bash
# Create backend environment
python3 -m venv venv
source venv/bin/activate  # Mac/Linux
# venv\Scripts\activate  # Windows

# Install dependencies (when ready)
pip install fastapi uvicorn langgraph langchain openrouter pydantic
```

### 3. Build Phase by Phase (See IMPLEMENTATION_PLAN.md)
```
Phase 1 (Days 1-2):  Plan + API design
Phase 2 (Days 3-5):  Backend implementation
Phase 3 (Days 6-8):  Plugin implementation
Phase 4 (Days 9-10): Integration testing
Phase 5 (Days 11-14): Polish + deploy
```

---

## Key Concepts

### Smart Context
Instead of sending your entire 100-script project to the AI:
- Plugin sends metadata (names, tags, imports/exports) for all scripts
- AI reads metadata, understands the system
- AI requests only the specific scripts it needs
- **Result:** Cheaper, faster, smarter decisions

### Agentic Loop
```
User: "Add double jump"
    ↓
AI thinks: "I need PlayerMovement and Humanoid scripts"
    ↓
AI reads those scripts
    ↓
AI generates code
    ↓
AI validates code
    ↓
AI implements changes
    ↓
User: "Perfect!"
```

### Two Models
- **Fast Model (Orchestrator):** Analyzes requests, decides what's needed
- **Smart Model (Worker):** Generates high-quality code
- **Cost Savings:** ~40% cheaper than single model, better quality

---

## Token Budget

**Per chat session (18 messages):**
- Gemini Flash + Pro: ~$0.90
- Claude Sonnet: ~$2.16
- User provides their OpenRouter API key (you don't pay)

---

## Architecture Decisions Explained

### Why Two Models?
- Single model wastes tokens remembering old conversations
- Two models: Orchestrator keeps conversation context, Worker gets fresh context for each task
- Better code quality + cheaper

### Why On-Demand Tools?
- Old way: Send all 100 scripts upfront (waste tokens on irrelevant code)
- New way: AI decides what to request, plugin provides only what's needed
- 70% token savings on initial request

### Why Metadata in Roblox Attributes?
- Don't need external database
- Works offline
- Metadata auto-updates with each generation

---

## Real Problems to Watch For

See `CHALLENGES_AND_RISKS.md` for full details.

**Biggest issues:**
1. **Latency UX** — Show loading indicator IMMEDIATELY
2. **Error Messages** — Users give up if errors are confusing
3. **Metadata Staleness** — Regenerate after each edit
4. **Context Window Limits** — For very large projects
5. **Scope Creep** — Ship MVP first, add features later

---

## Building Checklist

- [ ] Read all architecture docs
- [ ] Understand API contract (in IMPLEMENTATION_PLAN.md)
- [ ] Build backend FastAPI server
- [ ] Test with Postman
- [ ] Build Roblox plugin UI
- [ ] Connect plugin to backend
- [ ] Test end-to-end
- [ ] Handle errors
- [ ] Deploy backend (Vercel or Railway)
- [ ] Publish plugin

---

## Technology Stack

**Backend:**
- Python 3.10+
- FastAPI (HTTP server)
- LangGraph (agentic orchestration)
- OpenRouter API (BYOK - user's API key)

**Plugin:**
- Lua (Roblox scripting)
- HTTP calls to backend
- Metadata scanning

**Deployment:**
- Vercel (free, cold starts) OR Railway ($5/month)
- Roblox Creator Store (plugin distribution)

---

## What to Focus On

**MVP (Minimum Viable Product):**
✅ Plugin connects to backend
✅ Backend analyzes request
✅ Backend generates code
✅ Plugin receives code
✅ User can use it

**NOT MVP (v2.1+):**
❌ Perfect UI design
❌ All possible features
❌ Maximum performance
❌ Handling every edge case

**Ship MVP first. Iterate later.**

---

## Success Metrics

- [ ] Code works (generates valid Lua)
- [ ] Plugin doesn't crash
- [ ] Latency is acceptable (< 30 sec per request)
- [ ] Error messages are clear
- [ ] Backend can be deployed
- [ ] You understand every part of the system

---

## When You Get Stuck

1. **Backend not starting?** Check Python version, virtual environment
2. **Plugin not connecting?** Check backend URL, HTTP client
3. **Generated code broken?** Add validation + error handling
4. **Latency too slow?** Show loading indicator immediately (UX perception)
5. **Token costs high?** Use cheaper model (Gemini Flash) or optimize context

---

## Further Reading

- `SIMPLE_TWO_MODEL_APPROACH.md` — Architecture deep-dive
- `IMPLEMENTATION_PLAN.md` — Your step-by-step roadmap
- `CHALLENGES_AND_RISKS.md` — Real problems + solutions
- `CONTEXT_FILTERING_EXPLAINED.md` — Context management
- `INTELLIGENT_DEPENDENCY_RESOLUTION.md` — Smart script dependencies

---

## Questions?

Refer to the detailed architecture documents. They answer almost everything.

**If something is unclear:**
1. Check the relevant architecture doc
2. Check CHALLENGES_AND_RISKS.md for how to handle it
3. Check IMPLEMENTATION_PLAN.md for the specific code structure

---

## Building Order

**Start here:**
1. Read SIMPLE_TWO_MODEL_APPROACH.md (architecture)
2. Read IMPLEMENTATION_PLAN.md (roadmap)
3. Phase 1: Design API contract + file structure
4. Phase 2: Build backend with mock tools
5. Phase 3: Build plugin UI
6. Phase 4: Connect everything + test
7. Phase 5: Deploy

**Total time:** 3-4 weeks

---

**You've got this. Ship it. Iterate. Get hired.**
