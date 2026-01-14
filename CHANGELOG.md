# Changelog

## [2026-01-13] v2.0.5 - Critical Bug Fix - Plugin Loading Error

### Fixed
- **Plugin disappearing after restart** - Added safe module loading with error recovery
- **Silent failures** - Plugin now ALWAYS shows toolbar button, even when modules fail to load
- **Unhelpful errors** - Added detailed error UI when plugin fails to initialize
- **Module validation** - Added checks to detect corrupted plugin structure before loading

### Technical Details
- Wrapped all module requires in `pcall` to catch initialization errors
- Created fallback error toolbar when loading fails
- Added module structure validation (checks for missing/wrong type modules)
- Improved error messages to help users diagnose issues

### For Users
If plugin fails to load, you'll now see a "Lux Error" button instead of nothing. Click it for troubleshooting steps.

---

## [2026-01-13] Architecture Refactor

### Major Changes
- **Modular architecture**: Reorganized flat `/src` structure into logical modules (Core, Memory, Safety, Context, Planning, Tools, Coordination, UI, Shared)
- **OpenRouterClient split**: Broke down 1489-line god object into focused modules:
  - `Core/AgenticLoop.lua` - Main agentic loop
  - `Core/ApiClient.lua` - HTTP calls and API communication
  - `Core/ConversationHistory.lua` - Message history management
  - `Core/MessageConverter.lua` - Format conversions
- **Tools module split**: Separated large Tools.lua into specialized files:
  - `Tools/ToolExecutor.lua` - Execution routing
  - `Tools/ReadTools.lua` - Read operations (get_script, list_children, etc.)
  - `Tools/WriteTools.lua` - Write operations (patch_script, create_instance, etc.)
  - `Tools/ProjectTools.lua` - Project discovery and context
  - `Tools/ApprovalQueue.lua` - Approval workflow
  - `Tools/ToolDefinitions.lua` - Tool schemas
- **Clean dependencies**: Dependencies now flow downward with clear module boundaries
- **Module structure**: Each module has init.lua exporting public interface

### New Modules
- **Core**: Engine for agentic loop, API calls, conversation history
- **Memory**: WorkingMemory, DecisionMemory, ProjectContext
- **Safety**: CircuitBreaker, OutputValidator, ErrorAnalyzer, ErrorPredictor, ToolResilience
- **Context**: ContextSelector, SystemPrompt, CompressionFallback
- **Planning**: TaskPlanner, Verification
- **Coordination**: SessionManager for lifecycle orchestration
- **UI**: Builder, ChatRenderer, InputApproval, KeySetup, UserFeedback, Components
- **Shared**: Constants, Utils, IndexManager, MarkdownParser

### Benefits
- Improved code organization and maintainability
- Clear separation of concerns
- Easier to understand and modify individual systems
- Foundation for extracting standalone libraries
- Better testability with isolated modules
