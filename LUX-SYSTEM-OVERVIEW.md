# Lux Agentic AI System - Complete Workflow Overview

## Executive Summary

Lux is a sophisticated agentic AI system embedded in Roblox Studio that enables users to code and manage their games through natural language. The system implements a complete loop where an AI agent iteratively thinks, executes tools, handles user approvals, and learns from past decisions. The architecture is modular, resilient, and safety-focused, with multiple layers of safeguards to prevent errors and ensure user control.

**Key Insight**: The system flow is NOT a simple one-shot LLM query. It's a continuous **agentic loop** where the AI plans, executes tools, handles approvals, learns, and iterates until the user's request is satisfied.

---

## 1. Entry Point & Initialization Flow

### Plugin Bootstrap (Main.lua)

The system starts when a user clicks the Lux toolbar button in Roblox Studio.

**Flow**:
1. **Plugin Load** → Main.lua initializes
   - Loads all 8 major subsystems (Core, Memory, Safety, Context, Planning, Tools, Coordination, UI, Shared)
   - Creates toolbar button and dock widget UI container
     - **Widget Position**: Yes! Configurable via `Enum.InitialDockState` in Main.lua (currently set to `.Right`)
     - **Widget Size**: Yes! Configured in [Constants.lua](src/Shared/Constants.lua):
       - `WIDGET_DEFAULT_WIDTH = 400`, `WIDGET_DEFAULT_HEIGHT = 600`
       - `WIDGET_MIN_WIDTH = 300`, `WIDGET_MIN_HEIGHT = 400`
   - Initializes OpenRouterClient with plugin instance for secure API key storage

2. **State Management Initialization**
   ```
   state = {
     sessionId, status, chatMessages, pendingChanges,
     creditBalance, chatEnabled, isProcessing, ...
   }
   ```

3. **Widget Creation** → Roblox DockWidgetPluginGui
   - Default state: Right-docked, hidden until user clicks button

4. **Event Connections**
   - Button click → Toggle widget visibility
   - Widget enabled → Trigger initialization sequence

### Widget Enabled Initialization Sequence

When widget is enabled (user opens it):

```
Widget Opened
    ↓
checkAndSetupAPI()  ← Validates OpenRouter API key
    ├─ If not configured → Show KeySetup modal
    │   └─ User enters key → Validate with OpenRouter → Save to plugin settings
    └─ If configured → Continue
        ↓
    scanAndUpdateUI()  ← Index all scripts in game
        ├─ IndexManager.scanScripts() → Find all scripts recursively
        ├─ Check count against Constants.MAX_SCRIPTS (100)
        └─ Update UI status (empty, ready, error, etc.)
        ↓
    OpenRouterClient.onSessionStart()  ← Session initialization
        ├─ SessionManager.onConversationStart()
        │   ├─ Clear ErrorAnalyzer history (transient state)
        │   ├─ Clear TaskPlanner session (transient state)
        │   ├─ Reset CircuitBreaker, ErrorPredictor
        │   ├─ Load ProjectContext (persisted knowledge)
        │   └─ Load DecisionMemory (learned patterns)
        └─ Initialize ToolResilience metrics
        ↓
    refreshCreditBalance()  ← Fetch account balance from OpenRouter
        ↓
    UI Ready for Chat
```

---

## 2. User Message Flow Through the System

### Message Submission (User sends message)

```
User types message and presses Enter/Send
    ↓
sendChatMessage(message)
    ├─ Validate: message not empty, not processing already
    ├─ Rate limit check (ENABLE_COOLDOWN guard)
    ├─ ChatRenderer.addMessage(state, "user", message) → Display in UI
    ├─ Reset state: lastShownThinkingText, isProcessing flag
    └─ Disable input UI (prevent double-send)
        ↓
    task.spawn(async processing function)
        ├─ OpenRouterClient.resetToolLog() → Clear previous task's tool tracking
        ├─ ChatRenderer.showThinking(state) → Display "AI is thinking..." animation
        ├─ Determine if new or continuation:
        │   ├─ If first message → OpenRouterClient.startConversation(message)
        │   └─ If continuing → OpenRouterClient.continueConversation(message)
        └─ → Enter Agentic Loop (see section 3)
```

### Inside OpenRouterClient.startConversation/continueConversation

Before the agentic loop begins, the system builds context:

```
Message received
    ↓
SystemPrompt.buildComplete(message, context_modules)
    ├─ Base prompt (core directives about how AI should work)
    ├─ Tool guidance (which tools to use and when)
    ├─ Adaptive sections based on:
    │   ├─ TaskPlanner.analyzeTask(message) → Complexity, capabilities needed
    │   ├─ DecisionMemory.getSimilarPatterns(message) → Past solutions
    │   ├─ ContextSelector.selectRelevantScripts(message) → Important scripts
    │   ├─ ProjectContext.formatForPrompt() → Persisted domain knowledge
    │   └─ ErrorAnalyzer.getRecentErrors() → What failed recently
    └─ → Complete system prompt tailored to this task
        ↓
ConversationHistory.addMessage({ role: "user", text: message })
    ├─ Add user message to conversation history array
    └─ Will be converted to OpenAI format before API call
        ↓
AgenticLoop.processLoop(statusCallback, chatRenderer, callOpenRouterAPI)
    └─ → BEGIN AGENTIC LOOP
```

---

## 3. The Agentic Loop - Iterative Tool Execution

This is the CORE of the system. The loop continues until the AI decides it's done or needs user input.

### Loop Structure (AgenticLoop.lua)

```
AGENTIC LOOP (iteration 1, 2, 3, ...)
    ↓
continueLoopFromIteration(currentIteration, statusCallback, chatRenderer)
    ├─ Check iteration limit (Constants.MAX_AGENT_ITERATIONS = 50)
    ├─ ConversationHistory.compressIfNeeded() → Token management
    └─ statusCallback(iteration, "thinking") → Update UI progress
        ↓
    callOpenRouterAPI(ConversationHistory.getHistory())
        ├─ Build request with:
        │   ├─ System prompt (adaptive, built above)
        │   ├─ Conversation history (all previous turns)
        │   ├─ Tool definitions (ToolDefinitions.lua)
        │   └─ Generation config (temperature=1.0, maxTokens=8192)
        └─ → OpenRouter API returns response with:
            ├─ text (thinking/planning text)
            └─ functionCalls (array of tool calls)

        ↓
    Parse response:
        ├─ Extract functionCalls array
        ├─ Extract text (thinking/narration)
        └─ ConversationHistory.addMessage({ role: "model", parts })

        ↓
    If NO functionCalls:
        └─ Return { success: true, text: response }  ← Task complete!
            ↓
            handleAgentResponse() → Display final text to user

        ↓
    If functionCalls exist:
        └─ processToolBatch(1, batchContext)  ← Execute tools
```

### Tool Batch Processing

```
processToolBatch(startIndex, context)
    │
    For each functionCall in batch:
    │   ├─ Update UI: statusCallback(iteration, "executing_" .. toolName)
    │   │
    │   ├─ PRE-EXECUTION SAFETY CHECKS:
    │   │   ├─ SessionManager.beforeToolExecution()
    │   │   │   └─ CircuitBreaker.canExecute() → Has circuit opened? (too many failures)
    │   │   ├─ OutputValidator.validateToolCall()
    │   │   │   ├─ Check required fields present
    │   │   │   ├─ Check for hallucinated paths
    │   │   │   ├─ Check for placeholder text (TODO, FIXME, etc.)
    │   │   │   └─ Return suggestions if invalid
    │   │   └─ ErrorPredictor.checkWarnings()
    │   │       └─ Warn if pattern matches known failures
    │   │
    │   ├─ TOOL EXECUTION (if validation passed):
    │   │   ├─ Display tool intent (for user visibility)
    │   │   │   └─ chatRenderer.addThought(intent, "tool")
    │   │   ├─ ToolResilience.executeResilient() → Execute with auto-retry
    │   │   │   ├─ Try tool.execute(toolName, args)
    │   │   │   ├─ If retryable error → exponential backoff retry
    │   │   │   └─ Return result
    │   │   └─ Display tool result (for user visibility)
    │   │       └─ chatRenderer.addThought(result, "result")
    │   │
    │   ├─ POST-EXECUTION TRACKING:
    │   │   ├─ SessionManager.afterToolExecution()
    │   │   │   ├─ Update CircuitBreaker state
    │   │   │   └─ Update ErrorPredictor patterns
    │   │   ├─ TaskPlanner.recordToolCall()
    │   │   ├─ DecisionMemory.recordTool()
    │   │   └─ ConversationHistory.recordToolExecution()
    │   │
    │   ├─ APPROVAL CHECK (for dangerous operations):
    │   │   ├─ If DANGEROUS_OPERATIONS[toolName] and result.pending:
    │   │   │   ├─ Save pausedState { type: "batch_paused", currentIndex, context }
    │   │   │   ├─ Return { awaitingApproval: true, operation: {...} }
    │   │   │   └─ PAUSE LOOP: Show approval UI to user
    │   │   │
    │   │   └─ If FEEDBACK_OPERATIONS[toolName] and result.awaitingFeedback:
    │   │       ├─ Save pausedState { type: "feedback_paused", feedbackRequest }
    │   │       ├─ Return { awaitingUserFeedback: true, feedbackRequest: {...} }
    │   │       └─ PAUSE LOOP: Show feedback UI to user
    │   │
    │   └─ Add result to functionResponses array
    │       └─ ConversationHistory.addMessage({ role: "user", parts: functionResponses })
    │
    └─ After all tools in batch:
        └─ Return continueLoopFromIteration(iteration + 1, ...)
            ↓
            LOOP CONTINUES (or pauses for approval)
```

---

## 4. Approval & Feedback Handling

The agentic loop can PAUSE to wait for user input instead of executing dangerous operations automatically.

### Approval Flow (when tool needs approval)

```
Tool returns with pending operation
    ↓
handleAgentResponse({ awaitingApproval: true, operation: {...} })
    ├─ Show AI's thinking text first (context for user)
    │   └─ ChatRenderer.addMessage(state, "assistant", thinkingText)
    ├─ Start collapsible system group (for batching)
    │   └─ ChatRenderer.startCollapsibleSystemGroup(state, "Creating X")
    └─ handleApproval(operation) → Show inline approval prompt
        ├─ InputApproval.show(inputContainer, operation, approved_callback, denied_callback)
        │   ├─ Display operation icon, description, and code preview
        │   └─ Show "Approve" and "Deny" buttons
        │
        └─ User clicks Approve/Deny
            │
            APPROVE PATH:
            ├─ InputApproval.hide()
            ├─ ChatRenderer.addCollapsibleSystemItem(description, "success")
            ├─ OpenRouterClient.recordToolExecution() → Track for summary
            └─ AgenticLoop.resumeWithApproval(true)
                ├─ Tools.applyOperation(operationId) → Actually execute the tool now
                └─ Return continueLoopFromIteration(currentIndex + 1, ...)
                    └─ Process remaining tools in batch or next iteration

            DENY PATH:
            ├─ InputApproval.hide()
            ├─ ChatRenderer.addCollapsibleSystemItem(description, "error")
            ├─ OpenRouterClient.recordToolExecution() → Track as failed
            ├─ Tools.rejectOperation(operationId) → Mark as rejected
            └─ AgenticLoop.resumeWithApproval(false)
                ├─ Return error to AI with "User denied this operation"
                └─ Continue loop - AI responds to denial
```

### Feedback Flow (when AI asks user to verify)

```
Tool requests user feedback (e.g., "Does this look correct?")
    ↓
handleAgentResponse({ awaitingUserFeedback: true, feedbackRequest: {...} })
    ├─ Show AI's context text first
    └─ handleUserFeedbackRequest(feedbackRequest)
        ├─ UserFeedback.showInChat(state, feedbackRequest, callback)
        │   ├─ Display question in chat
        │   └─ Show response buttons (positive/negative/details)
        │
        └─ User responds
            ├─ OpenRouterClient.resumeWithFeedback({ positive, feedback })
            ├─ Build feedbackResult with interpretation hint for AI
            └─ AgenticLoop.resumeWithFeedback(feedbackResponse)
                ├─ Add feedback to conversation history
                └─ Return continueLoopFromIteration(currentIndex + 1, ...)
```

---

## 5. Memory Systems

The system has multiple memory layers that enable learning and context management.

### Conversation History (Core Memory)

**Module**: [ConversationHistory.lua](src/Core/ConversationHistory.lua)

- **conversationHistory[]** array - Messages: `{ role: "user"|"model"|"assistant", parts: [...] }`
- **toolExecutionLog{}** - Tracks which tools executed
- **Operations**: addMessage, getHistory, resetConversation, compressIfNeeded, recordToolExecution

**Lifecycle**: Created new on each conversation start, persists across multiple user messages until reset.

### Working Memory (Context Decay)

**Module**: [WorkingMemory.lua](src/Memory/WorkingMemory.lua)

Three tiers:
- **CRITICAL**: User goals (never evicted)
- **WORKING**: Recent tool results (decay over time)
- **BACKGROUND**: Compressed summaries

**Relevance decay**: halfLife = 300 seconds (recent context is much more valuable)

**Purpose**: Ensures old context doesn't overwhelm new information, prevents token bloat.

### Decision Memory (Learning)

**Module**: [DecisionMemory.lua](src/Memory/DecisionMemory.lua)

- Learns from executed tool sequences
- **patterns.successful[]** - Tool sequences that worked
- **patterns.failed[]** - Patterns that failed
- **currentSequence** - Being recorded now

**Operations**: startSequence, recordTool, endSequence, getSimilarPatterns, save/load

**Persistence**: Saved to `ReplicatedStorage.LuxMemory`, survives session restart.

### Project Context (Domain Knowledge)

**Module**: [ProjectContext.lua](src/Memory/ProjectContext.lua)

Stores validated game architecture notes with anchors:
```
entries[] → {
  text: "The combat system uses...",
  type: "architecture|convention|warning|dependency",
  anchor: {
    type: "script_exists|script_contains|...",
    target: "ScriptName" or pattern
  },
  validated: boolean,
  stale: boolean
}
```

**Purpose**: Gives AI persistent knowledge about game architecture across sessions.

---

## 6. Safety Mechanisms & When They Trigger

The system has 5 layers of safety to prevent runaway agents and broken states.

### Circuit Breaker (Hard Stop)

**Module**: [CircuitBreaker.lua](src/Safety/CircuitBreaker.lua)

- **States**: CLOSED (normal) → OPEN (blocked) → HALF_OPEN (testing)
- **Config**: failureThreshold = 5 consecutive failures, cooldownPeriod = 30 seconds
- **Trigger**: After 5 consecutive tool failures, circuit opens and blocks further execution
- **Recovery**: After cooldown, enters HALF_OPEN state for single retry attempt

**Example**: If get_script fails 5 times in a row (invalid paths), circuit opens. AI must acknowledge and try a different approach.

### Output Validator (Pre-Execution)

**Module**: [OutputValidator.lua](src/Safety/OutputValidator.lua)

Validates tool calls BEFORE execution:
- Required fields present
- Paths exist in game
- No placeholders (TODO, FIXME, <name>, "INSERT HERE")
- Basic Lua syntax checking
- Suspicious patterns detection

**Example**: AI tries `patch_script({path: "Workspace.Unknown", ...})` but Workspace.Unknown doesn't exist. Validator catches it, AI learns to check first with list_children.

### Error Analyzer & Predictor (Learning Safety)

**Modules**: [ErrorAnalyzer.lua](src/Safety/ErrorAnalyzer.lua), [ErrorPredictor.lua](src/Safety/ErrorPredictor.lua)

**ErrorAnalyzer** classifies errors intelligently:
- missing_resource → "Path not found - verify with list_children"
- syntax_error → "Malformed code - re-read and check brackets"
- property_error → "Invalid property - use get_instance to check"
- already_exists → "Item already created - modify or delete first"

**ErrorPredictor** detects patterns BEFORE failures:
- Tracks tool success/failure rates
- Detects error patterns in sequence
- Identifies potential loops (same action repeating)

### Tool Resilience (Auto-Healing)

**Module**: [ToolResilience.lua](src/Safety/ToolResilience.lua)

Wraps every tool execution with resilience:
- Automatic retry with exponential backoff (100ms → 500ms → give up)
- State sync detection
- Output validation and sanitization
- Health monitoring and anomaly tracking

**Example**: Network hiccup causes get_script to timeout. Resilience auto-retries after 100ms, succeeds.

### Approval Requirement (User Safeguard)

**Dangerous operations** require user approval:
- patch_script, edit_script, create_script
- create_instance, set_instance_properties
- delete_instance

Loop PAUSES until user approves or denies the operation.

---

## 7. Context Building & Prompt Construction

The system prompt is NOT static. It's dynamically built for each API call with relevant context.

### System Prompt Construction

**Module**: [SystemPrompt.lua](src/Context/SystemPrompt.lua)

```
SystemPrompt.buildComplete(userMessage, context_modules)
    │
    ├─ BASE_PROMPT (always included):
    │   ├─ Core directives (plan first, narrate work, read before edit)
    │   ├─ Communication style requirements
    │   ├─ Transparency protocol (tools are shown to user)
    │   └─ Tool reference (which tools to use)
    │
    ├─ ADAPTIVE SECTIONS:
    │   ├─ Task analysis (complexity, capabilities needed)
    │   ├─ Decision memory (past solutions that worked)
    │   ├─ Project context (game architecture notes)
    │   ├─ Error recovery (recent failures to avoid)
    │   ├─ Script context (relevant scripts in game)
    │   └─ Working memory (active context)
    │
    └─ Result: Highly contextualized prompt for this specific moment
```

### Context Selector (Reducing Token Usage)

**Module**: [ContextSelector.lua](src/Context/ContextSelector.lua)

- **Problem**: Dumping all scripts into every prompt wastes tokens
- **Solution**: Select only RELEVANT scripts

**Selection strategy**:
- Extract keywords from user message
- Score scripts by keyword match
- Boost recently edited scripts
- Boost recently read scripts
- Return top N scripts by score

**Benefit**: For a 100-script game, might include only 10-15 most relevant ones, saving 40% of context tokens.

---

## 8. Tool Execution Flow

Tools are the "hands" of the AI. They're the only way the AI can inspect or modify the game.

### Tool Categories

**READ TOOLS** (Safe, instant):
- get_script, get_instance, list_children
- get_descendants_tree, search_scripts

**WRITE TOOLS** (Dangerous, require approval):
- patch_script, edit_script, create_script
- create_instance, set_instance_properties, delete_instance

**PROJECT TOOLS**:
- request_user_feedback

### Tool Execution Pipeline

```
AgenticLoop.processToolBatch():
    For tool in batch:
        │
        ├─ 1. PRE-EXECUTION
        │   ├─ SessionManager.beforeToolExecution(toolName)
        │   ├─ OutputValidator.validateToolCall()
        │   └─ ErrorPredictor.getWarning()
        │
        ├─ 2. DISPLAY INTENT (for user visibility)
        │   └─ chatRenderer.addThought(formatToolIntent(...), "tool")
        │
        ├─ 3. EXECUTE
        │   └─ ToolResilience.executeResilient(Tools.execute, toolName, args)
        │       ├─ Try 1: Tools.execute(toolName, args)
        │       ├─ If fails and retryable → Try 2 after 100ms delay
        │       └─ If fails and not retryable → Return error
        │
        ├─ 4. DISPLAY RESULT
        │   └─ chatRenderer.addThought(formatToolResult(...), "result")
        │
        ├─ 5. TRACK EXECUTION
        │   ├─ SessionManager.afterToolExecution()
        │   ├─ TaskPlanner.recordToolCall()
        │   ├─ DecisionMemory.recordTool()
        │   └─ ConversationHistory.recordToolExecution()
        │
        ├─ 6. CHECK FOR APPROVAL NEEDED
        │   ├─ If dangerous and result.pending → PAUSE LOOP
        │   └─ If feedback needed → PAUSE LOOP
        │
        └─ 7. ADD RESULT TO HISTORY
            └─ ConversationHistory.addMessage({ role: "user", parts: [functionResponse] })
```

### Approval Queue Management

**Module**: [ApprovalQueue.lua](src/Tools/ApprovalQueue.lua)

Maintains queue of pending operations:
```
operations: {
  id: number (unique),
  type: string (patch_script, create_instance, etc.),
  status: "pending" | "approved" | "rejected",
  data: table (args from tool call),
  timestamp: number,
  result: table (after approval)
}
```

**Lifecycle**:
- Tool returns pending result → queue() stores it
- User clicks Approve → Tools.applyOperation(operationId) executes it
- User clicks Deny → Tools.rejectOperation(operationId) marks rejected

---

## 9. Error Handling & Recovery

The system is designed to recover gracefully from failures.

### Error Categories & Recovery

```
Error occurs during tool execution:
    │
    ├─ ErrorAnalyzer.analyzeError(error) → Classify error
    │   ├─ Category: missing_resource
    │   │   └─ Recovery: "Verify path with get_instance or list_children"
    │   ├─ Category: syntax_error
    │   │   └─ Recovery: "Re-read script, check for missing 'end' or brackets"
    │   ├─ Category: property_error
    │   │   └─ Recovery: "Use get_instance to verify properties, check types"
    │
    ├─ Error returned to AI with analysis
    │
    └─ AI decides next action:
        ├─ Simple error → Auto-retry with fix
        └─ Persistent error → Ask user for help
```

### Resilience & Retry Logic

```
ToolResilience.executeResilient() wraps every tool:

Try 1: Tool execution
    ├─ If success → Return result
    ├─ If retryable error (timeout, connection) → Wait 100ms, Try 2
    └─ If non-retryable error → Return error

Try 2: Tool execution (after 100ms)
    ├─ If success → Return result, increment autoRecoveredCount
    ├─ If retryable error → Wait 500ms, Try 3
    └─ If non-retryable error → Return error

Try 3: Tool execution (after 500ms)
    ├─ If success → Return result
    └─ If any error → Return error (gave up after 3 tries)
```

---

## 10. Session Lifecycle

The system manages state across three scopes to prevent leaks.

### Session Scopes

**PERSISTED STATE** (Survives session restart):
- ProjectContext (game architecture notes) → ReplicatedStorage.LuxContext
- DecisionMemory (learned tool patterns) → ReplicatedStorage.LuxMemory

**SESSION-SCOPED STATE** (Cleared on conversation reset):
- ConversationHistory, ErrorAnalyzer history, TaskPlanner session
- ContextSelector cache, WorkingMemory, CircuitBreaker state

**TASK-SCOPED STATE** (Cleared on each new user message):
- pausedState (approval/feedback pause data)
- toolExecutionLog (for current task's completion summary)

### Conversation Lifecycle

```
USER OPENS PLUGIN:
    ├─ Check API key configured → KeySetup modal if not
    ├─ SessionManager.onConversationStart()
    │   ├─ Clear all transient state
    │   ├─ Load ProjectContext from storage
    │   ├─ Load DecisionMemory from storage
    │   └─ Initialize ToolResilience metrics
    └─ Chat ready

USER SENDS MESSAGE:
    ├─ Build adaptive system prompt
    ├─ Add message to ConversationHistory
    └─ Start agentic loop (iteration 1, 2, 3, ...)
        └─ SessionManager.onTaskComplete(success, summary)

USER CLICKS RESET BUTTON:
    ├─ Show confirmation dialog
    └─ Clear chat UI and ConversationHistory
        └─ SessionManager.onConversationEnd()
```

---

## 11. Major Modules - Quick Reference

### Core Modules (Engine)
| Module | Purpose | Location |
|--------|---------|----------|
| **AgenticLoop.lua** | Main agentic loop iteration | [src/Core/AgenticLoop.lua](src/Core/AgenticLoop.lua) |
| **ApiClient.lua** | HTTP communication with OpenRouter | [src/Core/ApiClient.lua](src/Core/ApiClient.lua) |
| **ConversationHistory.lua** | Conversation state | [src/Core/ConversationHistory.lua](src/Core/ConversationHistory.lua) |
| **MessageConverter.lua** | Format conversion | [src/Core/MessageConverter.lua](src/Core/MessageConverter.lua) |

### Memory Modules (Learning)
| Module | Purpose | Location |
|--------|---------|----------|
| **WorkingMemory.lua** | Active context with decay | [src/Memory/WorkingMemory.lua](src/Memory/WorkingMemory.lua) |
| **DecisionMemory.lua** | Tool pattern learning | [src/Memory/DecisionMemory.lua](src/Memory/DecisionMemory.lua) |
| **ProjectContext.lua** | Game architecture notes | [src/Memory/ProjectContext.lua](src/Memory/ProjectContext.lua) |

### Safety Modules (Protection)
| Module | Purpose | Location |
|--------|---------|----------|
| **CircuitBreaker.lua** | Hard stop on failure spiral | [src/Safety/CircuitBreaker.lua](src/Safety/CircuitBreaker.lua) |
| **OutputValidator.lua** | Pre-execution validation | [src/Safety/OutputValidator.lua](src/Safety/OutputValidator.lua) |
| **ErrorAnalyzer.lua** | Error classification | [src/Safety/ErrorAnalyzer.lua](src/Safety/ErrorAnalyzer.lua) |
| **ErrorPredictor.lua** | Proactive warning system | [src/Safety/ErrorPredictor.lua](src/Safety/ErrorPredictor.lua) |
| **ToolResilience.lua** | Auto-retry and healing | [src/Safety/ToolResilience.lua](src/Safety/ToolResilience.lua) |

### Context Modules (Adaptation)
| Module | Purpose | Location |
|--------|---------|----------|
| **SystemPrompt.lua** | Dynamic prompt building | [src/Context/SystemPrompt.lua](src/Context/SystemPrompt.lua) |
| **ContextSelector.lua** | Relevant script selection | [src/Context/ContextSelector.lua](src/Context/ContextSelector.lua) |
| **CompressionFallback.lua** | Token management fallback | [src/Context/CompressionFallback.lua](src/Context/CompressionFallback.lua) |

### Planning Modules (Thinking)
| Module | Purpose | Location |
|--------|---------|----------|
| **TaskPlanner.lua** | Task analysis and planning | [src/Planning/TaskPlanner.lua](src/Planning/TaskPlanner.lua) |
| **Verification.lua** | Self-verification system | [src/Planning/Verification.lua](src/Planning/Verification.lua) |

### Tool Modules (Execution)
| Module | Purpose | Location |
|--------|---------|----------|
| **ToolExecutor.lua** | Tool routing and formatting | [src/Tools/ToolExecutor.lua](src/Tools/ToolExecutor.lua) |
| **ReadTools.lua** | Read-only operations | [src/Tools/ReadTools.lua](src/Tools/ReadTools.lua) |
| **WriteTools.lua** | Modification operations | [src/Tools/WriteTools.lua](src/Tools/WriteTools.lua) |
| **ProjectTools.lua** | Project discovery | [src/Tools/ProjectTools.lua](src/Tools/ProjectTools.lua) |
| **ApprovalQueue.lua** | Approval management | [src/Tools/ApprovalQueue.lua](src/Tools/ApprovalQueue.lua) |
| **ToolDefinitions.lua** | Tool schemas | [src/Tools/ToolDefinitions.lua](src/Tools/ToolDefinitions.lua) |

### Coordination Module (Lifecycle)
| Module | Purpose | Location |
|--------|---------|----------|
| **SessionManager.lua** | State scope management | [src/Coordination/SessionManager.lua](src/Coordination/SessionManager.lua) |

### UI Modules (Presentation)
| Module | Purpose | Location |
|--------|---------|----------|
| **Builder.lua** | Main UI creation | [src/UI/Builder.lua](src/UI/Builder.lua) |
| **ChatRenderer.lua** | Chat message display | [src/UI/ChatRenderer.lua](src/UI/ChatRenderer.lua) |
| **InputApproval.lua** | Approval prompt UI | [src/UI/InputApproval.lua](src/UI/InputApproval.lua) |
| **UserFeedback.lua** | Feedback request UI | [src/UI/UserFeedback.lua](src/UI/UserFeedback.lua) |
| **KeySetup.lua** | API key entry modal | [src/UI/KeySetup.lua](src/UI/KeySetup.lua) |

### Shared Modules (Utilities)
| Module | Purpose | Location |
|--------|---------|----------|
| **Constants.lua** | Configuration | [src/Shared/Constants.lua](src/Shared/Constants.lua) |
| **Utils.lua** | Helper functions | [src/Shared/Utils.lua](src/Shared/Utils.lua) |
| **IndexManager.lua** | Script scanning | [src/Shared/IndexManager.lua](src/Shared/IndexManager.lua) |
| **MarkdownParser.lua** | Markdown → GUI | [src/Shared/MarkdownParser.lua](src/Shared/MarkdownParser.lua) |

### Entry Points
| Module | Purpose | Location |
|--------|---------|----------|
| **Main.lua** | Plugin entry point | [Main.lua](Main.lua) |
| **OpenRouterClient.lua** | Legacy orchestration wrapper | [src/OpenRouterClient.lua](src/OpenRouterClient.lua) |

---

## 12. System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER OPENS PLUGIN                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
   API KEY OK?                          KeySetup Modal
        │ ✓                              (save to plugin settings)
        │                                     │
        ▼                                     │
   Scan Scripts                              │
   Index all code                            │
        │                                     │
        ▼                                ┌────┴──────┐
   Load ProjectContext                   │ ✓ Saved   │
   Load DecisionMemory                   └───────────┘
   Load Session State                         │
        │◄────────────────────────────────────┘
        │
        ▼
   CHAT READY FOR INPUT
        │
        │ User sends message
        ▼
   ┌─────────────────────────────────────────────────────┐
   │  BUILD ADAPTIVE SYSTEM PROMPT                       │
   │  ├─ Base directives                                 │
   │  ├─ Task analysis (TaskPlanner)                     │
   │  ├─ Similar past solutions (DecisionMemory)         │
   │  ├─ Game architecture (ProjectContext)              │
   │  ├─ Recent errors (ErrorAnalyzer)                   │
   │  ├─ Relevant scripts (ContextSelector)              │
   │  └─ Active context (WorkingMemory)                  │
   └──────────────────────┬────────────────────────────────┘
                          │
                          ▼
   ┌──────────────────────────────────────────────────────┐
   │  AGENTIC LOOP (Iteration 1, 2, 3, ...)              │
   │                                                      │
   │  ┌─ Call OpenRouter API                             │
   │  │  ├─ Send: system prompt + history + tool defs    │
   │  │  └─ Receive: thinking text + functionCalls       │
   │  │                                                   │
   │  ├─ No function calls?                              │
   │  │  └─ Task complete! Return text                   │
   │  │                                                   │
   │  ├─ Has function calls?                             │
   │  │  ├─ For each tool:                               │
   │  │  │  │                                             │
   │  │  │  ├─ PRE-EXEC CHECKS                           │
   │  │  │  │ ├─ CircuitBreaker: Blocked?                │
   │  │  │  │ ├─ OutputValidator: Valid call?            │
   │  │  │  │ └─ ErrorPredictor: Pattern warning?        │
   │  │  │  │                                             │
   │  │  │  ├─ EXECUTE                                    │
   │  │  │  │ ├─ ToolResilience wrapper (auto-retry)     │
   │  │  │  │ ├─ ToolExecutor routes to:                 │
   │  │  │  │ │ ├─ ReadTools (safe)                      │
   │  │  │  │ │ └─ WriteTools (queued for approval)      │
   │  │  │  │ └─ Return result                            │
   │  │  │  │                                             │
   │  │  │  ├─ POST-EXEC TRACKING                        │
   │  │  │  │ ├─ SessionManager: Update metrics          │
   │  │  │  │ ├─ TaskPlanner: Record progress            │
   │  │  │  │ ├─ DecisionMemory: Learn patterns          │
   │  │  │  │ └─ ConversationHistory: Track execution    │
   │  │  │  │                                             │
   │  │  │  ├─ DANGEROUS OP?                             │
   │  │  │  │ ├─ Result has pending status?              │
   │  │  │  │ │ └─ PAUSE LOOP: Show approval UI          │
   │  │  │  │ │    ├─ User approves                      │
   │  │  │  │ │    │ └─ ApplyOperation → resume loop     │
   │  │  │  │ │    └─ User denies                        │
   │  │  │  │ │      └─ RejectOperation → resume loop    │
   │  │  │  │ └─ Else: Continue                          │
   │  │  │  │                                             │
   │  │  │  └─ Add result to history                      │
   │  │  │                                                 │
   │  │  └─ Next iteration (iteration + 1)               │
   │  │     └─ Add tool results to history                │
   │  │     └─ Call API again with new results            │
   │  │                                                   │
   │  └─ Loop condition: max 50 iterations               │
   │     On exceed → Error                                │
   │                                                      │
   └──────────────────────┬───────────────────────────────┘
                          │
                          ▼
   ┌──────────────────────────────────────────────────────┐
   │  COMPLETION                                          │
   │  ├─ Display final response text                      │
   │  ├─ Show completion summary (tools used)             │
   │  ├─ Add to ProjectContext/DecisionMemory if learned  │
   │  ├─ Re-enable input                                  │
   │  └─ SessionManager.onTaskComplete()                  │
   └──────────────────────┬───────────────────────────────┘
                          │
                          ▼
   ┌──────────────────────────────────────────────────────┐
   │  READY FOR NEXT MESSAGE (same conversation)          │
   │  ├─ Clear task-scoped state                          │
   │  ├─ Keep conversation history (for context)          │
   │  ├─ Keep persisted memory (ProjectContext, Decision) │
   │  └─ Go to "Build Adaptive System Prompt"             │
   └──────────────────────────────────────────────────────┘
```

---

## 13. Key Design Principles

### 1. Agent Autonomy with User Control
- AI can plan and execute many steps automatically
- Dangerous operations pause the loop and require explicit user approval
- User can deny operations without breaking the flow

### 2. Transparency Protocol
- All tool calls are displayed to the user in real-time
- User sees tool intent BEFORE execution
- User sees tool result AFTER execution
- Users can learn how the AI works by observing

### 3. Graceful Degradation
- Transient failures (network) auto-retry with backoff
- Persistent failures surface to AI with analysis
- AI learns from errors and tries different approaches
- Circuit breaker prevents infinite loops (hard stop at 5 failures)

### 4. Adaptive Context
- System prompt changes based on current task
- Only relevant scripts included (saves tokens)
- Recent failures mentioned to prevent repetition
- Past successful patterns suggested as templates

### 5. Modular Safety Layers
- 5 independent safety systems work together
- CircuitBreaker (hard stop), OutputValidator (pre-exec), Resilience (retry), Analyzer (learning), Predictor (warning)
- Failure in one layer doesn't break others
- Each layer has independent configuration

### 6. Memory Across Sessions
- ProjectContext persists game architecture knowledge
- DecisionMemory learns tool usage patterns
- Both survive session restart
- Anchored to real game structure for validation

### 7. Clear State Scoping
- Persisted state (ProjectContext, DecisionMemory)
- Session-scoped state (conversation history, error tracking)
- Task-scoped state (pause state, current execution)
- Prevents state pollution across tasks

---

## 14. Configuration Hotspots

**Agent behavior**:
- `Constants.MAX_AGENT_ITERATIONS = 50` - Stop looping after this many
- `Constants.COMPRESSION_THRESHOLD = 50000` - Compress history at token count

**Safety**:
- `CircuitBreaker.CONFIG.failureThreshold = 5` - Open circuit after 5 failures
- `CircuitBreaker.CONFIG.cooldownPeriod = 30` - Seconds before half-open

**Token management**:
- `Constants.GENERATION_CONFIG.maxOutputTokens = 8192` - Max output per call
- `WorkingMemory.CONFIG.halfLife = 300` - Seconds for context to decay
- `ContextSelector.FRESHNESS_CONFIG.staleThreshold = 300` - When script context is stale

**Memory**:
- `Constants.PROJECT_CONTEXT.maxEntries = 50` - Max stored architecture notes

**Features**:
- `Constants.ADAPTIVE_PROMPT.enabled = true` - Dynamic system prompt
- `Constants.PROJECT_CONTEXT.enabled = true` - Game architecture memory
- `Constants.PLANNING.enabled = true` - Task planning module

---

## Summary

Lux's agentic workflow is a sophisticated loop where:

1. **User sends message** → System builds adaptive context
2. **AI plans** → Analyzes task, recalls past solutions, considers game structure
3. **AI acts** → Executes tools with safety checks, pauses for approval when needed
4. **User reviews** → Approves/denies operations, provides feedback
5. **AI learns** → Records patterns, updates context, improves next iteration
6. **Loop continues** → Until task complete or user intervention needed
7. **Conversation context persists** → Multiple tasks in same session
8. **Knowledge survives** → ProjectContext and DecisionMemory persist across sessions

The system balances **autonomy** (AI can execute many steps) with **control** (user approves dangerous ops), **safety** (5 protection layers) with **efficiency** (context selection, token management), and **learnability** (patterns improve over time) with **transparency** (user sees everything).
