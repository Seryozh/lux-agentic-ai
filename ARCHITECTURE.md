# Luxembourg: AI-Powered Game Development Agent

## Comprehensive System Architecture Documentation

---

## Executive Summary

**Luxembourg** is an AI-powered development assistant that enables natural language game development within Roblox Studio. Users describe what they want to build in plain English, and an autonomous AI agent analyzes the project, generates code, and executes modifications—all within the game development environment.

The system demonstrates several advanced engineering patterns:
- **Agentic AI Architecture** with tool-calling and autonomous decision-making
- **Novel Bidirectional Communication** over one-way HTTP constraints
- **Cost-Optimized Multi-Level Exploration** reducing API costs by ~90%
- **Production-Ready Deployment** with session management and fault tolerance

**Key Metrics:**
- 1,000+ active installations on Roblox Creator Store
- Sub-second response latency for tool operations
- Handles complex multi-action tasks in single requests
- Zero data retention (privacy-first design)

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Component Deep Dive](#3-component-deep-dive)
4. [Communication Patterns](#4-communication-patterns)
5. [AI Agent Architecture](#5-ai-agent-architecture)
6. [Data Flow & Processing Pipeline](#6-data-flow--processing-pipeline)
7. [Cost Optimization Strategies](#7-cost-optimization-strategies)
8. [Security Architecture](#8-security-architecture)
9. [Deployment Architecture](#9-deployment-architecture)
10. [Scalability & Performance](#10-scalability--performance)
11. [Design Decisions & Trade-offs](#11-design-decisions--trade-offs)
12. [Future Architecture Considerations](#12-future-architecture-considerations)

---

## 1. System Overview

### 1.1 Problem Statement

Game development in Roblox Studio requires significant technical expertise. Developers must understand Lua scripting, the Roblox API, UI systems, networking, and game architecture. This creates a barrier for:
- Beginners learning game development
- Rapid prototyping of ideas
- Non-programmers with creative visions

### 1.2 Solution

Luxembourg provides an AI-powered natural language interface that:
1. **Understands** user intent from plain English descriptions
2. **Analyzes** the current project structure and existing code
3. **Generates** appropriate modifications (scripts, UI, properties)
4. **Executes** changes directly in the development environment
5. **Maintains** context across conversation turns

### 1.3 Key Innovation

The primary technical innovation is a **polling bridge pattern** that enables true bidirectional communication between an AI agent and a Roblox plugin, despite Roblox's one-way HTTP constraint (plugins can only make outbound requests, not receive incoming connections).

---

## 2. High-Level Architecture

### 2.1 System Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ROBLOX STUDIO                                  │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    LUXEMBOURG PLUGIN                               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │   Chat UI   │  │  Project    │  │   Action    │               │  │
│  │  │  Interface  │  │   Scanner   │  │  Executor   │               │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘               │  │
│  │         │                │                │                       │  │
│  │         └────────────────┼────────────────┘                       │  │
│  │                          │                                        │  │
│  │                   ┌──────▼──────┐                                 │  │
│  │                   │   HTTP      │                                 │  │
│  │                   │   Client    │                                 │  │
│  │                   └──────┬──────┘                                 │  │
│  └──────────────────────────┼────────────────────────────────────────┘  │
└─────────────────────────────┼───────────────────────────────────────────┘
                              │
                              │ HTTPS
                              │
┌─────────────────────────────▼───────────────────────────────────────────┐
│                         CLOUD BACKEND                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      FASTAPI SERVER                                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │
│  │  │    /chat    │  │    /poll    │  │  /respond   │               │  │
│  │  │   Endpoint  │  │   Endpoint  │  │  Endpoint   │               │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘               │  │
│  │         │                │                │                       │  │
│  │         └────────────────┼────────────────┘                       │  │
│  │                          │                                        │  │
│  │                   ┌──────▼──────┐                                 │  │
│  │                   │   Session   │                                 │  │
│  │                   │   Manager   │                                 │  │
│  │                   └──────┬──────┘                                 │  │
│  │                          │                                        │  │
│  │                   ┌──────▼──────┐                                 │  │
│  │                   │  AI Agent   │                                 │  │
│  │                   │  (LangGraph)│                                 │  │
│  │                   └──────┬──────┘                                 │  │
│  └──────────────────────────┼────────────────────────────────────────┘  │
└─────────────────────────────┼───────────────────────────────────────────┘
                              │
                              │ HTTPS
                              │
┌─────────────────────────────▼───────────────────────────────────────────┐
│                        OPENROUTER API                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │              LLM Provider (Gemini Flash / Claude / GPT)            │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Responsibilities

| Component | Technology | Responsibility |
|-----------|------------|----------------|
| **Chat UI** | Lua/Roblox | User interaction, message display, action approval |
| **Project Scanner** | Lua/Roblox | Analyzes game structure, indexes scripts |
| **Action Executor** | Lua/Roblox | Executes AI-generated modifications in game |
| **HTTP Client** | Lua/Roblox | Communication with cloud backend |
| **FastAPI Server** | Python | Request routing, session management |
| **Session Manager** | Python | State persistence, polling bridge |
| **AI Agent** | Python/LangGraph | Reasoning, tool execution, response generation |
| **LLM Provider** | External API | Natural language understanding, code generation |

---

## 3. Component Deep Dive

### 3.1 Plugin Architecture (Client-Side)

The plugin operates within Roblox Studio as a trusted extension with full access to the game hierarchy.

#### 3.1.1 User Interface Layer

```
┌────────────────────────────────────────┐
│              Status Bar                 │
│  [●] Ready    [New Chat]    ~937 tokens│
├────────────────────────────────────────┤
│                                        │
│  You: Add a sprint system with         │
│  stamina that regenerates over time    │
│                                        │
│  Lux: I'll create a complete sprint    │
│  system with UI and mechanics...       │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │ 1. Create ScreenGui "StaminaUI"  │  │
│  │ 2. Create Frame "StaminaBar"     │  │
│  │ 3. Create LocalScript "Sprint"   │  │
│  └──────────────────────────────────┘  │
│                                        │
│  [✓ Apply All Actions]                 │
│                                        │
├────────────────────────────────────────┤
│  [Ask Luxembourg...              ] [>] │
└────────────────────────────────────────┘
```

**Design Principles:**
- **Minimal cognitive load**: Single-purpose interface
- **Transparency**: All proposed actions shown before execution
- **User control**: Explicit approval required for modifications
- **Context awareness**: Token usage and request tracking

#### 3.1.2 Project Scanner

The scanner builds a lightweight representation of the game for AI context.

**Scanning Strategy:**
```
Game
├── Workspace [42 children]
├── ServerScriptService [8 children]
├── ReplicatedStorage [15 children]
├── StarterGui [3 children]
└── ...
```

**Key Design Decisions:**
- **Lazy loading**: Only top-level structure initially (no script content)
- **On-demand exploration**: Full content fetched only when agent requests
- **Selective inclusion**: Filters irrelevant engine instances

#### 3.1.3 Action Executor

Executes eight fundamental action types that compose into any game modification:

| Action Type | Purpose | Example |
|-------------|---------|---------|
| `set_property` | Modify instance attributes | Change Part color, size |
| `create_instance` | Create new game objects | Add Parts, UI elements |
| `delete_instance` | Remove objects | Clean up unused assets |
| `move_instance` | Reparent in hierarchy | Reorganize structure |
| `clone_instance` | Duplicate objects | Create from templates |
| `create_script` | Add new scripts | New game logic |
| `modify_script` | Update existing scripts | Bug fixes, features |
| `delete_script` | Remove scripts | Code cleanup |

**Type Conversion System:**
```
JSON Input              → Roblox Type
─────────────────────────────────────
[255, 128, 0]          → Color3.fromRGB(255, 128, 0)
[10, 5, 20]            → Vector3.new(10, 5, 20)
[0, 100, 0, 50]        → UDim2.new(0, 100, 0, 50)
"Enum.Material.Grass"  → Enum.Material.Grass
"Bright red"           → BrickColor.new("Bright red")
```

### 3.2 Backend Architecture (Server-Side)

#### 3.2.1 API Layer

Three endpoints form the complete API surface:

```
POST /chat
├── Input: session_id, user_message, project_map, api_key
├── Process: Run AI agent with context
└── Output: message, actions[], metadata

GET /poll/{session_id}
├── Input: session_id
├── Process: Check for pending agent requests
└── Output: pending_requests[], queued_actions[]

POST /poll/{session_id}/respond
├── Input: request_id, data
├── Process: Fulfill agent's data request
└── Output: acknowledgment
```

#### 3.2.2 Session Management

Sessions provide conversation continuity and state isolation:

```
Session
├── session_id          # Unique identifier
├── conversation_history # Message log
├── project_map          # Current game structure
├── cached_metadata      # Tool response cache
├── cached_scripts       # Script content cache
├── pending_requests     # Awaiting plugin data
├── fulfilled_data       # Received from plugin
├── action_queue         # Generated actions
├── executed_hashes      # Deduplication tracking
└── timestamps           # TTL management
```

**Lifecycle Management:**
- **Creation**: On first request from new session_id
- **Expiration**: After 1 hour of inactivity (configurable)
- **Cleanup**: Background task runs every 5 minutes

#### 3.2.3 AI Agent Orchestration

Built on LangGraph for structured agent workflows:

```
                    ┌─────────────┐
                    │    START    │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
              ┌────►│   AGENT     │◄────┐
              │     │    NODE     │     │
              │     └──────┬──────┘     │
              │            │            │
              │     ┌──────▼──────┐     │
              │     │ Tool Calls? │     │
              │     └──────┬──────┘     │
              │            │            │
              │      Yes   │   No       │
              │     ┌──────┴──────┐     │
              │     │             │     │
              │     ▼             ▼     │
        ┌─────┴─────┐     ┌───────────┐│
        │  Execute  │     │   Parse   ││
        │   Tools   │     │  Response ││
        └─────┬─────┘     └─────┬─────┘│
              │                 │      │
              └─────────────────┘      │
                                       │
                    ┌──────────────────┘
                    │
             ┌──────▼──────┐
             │     END     │
             └─────────────┘
```

---

## 4. Communication Patterns

### 4.1 The Polling Bridge Pattern

**The Challenge:**
Roblox plugins can only make outbound HTTP requests. They cannot open websockets or receive incoming connections. This creates a fundamental challenge for AI agents that need to request additional information during processing.

**The Solution:**
An asynchronous polling bridge using event-based synchronization:

```
TIMELINE
────────────────────────────────────────────────────────────────────────►

PLUGIN                          BACKEND                         AGENT
  │                               │                               │
  │──POST /chat─────────────────►│                               │
  │                               │──run_agent()────────────────►│
  │                               │                               │
  │                               │          ┌───────────────────┤
  │                               │          │ Need script data  │
  │                               │          └───────────────────┤
  │                               │                               │
  │                               │◄──create_pending_request()───│
  │                               │                               │
  │                               │   [Agent AWAITS asyncio.Event]
  │                               │                               │
  │──GET /poll──────────────────►│                               │
  │◄─────pending_requests────────│                               │
  │                               │                               │
  │  [Read script from game]      │                               │
  │                               │                               │
  │──POST /respond───────────────►│                               │
  │                               │──event.set()────────────────►│
  │                               │                               │
  │                               │   [Agent RESUMES]             │
  │                               │                               │
  │                               │◄──actions + response──────────│
  │◄─────ChatResponse─────────────│                               │
  │                               │                               │
```

**Key Implementation Details:**

1. **Async Event Creation**: When agent needs data, creates `asyncio.Event()`
2. **Blocking Wait**: Agent awaits event with configurable timeout (30s default)
3. **Polling Loop**: Plugin polls every 100ms while processing
4. **Event Signaling**: Response endpoint calls `event.set()` to wake agent
5. **Data Retrieval**: Agent retrieves data from `fulfilled_data` dictionary

**Benefits:**
- True bidirectional communication over one-way HTTP
- No long-polling or connection holding
- Graceful timeout handling
- Works within platform constraints

### 4.2 Request-Response Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                         COMPLETE REQUEST FLOW                         │
└──────────────────────────────────────────────────────────────────────┘

1. USER INPUT
   └─► "Add a health bar that decreases when player takes damage"

2. PLUGIN PROCESSING
   ├─► Build project map (lazy, top-level only)
   ├─► Package request with session context
   └─► POST to /chat endpoint

3. BACKEND RECEIVES
   ├─► Validate request schema
   ├─► Retrieve or create session
   ├─► Update session with latest project map
   └─► Invoke AI agent

4. AGENT REASONING (Loop)
   ├─► Analyze user intent
   ├─► Determine information needs
   ├─► Call tools if needed:
   │   ├─► search_project("health") → Find existing systems
   │   ├─► get_metadata("PlayerScript") → Quick preview
   │   └─► get_full_script("PlayerScript") → Full code + hash
   ├─► Generate action plan
   └─► Format JSON response

5. TOOL EXECUTION (If Needed)
   ├─► Agent creates pending request
   ├─► Agent awaits response
   ├─► Plugin polls, sees request
   ├─► Plugin reads game data
   ├─► Plugin responds with data
   └─► Agent continues with data

6. RESPONSE GENERATION
   ├─► Agent outputs JSON with actions
   ├─► Backend validates action schema
   ├─► Actions deduplicated (hash-based)
   └─► Response sent to plugin

7. USER REVIEW
   ├─► Actions displayed with descriptions
   ├─► User reviews proposed changes
   └─► User clicks "Apply" to execute

8. EXECUTION
   ├─► Each action executed in sequence
   ├─► Type conversions applied
   ├─► Changes made to game
   └─► Confirmation displayed
```

---

## 5. AI Agent Architecture

### 5.1 Agent Design Philosophy

The agent follows a **continuous execution model** inspired by production AI coding assistants:

**Principles:**
1. **Complete tasks fully**: No arbitrary step breaks requiring user continuation
2. **Explore before acting**: Use tools to understand context
3. **Verify before modifying**: Read scripts before attempting changes
4. **Explain actions clearly**: Provide human-readable descriptions

### 5.2 Tool System

Four tools provide the agent's interface to the game:

```
┌─────────────────────────────────────────────────────────────────┐
│                         TOOL HIERARCHY                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  LEVEL 1: Structure (Always Available)                          │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Project Map - Included in every request                │    │
│  │  • Top-level containers with child counts               │    │
│  │  • No script content                                    │    │
│  │  • Cost: FREE (included in context)                     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           ▼                                      │
│  LEVEL 2: Discovery (On-Demand)                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  search_project(query)                                   │    │
│  │  • Semantic search across all scripts                   │    │
│  │  • Returns: names and paths                             │    │
│  │  • Cost: LOW (metadata only)                            │    │
│  │                                                          │    │
│  │  list_children(path)                                     │    │
│  │  • List contents of specific location                   │    │
│  │  • Returns: child names and types                       │    │
│  │  • Cost: LOW (metadata only)                            │    │
│  │                                                          │    │
│  │  get_metadata(script_name)                               │    │
│  │  • Quick script preview                                  │    │
│  │  • Returns: type, location, line count, dependencies    │    │
│  │  • Cost: LOW (summary only)                             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           ▼                                      │
│  LEVEL 3: Full Access (When Needed)                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  get_full_script(script_name)                            │    │
│  │  • Complete script source code                          │    │
│  │  • Returns: full source + content hash                  │    │
│  │  • Cost: HIGH (full content transfer)                   │    │
│  │  • REQUIRED before any modify_script action             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Execution Loop

```python
# Simplified agent loop logic
while iterations < MAX_ITERATIONS:

    # Get LLM response
    response = llm.invoke(messages)

    # Check for tool calls
    if response.has_tool_calls():
        # Execute tools in parallel
        results = await asyncio.gather(*[
            execute_tool(call) for call in response.tool_calls
        ])
        # Add results to context
        messages.extend(tool_messages(results))
        continue

    # Try to parse as action JSON
    if is_valid_json(response.content):
        actions = parse_actions(response.content)
        return actions

    # Handle conversational response
    if is_conversational(response.content):
        return {"message": response.content}

    # Request JSON format retry
    messages.append("Please respond with valid JSON")
```

### 5.4 Context Management

**System Prompt Structure:**
```
┌─────────────────────────────────────────────────────────────────┐
│ SYSTEM PROMPT                                                    │
├─────────────────────────────────────────────────────────────────┤
│ 1. Role Definition                                               │
│    "Expert Roblox Studio AI with full game control"             │
│                                                                  │
│ 2. Execution Model                                               │
│    "Complete ENTIRE task in single response"                    │
│                                                                  │
│ 3. Tool Documentation                                            │
│    search_project, list_children, get_metadata, get_full_script │
│                                                                  │
│ 4. Action Format Specification                                   │
│    JSON schema with all 8 action types                          │
│                                                                  │
│ 5. Rules & Constraints                                           │
│    Hash verification, type formats, best practices              │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ PROJECT CONTEXT                                                  │
├─────────────────────────────────────────────────────────────────┤
│ # Current Project Structure                                      │
│ Game                                                             │
│   Workspace [42 children]                                        │
│   ServerScriptService [8 children]                               │
│   ...                                                            │
│                                                                  │
│ # Recently Created Objects (Working Memory)                      │
│   - game.Workspace.HealthBar (ScreenGui)                        │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ CONVERSATION HISTORY (Sliding Window: Last 20 messages)         │
├─────────────────────────────────────────────────────────────────┤
│ User: "Create a part"                                            │
│ Assistant: "Created Part at Workspace"                          │
│ User: "Make it red"                                              │
│ Assistant: "Changed Part color to red"                          │
│ ...                                                              │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ CURRENT MESSAGE                                                  │
├─────────────────────────────────────────────────────────────────┤
│ User: "Add a health bar that shows player health"               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Data Flow & Processing Pipeline

### 6.1 Action Generation Pipeline

```
USER REQUEST
     │
     ▼
┌─────────────────┐
│  Intent Parse   │ ◄── LLM analyzes natural language
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Context Gather  │ ◄── Tools fetch project state
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Plan Generate  │ ◄── LLM creates action sequence
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  JSON Format    │ ◄── Structured output with actions
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Validate      │ ◄── Pydantic schema validation
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Deduplicate   │ ◄── Hash-based duplicate removal
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Queue/Send    │ ◄── Actions queued for plugin
└─────────────────┘
```

### 6.2 Script Modification Flow

Script modifications require hash verification to prevent data loss:

```
1. AGENT REQUESTS SCRIPT
   └─► get_full_script("PlayerController")

2. PLUGIN READS SCRIPT
   ├─► Finds script in game hierarchy
   ├─► Reads current source code
   ├─► Computes content hash (MD5)
   └─► Returns: {source, hash, path}

3. AGENT MODIFIES
   ├─► Analyzes current code
   ├─► Generates modified version
   └─► Creates action with original_hash

4. EXECUTOR VERIFIES
   ├─► Reads current script hash
   ├─► Compares with original_hash
   ├─► If match: Apply modification
   └─► If mismatch: Reject (concurrent edit)
```

**Why Hash Verification?**
- Prevents overwriting concurrent human edits
- Ensures agent modifies expected version
- Provides audit trail for changes

### 6.3 Caching Strategy

Three-level caching reduces redundant operations:

```
┌─────────────────────────────────────────────────────────────────┐
│                       CACHING LAYERS                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  SESSION-LEVEL CACHE (In-Memory)                                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  cached_metadata                                         │    │
│  │  ├── "search:player" → [results...]                     │    │
│  │  ├── "search:health" → [results...]                     │    │
│  │  └── "children:Workspace" → [children...]               │    │
│  │                                                          │    │
│  │  cached_scripts                                          │    │
│  │  ├── "PlayerController" → {source, hash}                │    │
│  │  └── "GameManager" → {source, hash}                     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  CACHE INVALIDATION                                             │
│  • Cleared when project_map changes between requests            │
│  • Cleared on new chat session                                  │
│  • TTL-based expiration with session (1 hour)                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Cost Optimization Strategies

### 7.1 Token Efficiency

**Problem**: Sending full project content with every request is expensive.

**Solution**: Progressive disclosure with lazy loading.

```
NAIVE APPROACH (Expensive)
──────────────────────────
Every request includes:
• Full project tree (all levels)     ~5,000 tokens
• All script sources                 ~50,000 tokens
• Previous conversation              ~10,000 tokens
                                     ───────────────
Total per request:                   ~65,000 tokens

OPTIMIZED APPROACH (Luxembourg)
───────────────────────────────
Every request includes:
• Top-level structure only           ~500 tokens
• Conversation (last 20 msgs)        ~5,000 tokens
                                     ───────────────
Base per request:                    ~5,500 tokens

On-demand (only when needed):
• Search results                     ~200 tokens
• Script metadata                    ~100 tokens
• Full script (per script)           ~1,000 tokens

SAVINGS: ~90% reduction in token usage
```

### 7.2 Deduplication

**Problem**: Retry scenarios or LLM errors might generate duplicate actions.

**Solution**: Hash-based deduplication at queue time.

```python
def compute_action_hash(action):
    key = f"{action.type}:{action.target}:{action.name}"
    return md5(key).hexdigest()[:12]

def queue_action(action):
    hash = compute_action_hash(action)
    if hash not in executed_hashes:
        executed_hashes.add(hash)
        action_queue.append(action)
```

### 7.3 Parallel Tool Execution

When agent needs multiple pieces of information, tools execute concurrently:

```
SEQUENTIAL (Slow)
─────────────────
search_project("health")   ──────────────────► 500ms
                                    get_metadata("Player")   ──────────────────► 300ms
                                                                      Total: 800ms

PARALLEL (Fast)
───────────────
search_project("health")   ──────────────────►
get_metadata("Player")     ──────────────────►
                                    Total: 500ms (limited by slowest)
```

---

## 8. Security Architecture

### 8.1 Privacy-First Design

```
┌─────────────────────────────────────────────────────────────────┐
│                    DATA HANDLING POLICY                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  WHAT WE STORE (Session-Only)                                   │
│  ├── Conversation history (in-memory, session-scoped)           │
│  ├── Project structure (in-memory, session-scoped)              │
│  └── Cached tool responses (in-memory, session-scoped)          │
│                                                                  │
│  WHAT WE NEVER STORE                                            │
│  ├── API keys (processed, never persisted)                      │
│  ├── User identities                                            │
│  ├── Project content after session ends                         │
│  └── Conversation logs to disk                                  │
│                                                                  │
│  DATA LIFECYCLE                                                  │
│  ├── Created: On first request                                  │
│  ├── Held: In memory only                                       │
│  ├── Expired: After 1 hour of inactivity                        │
│  └── Deleted: Permanently removed from memory                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 BYOK (Bring Your Own Key)

Users provide their own API keys for LLM access:

**Benefits:**
- No central key to compromise
- User controls their own costs
- No data flows through our accounts
- Transparent billing (direct to user)

**Implementation:**
- Key sent with each request
- Key held in session memory only
- Key cleared on session expiration
- Key never logged or persisted

### 8.3 Input Validation

All inputs validated with strict schemas:

```
ChatRequest
├── session_id: string, 1-128 chars
├── user_message: string, 1-10,000 chars
├── project_map: string, max 100,000 chars
└── openrouter_key: string, validated format

Action
├── type: enum [8 valid types]
├── target: string, min 1 char
├── properties: dict (validated per type)
└── original_hash: string (for modifications)
```

### 8.4 Action Approval Workflow

Every modification requires explicit user approval:

```
┌──────────────────────────────────────────┐
│  Proposed Actions:                        │
│                                           │
│  1. Create Part "Floor" in Workspace      │
│  2. Set Floor.Size to [100, 1, 100]       │
│  3. Set Floor.Anchored to true            │
│                                           │
│  [✓ Apply All]  [✗ Cancel]               │
└──────────────────────────────────────────┘
```

**Safeguards:**
- Actions displayed in human-readable form
- User must explicitly click "Apply"
- No automatic execution
- Cancel option always available

---

## 9. Deployment Architecture

### 9.1 Infrastructure Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     DEPLOYMENT TOPOLOGY                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ROBLOX CREATOR STORE                                           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Luxembourg Plugin (.rbxm)                               │    │
│  │  • Distributed to 1,000+ users                          │    │
│  │  • Auto-updates via Roblox                              │    │
│  │  • Runs locally in Roblox Studio                        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           │ HTTPS                                │
│                           ▼                                      │
│  RAILWAY.APP (Cloud Platform)                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Backend Service                                         │    │
│  │  • Python 3.11 runtime                                  │    │
│  │  • Auto-scaling (Railway managed)                       │    │
│  │  • HTTPS termination                                    │    │
│  │  • Environment variable injection                       │    │
│  └─────────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           │ HTTPS                                │
│                           ▼                                      │
│  OPENROUTER (LLM Gateway)                                       │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Multi-Model Access                                      │    │
│  │  • Gemini Flash (default)                               │    │
│  │  • Claude, GPT-4, etc. (user choice)                    │    │
│  │  • Usage-based billing                                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 9.2 CI/CD Pipeline

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│   Push   │───►│   Lint   │───►│   Type   │───►│  Build   │
│  to Git  │    │  (Ruff)  │    │  Check   │    │  Check   │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
                                                      │
                                                      ▼
                                               ┌──────────┐
                                               │  Deploy  │
                                               │ (Railway)│
                                               └──────────┘
```

**Pipeline Stages:**
1. **Lint**: Code style validation (Ruff)
2. **Type Check**: Static type analysis (mypy)
3. **Build Check**: Verify application starts
4. **Deploy**: Automatic on main branch (Railway)

### 9.3 Configuration Management

```
┌─────────────────────────────────────────────────────────────────┐
│                   CONFIGURATION HIERARCHY                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ENVIRONMENT VARIABLES (Production)                             │
│  ├── PORT                    # Server port (Railway-assigned)   │
│  ├── POLL_TIMEOUT            # Tool request timeout (30s)       │
│  ├── SESSION_TTL             # Session lifetime (3600s)         │
│  ├── CLEANUP_INTERVAL        # Cleanup frequency (300s)         │
│  └── MAX_JSON_RETRIES        # LLM retry limit (3)              │
│                                                                  │
│  DEFAULTS (Fallback)                                            │
│  └── Defined in config.py Settings class                        │
│                                                                  │
│  PLUGIN SETTINGS (Persisted)                                    │
│  └── API Key stored in plugin:SetSetting()                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. Scalability & Performance

### 10.1 Performance Characteristics

| Operation | Typical Latency | Notes |
|-----------|-----------------|-------|
| Project map build | <100ms | Lazy loading, top-level only |
| Tool execution | 100-500ms | Includes plugin round-trip |
| LLM response | 1-5s | Model-dependent |
| Action execution | <50ms per action | Local to Roblox Studio |
| Full request cycle | 2-10s | Depends on complexity |

### 10.2 Scalability Model

```
┌─────────────────────────────────────────────────────────────────┐
│                    SCALABILITY DIMENSIONS                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  HORIZONTAL: Concurrent Users                                   │
│  ├── Stateless request handling                                 │
│  ├── Session isolation (no cross-session state)                 │
│  ├── Railway auto-scaling                                       │
│  └── Bottleneck: LLM API rate limits                           │
│                                                                  │
│  VERTICAL: Request Complexity                                   │
│  ├── Lazy loading minimizes data transfer                       │
│  ├── Caching reduces redundant operations                       │
│  ├── Parallel tool execution                                    │
│  └── Bottleneck: LLM context window                            │
│                                                                  │
│  TEMPORAL: Session Duration                                     │
│  ├── Sliding window for conversation history (20 messages)      │
│  ├── TTL-based session cleanup                                  │
│  ├── Cache invalidation on project changes                      │
│  └── Bottleneck: Memory for long sessions                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 10.3 Fault Tolerance

| Failure Mode | Detection | Recovery |
|--------------|-----------|----------|
| LLM timeout | 30s timeout | Return error message |
| Plugin timeout | 30s timeout | Agent continues without data |
| Invalid JSON | Parse exception | Retry with correction prompt |
| Session expiry | TTL check | Create new session |
| Network error | HTTP exception | User-facing error message |

---

## 11. Design Decisions & Trade-offs

### 11.1 Polling vs. WebSocket

**Decision**: Polling bridge pattern

**Trade-offs:**
| Aspect | Polling | WebSocket |
|--------|---------|-----------|
| Roblox compatibility | ✓ Works | ✗ Not supported |
| Latency | ~100ms intervals | Real-time |
| Complexity | Higher (event sync) | Lower |
| Resource usage | Periodic requests | Persistent connection |

**Rationale**: WebSocket would be ideal, but Roblox plugins cannot receive incoming connections. The polling bridge enables bidirectional communication within platform constraints.

### 11.2 Single Model vs. Multi-Model

**Decision**: Unified single model with tools

**Trade-offs:**
| Aspect | Single Model | Orchestrator + Worker |
|--------|--------------|----------------------|
| Latency | Lower (1 LLM call path) | Higher (2+ calls) |
| Cost | Lower | Higher |
| Complexity | Simpler | More complex |
| Specialization | General purpose | Task-optimized |

**Rationale**: Modern models (Gemini Flash, Claude) handle both planning and execution well. The tool system provides necessary specialization without multi-model overhead.

### 11.3 Step-by-Step vs. Continuous Execution

**Decision**: Continuous execution (complete task in one response)

**Trade-offs:**
| Aspect | Step-by-Step | Continuous |
|--------|--------------|------------|
| User control | Per-step approval | Single approval |
| UX friction | Higher (many clicks) | Lower (one click) |
| Error recovery | Granular | All-or-nothing |
| Context usage | Lower per step | Higher per request |

**Rationale**: Step-by-step execution created UX friction (multiple "continue" clicks). Continuous execution matches user mental model ("do this task") and reduces interaction overhead.

### 11.4 Server-Side vs. Client-Side LLM

**Decision**: Server-side LLM via API

**Trade-offs:**
| Aspect | Server-Side | Client-Side |
|--------|-------------|-------------|
| Privacy | Data leaves device | Data stays local |
| Capability | Full model access | Limited by device |
| Cost model | API usage | One-time/hardware |
| Updates | Always latest | Manual updates |

**Rationale**: Server-side enables access to powerful models without requiring user hardware. BYOK model addresses privacy concerns while maintaining capability.

---

## 12. Future Architecture Considerations

### 12.1 Potential Enhancements

**Streaming Responses**
- Progressive action display as LLM generates
- Reduced perceived latency
- Earlier user feedback

**Multi-File Operations**
- Coordinated changes across multiple scripts
- Transaction-like semantics
- Rollback capability

**Learning from Corrections**
- Track user modifications to AI output
- Improve future suggestions
- Personalized model fine-tuning

**Collaborative Features**
- Multiple users in same session
- Shared project context
- Conflict resolution

### 12.2 Scalability Roadmap

```
CURRENT STATE
├── Single backend instance
├── In-memory sessions
└── Direct LLM calls

PHASE 2: Enhanced Reliability
├── Redis session store
├── Multiple backend instances
└── Load balancer

PHASE 3: Enterprise Scale
├── Distributed caching
├── LLM response caching
└── Geographic distribution
```

### 12.3 Integration Possibilities

- **Version Control**: Git-like history for AI changes
- **Team Features**: Shared AI assistants for studios
- **Asset Integration**: AI-generated 3D models, textures
- **Testing**: Automated test generation for game logic

---

## Appendix A: Technology Stack Summary

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Frontend** | Lua/Roblox | Plugin UI and game integration |
| **Backend** | Python/FastAPI | API server and session management |
| **Agent Framework** | LangGraph | AI agent orchestration |
| **LLM Integration** | LangChain | Tool calling and LLM interface |
| **LLM Provider** | OpenRouter | Multi-model LLM access |
| **Validation** | Pydantic | Request/response schemas |
| **Deployment** | Railway | Cloud hosting and CI/CD |
| **Distribution** | Roblox Creator Store | Plugin distribution |

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **Action** | A single atomic modification to the game (create, modify, delete) |
| **Agent** | The AI system that reasons about requests and generates actions |
| **BYOK** | Bring Your Own Key - user provides their own API credentials |
| **LangGraph** | Framework for building stateful agent workflows |
| **Polling Bridge** | Pattern for bidirectional communication over one-way HTTP |
| **Project Map** | Lightweight representation of game structure for AI context |
| **Session** | Isolated conversation state for a single user interaction |
| **Tool** | Function the AI agent can call to gather information |

---

## Appendix C: Metrics & Statistics

| Metric | Value |
|--------|-------|
| Total Lines of Code | 2,237 |
| Backend (Python) | 813 lines |
| Plugin (Lua) | 1,424 lines |
| Active Installations | 1,000+ |
| Supported Action Types | 8 |
| Available Tools | 4 |
| Max Conversation History | 20 messages |
| Session TTL | 1 hour |
| Tool Timeout | 30 seconds |
| Estimated Token Savings | ~90% |

---

*Document Version: 1.0*
*Last Updated: February 2026*
*Author: Sergei*
