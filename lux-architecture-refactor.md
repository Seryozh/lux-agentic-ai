# Lux Architecture Refactor Plan

## The Problem

Currently, everything is flat in `/src`:
```
src/
  CircuitBreaker.lua
  CompressionFallback.lua
  ContextSelector.lua
  DecisionMemory.lua
  ErrorAnalyzer.lua
  ErrorPredictor.lua
  OpenRouterClient.lua    ← 1489 lines, does too much
  OutputValidator.lua
  ProjectContext.lua
  SessionManager.lua
  SystemPrompt.lua
  TaskPlanner.lua
  ToolResilience.lua
  Tools.lua               ← 69KB, does too much
  WorkingMemory.lua
  ... etc
```

**Issues:**
1. No clear grouping - hard to see what relates to what
2. OpenRouterClient.lua is a god object (1489 lines)
3. Dependencies are implicit - you have to read the code to know what calls what
4. Can't improve one system without understanding all of them
5. Can't extract systems for standalone use

---

## Proposed Architecture

```
src/
├── Core/                      # The Engine
│   ├── init.lua               # Exports: AgenticLoop, ApiClient
│   ├── AgenticLoop.lua        # The while(tools) loop - EXTRACTED from OpenRouterClient
│   ├── ApiClient.lua          # HTTP calls to OpenRouter - EXTRACTED from OpenRouterClient
│   └── ConversationHistory.lua # Message history management
│
├── Memory/                    # Remembering Things
│   ├── init.lua               # Exports: WorkingMemory, DecisionMemory, ProjectContext
│   ├── WorkingMemory.lua      # Tiered memory with decay
│   ├── DecisionMemory.lua     # Pattern learning from past tasks
│   └── ProjectContext.lua     # Persisted project knowledge
│
├── Safety/                    # Preventing Chaos
│   ├── init.lua               # Exports: CircuitBreaker, OutputValidator, etc.
│   ├── CircuitBreaker.lua     # Failure spiral prevention
│   ├── OutputValidator.lua    # Catch hallucinated tool calls
│   ├── ErrorAnalyzer.lua      # Classify errors, suggest recovery
│   ├── ErrorPredictor.lua     # Predict errors before they happen
│   └── ToolResilience.lua     # Auto-retry, health monitoring
│
├── Context/                   # What to Tell the LLM
│   ├── init.lua               # Exports: ContextSelector, PromptBuilder
│   ├── ContextSelector.lua    # Pick relevant scripts
│   ├── PromptBuilder.lua      # Build dynamic system prompts (renamed from SystemPrompt)
│   └── CompressionFallback.lua # Compress long histories
│
├── Planning/                  # Thinking Before Acting
│   ├── init.lua               # Exports: TaskPlanner
│   ├── TaskPlanner.lua        # Complexity analysis, intent tracking
│   └── Verification.lua       # Verify changes worked
│
├── Tools/                     # Doing Things in Roblox
│   ├── init.lua               # Exports: ToolExecutor, ToolDefinitions
│   ├── ToolExecutor.lua       # Execute tool calls (EXTRACTED from Tools.lua)
│   ├── ToolDefinitions.lua    # Tool schemas for LLM
│   ├── ReadTools.lua          # get_script, get_instance, list_children, etc.
│   ├── WriteTools.lua         # patch_script, create_instance, etc.
│   └── ProjectTools.lua       # discover_project, update_context, etc.
│
├── Coordination/              # Orchestrating Everything
│   ├── init.lua               # Exports: SessionManager
│   └── SessionManager.lua     # Lifecycle coordination (SIMPLIFIED)
│
├── UI/                        # User Interface
│   ├── init.lua
│   ├── Builder.lua
│   ├── ChatRenderer.lua
│   ├── InputApproval.lua
│   ├── KeySetup.lua
│   └── UserFeedback.lua
│
├── Shared/                    # Utilities
│   ├── init.lua
│   ├── Constants.lua
│   ├── Utils.lua
│   ├── IndexManager.lua
│   └── MarkdownParser.lua
│
└── init.lua                   # Main exports for the whole src folder
```

---

## System Boundaries & Interfaces

### 1. Core (The Engine)

**Responsibility:** Run the agentic loop. Call LLM. Execute tools. Repeat until done.

**Inputs:**
- User message
- Tool executor function
- Callbacks for UI updates

**Outputs:**
- Final response text
- Or: "awaiting approval" state

**Interface:**
```lua
local Core = require(src.Core)

-- Start a conversation
local result = Core.AgenticLoop.run({
    userMessage = "Create a health bar",
    toolExecutor = Tools.execute,
    onIteration = function(n, status) end,
    onToolCall = function(name, args) end,
})

-- Result is either:
-- { success = true, text = "I created..." }
-- { awaitingApproval = true, operation = {...} }
-- { success = false, error = "..." }
```

**Dependencies:** 
- ApiClient (for HTTP)
- Safety.CircuitBreaker (to check before tools)
- Safety.OutputValidator (to validate tool calls)
- Context.CompressionFallback (to compress history)

---

### 2. Memory (Remembering Things)

**Responsibility:** Track what happened. Remember patterns. Persist knowledge.

**Interface:**
```lua
local Memory = require(src.Memory)

-- Working Memory (session-scoped, decays)
Memory.Working.setGoal("Create a health bar", analysis)
Memory.Working.add("tool_result", "Created HealthFrame", {path = "..."})
Memory.Working.formatForPrompt() -- Returns formatted string

-- Decision Memory (persisted, learns patterns)
Memory.Decision.startSequence("Create a health bar")
Memory.Decision.recordTool("create_instance", true, "Created frame")
Memory.Decision.endSequence(true, "Completed successfully")
Memory.Decision.getSuggestionsFor("Create a button") -- Returns past patterns

-- Project Context (persisted, project-specific knowledge)
Memory.Project.update("architecture", "PlayerData is in ServerScriptService")
Memory.Project.formatForPrompt() -- Returns formatted string
```

**Dependencies:** None (leaf module)

---

### 3. Safety (Preventing Chaos)

**Responsibility:** Stop bad things before they happen. Recover from failures.

**Interface:**
```lua
local Safety = require(src.Safety)

-- Circuit Breaker
local canProceed, warning = Safety.CircuitBreaker.canProceed()
Safety.CircuitBreaker.recordFailure("patch_script", "not found")
Safety.CircuitBreaker.recordSuccess()
Safety.CircuitBreaker.forceReset()

-- Output Validator  
local validation = Safety.OutputValidator.validate({
    name = "patch_script",
    args = { path = "...", search_content = "...", replace_content = "..." }
})
-- Returns: { valid = true/false, issues = [...], suggestions = [...] }

-- Error Analyzer
local analysis = Safety.ErrorAnalyzer.classify("patch_script", args, "not found")
-- Returns: { category = "missing_resource", severity = "medium", recoveryStrategies = [...] }

-- Tool Resilience
local result = Safety.ToolResilience.executeResilient(toolFn, "patch_script", args)
-- Auto-retries on transient errors, returns result
```

**Dependencies:** 
- Shared.Utils (for path utilities)
- Context.ContextSelector (for freshness tracking - could be decoupled)

---

### 4. Context (What to Tell the LLM)

**Responsibility:** Build the right prompt. Pick relevant scripts. Compress when needed.

**Interface:**
```lua
local Context = require(src.Context)

-- Context Selector
local selection = Context.Selector.selectRelevantScripts("Create health bar", taskAnalysis)
-- Returns: { scripts = [...], totalAvailable = 50, selectionReason = "..." }

Context.Selector.recordRead("ServerScriptService/PlayerData")
Context.Selector.recordModified("ServerScriptService/PlayerData")

-- Prompt Builder
local systemPrompt = Context.PromptBuilder.build({
    userMessage = "Create a health bar",
    taskAnalysis = { complexity = "medium", ... },
    recentFailures = 2,
    memoryContext = Memory.Working.formatForPrompt(),
    projectContext = Memory.Project.formatForPrompt(),
    scriptContext = Context.Selector.formatForPrompt(selection),
})

-- Compression
local compressed = Context.Compression.compress(conversationHistory, {
    summarizeFn = aiSummarize,  -- Optional AI summarizer
    preserveCount = 10,
})
-- Returns: { success = true, compressed = [...], strategy = "structured_truncation" }
```

**Dependencies:**
- Shared.IndexManager (for script scanning)
- Shared.Constants

---

### 5. Planning (Thinking Before Acting)

**Responsibility:** Analyze tasks. Track intent. Trigger reflection.

**Interface:**
```lua
local Planning = require(src.Planning)

-- Task Analysis
local analysis = Planning.TaskPlanner.analyzeTask("Create a complete shop system")
-- Returns: { 
--   complexity = "complex", 
--   estimatedSteps = 8,
--   capabilities = {"ui_creation", "script_editing", "data_management"},
--   shouldPlan = true 
-- }

-- Intent Tracking
Planning.TaskPlanner.setIntent("Create a shop", analysis)
Planning.TaskPlanner.getIntentReminder() -- For error recovery
Planning.TaskPlanner.onError("Script not found")
Planning.TaskPlanner.completeIntent(true, "Created shop system")

-- Tool Call Tracking
Planning.TaskPlanner.recordToolCall("create_instance", true)
Planning.TaskPlanner.getRecentFailureCount()

-- Verification
local checks = Planning.Verification.generateChecks("create_instance", args, result)
-- Returns verification steps to confirm change worked
```

**Dependencies:**
- Shared.Constants

---

### 6. Tools (Doing Things in Roblox)

**Responsibility:** Actually modify Roblox Studio. Read scripts. Create instances.

**Interface:**
```lua
local Tools = require(src.Tools)

-- Execute any tool
local result = Tools.execute("patch_script", {
    path = "ServerScriptService/PlayerData",
    search_content = "local health = 100",
    replace_content = "local health = 150",
})
-- Returns: { success = true } or { error = "..." }

-- Dangerous operations go through approval
local result = Tools.execute("delete_instance", { path = "..." })
-- Returns: { pending = true, operationId = "...", preview = {...} }

Tools.applyOperation(operationId)  -- After user approves
Tools.rejectOperation(operationId) -- If user rejects

-- Get tool definitions for LLM
local definitions = Tools.getDefinitions()
```

**Dependencies:**
- Shared.Utils (for path resolution)
- Roblox services (game, HttpService, ChangeHistoryService)

---

### 7. Coordination (Orchestrating Everything)

**Responsibility:** Lifecycle management. Reset state at right times. Wire everything together.

**Interface:**
```lua
local Coordination = require(src.Coordination)

-- Session lifecycle
Coordination.Session.onConversationStart()
Coordination.Session.onConversationEnd()

-- Task lifecycle  
local analysis = Coordination.Session.onNewTask("Create a health bar")
Coordination.Session.onTaskComplete(true, "Created health bar")

-- Tool lifecycle hooks
Coordination.Session.beforeToolExecution("patch_script", args)
Coordination.Session.afterToolExecution("patch_script", args, success, result)
```

**What it does internally:**
- Calls Memory.Working.clear() on conversation start
- Calls Safety.CircuitBreaker.forceReset() on new task
- Calls Memory.Decision.endSequence() on task complete
- etc.

**Dependencies:** Everything (but just for coordination, not business logic)

---

## Dependency Graph (Clean Version)

```
                    ┌─────────────────┐
                    │   Main.lua      │
                    │  (Entry Point)  │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Coordination   │
                    │ (SessionManager)│
                    └────────┬────────┘
                             │ orchestrates
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
   ┌──────────┐        ┌──────────┐        ┌──────────┐
   │   Core   │        │  Memory  │        │    UI    │
   │(Loop/API)│        │(3 stores)│        │          │
   └────┬─────┘        └──────────┘        └──────────┘
        │
        │ uses
        ▼
   ┌──────────┐        ┌──────────┐        ┌──────────┐
   │  Safety  │◄───────│ Context  │        │ Planning │
   │(4 guards)│        │(selector)│        │ (planner)│
   └────┬─────┘        └──────────┘        └──────────┘
        │
        │ wraps
        ▼
   ┌──────────┐
   │  Tools   │
   │(executor)│
   └────┬─────┘
        │
        ▼
   ┌──────────┐
   │  Shared  │
   │ (utils)  │
   └──────────┘
```

**Key insight:** Dependencies flow DOWN. Nothing below depends on things above.

---

## File-by-File Refactor Plan

### Phase 1: Create Structure (No Code Changes)
1. Create folder structure
2. Create init.lua files that re-export existing modules
3. Verify everything still works

### Phase 2: Split OpenRouterClient.lua (The Big One)
Current: 1489 lines doing 5 different things

Split into:
- `Core/AgenticLoop.lua` - The while(tools) loop (~400 lines)
- `Core/ApiClient.lua` - HTTP calls, token tracking (~300 lines)  
- `Core/ConversationHistory.lua` - History management, compression triggers (~200 lines)
- `Core/MessageConverter.lua` - Convert between internal/OpenAI formats (~150 lines)

### Phase 3: Split Tools.lua (69KB!)
Current: One massive file with all tool implementations

Split into:
- `Tools/ToolExecutor.lua` - Main execute() function, routing
- `Tools/ReadTools.lua` - get_script, get_instance, list_children, search_scripts
- `Tools/WriteTools.lua` - patch_script, edit_script, create_script, create_instance
- `Tools/ProjectTools.lua` - discover_project, get_project_context, update_project_context
- `Tools/ApprovalQueue.lua` - Pending operations, apply/reject

### Phase 4: Move Files to Folders
Move existing files into their new homes:
- CircuitBreaker.lua → Safety/
- OutputValidator.lua → Safety/
- ErrorAnalyzer.lua → Safety/
- etc.

### Phase 5: Update Requires
Change all `require(script.Parent.X)` to new paths.

### Phase 6: Simplify SessionManager
Currently does too much. After refactor, it should ONLY:
- Call lifecycle hooks on other modules
- Not contain any business logic itself

---

## Extractable Libraries (For Your GitHub)

After refactor, these can become standalone packages:

### 1. `llm-circuit-breaker`
- Just CircuitBreaker.lua
- Port to TypeScript/Python
- Zero dependencies

### 2. `agent-working-memory`  
- WorkingMemory.lua
- The tiered decay system
- Port to TypeScript/Python

### 3. `context-compressor`
- CompressionFallback.lua
- Multi-strategy compression
- Port to TypeScript/Python

### 4. `llm-error-recovery`
- ErrorAnalyzer.lua
- Pattern matching + adaptive recovery
- Port to TypeScript/Python

### 5. `resilient-tool-layer`
- ToolResilience.lua
- Retry logic + health monitoring
- Port to TypeScript/Python

### 6. `agentic-planner`
- TaskPlanner.lua
- Complexity analysis + intent tracking
- Port to TypeScript/Python

---

## How to Read the Codebase After Refactor

**"I want to understand the main loop"**
→ Open `Core/AgenticLoop.lua`

**"I want to understand how errors are handled"**  
→ Open `Safety/` folder, read each file

**"I want to understand what context the LLM sees"**
→ Open `Context/PromptBuilder.lua`

**"I want to add a new tool"**
→ Add to `Tools/ReadTools.lua` or `Tools/WriteTools.lua`
→ Add schema to `Tools/ToolDefinitions.lua`

**"I want to improve memory management"**
→ Open `Memory/` folder, each file is independent

---

## Next Steps

1. Do you want me to start Phase 1 (create structure)?
2. Or should we first extract one system as a standalone library to prove the concept?
3. Or do you want to review/modify this plan first?

The refactor can be done incrementally - each phase results in working code.
