--[[
    Constants.lua
    All configuration constants for Lux plugin
]]

local Constants = {}

-- Plugin Identity
Constants.PLUGIN_NAME = "Lux"
Constants.PLUGIN_VERSION = "2.0.5"

-- OpenRouter Configuration
Constants.OPENROUTER_MODEL = "google/gemini-3-flash-preview" -- Main model (default)
Constants.SUMMARY_MODEL = "google/gemini-3-flash-preview" -- Summarization model

-- Available Models for selection
Constants.AVAILABLE_MODELS = {
	{
		id = "google/gemini-3-flash-preview",
		name = "Gemini 3 Flash",
		description = "Fast & affordable. Great for most tasks.",
		pricing = "$0.50/M input � $3/M output",
		isDefault = true
	},
	{
		id = "google/gemini-3-pro-preview",
		name = "Gemini 3 Pro",
		description = "Most capable. Best for complex tasks.",
		pricing = "$2/M input � $12/M output",
		isDefault = false
	}
}
Constants.OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
Constants.OPENROUTER_CREDITS_ENDPOINT = "https://openrouter.ai/api/v1/credits"
Constants.OPENROUTER_REFERER = "https://lux.sergestudios.com"
Constants.LOW_BALANCE_WARNING = 0.50

-- Debug Mode
Constants.DEBUG = false -- Set to true only for development

-- Timeouts
Constants.REQUEST_TIMEOUT = 120

-- Generation Config
Constants.GENERATION_CONFIG = {
	temperature = 1.0,
	maxOutputTokens = 8192,  -- Reduced for Gemini Flash compatibility (was 65536)
	-- Note: thinkingConfig is not used in API requests and is reserved for future thinking models
	thinkingConfig = {
		thinkingLevel = "low"
	}
}

-- Features
Constants.ENABLE_GOOGLE_SEARCH = false

-- Master switches
Constants.FEATURES = {
	projectContext = true,
	progressIndicator = true,
	webFetch = false, -- Disabled as requested
}

-- Project Context Configuration
Constants.PROJECT_CONTEXT = {
	enabled = true,
	storageName = "LuxContext",
	storageLocation = "ReplicatedStorage",
	maxEntries = 50,
	maxContentLength = 500,
	staleThresholdDays = 7,
	validateOnSessionStart = true,
}

Constants.CONTEXT_TYPES = { "architecture", "convention", "warning", "dependency" }

Constants.ANCHOR_TYPES = {
	"script_exists",
	"script_contains",
	"instance_exists",
	"service_has_child",
}


-- Script Limits
Constants.MAX_SCRIPTS = 100
Constants.SCRIPT_WARNING_THRESHOLD = 50
Constants.SCRIPT_LIST_MODE = "summary"

Constants.MAX_MESSAGE_LENGTH = 1000
Constants.CHAT_COOLDOWN_SECONDS = 0
Constants.ENABLE_COOLDOWN = false
Constants.THINKING_ANIMATION_INTERVAL = 0.5

-- Agent Loop Configuration
Constants.MAX_AGENT_ITERATIONS = 50
Constants.SHOW_ITERATION_PROGRESS = true
Constants.COMPRESSION_THRESHOLD = 50000 
Constants.MESSAGES_TO_PRESERVE = 10   

-- ============================================================================
-- AGENTIC INTELLIGENCE SETTINGS (v2.0)
-- ============================================================================

-- Task Planning
Constants.PLANNING = {
	enabled = true,
	analyzeBeforeExecution = true,         -- Analyze task complexity before starting
	maxPlanSteps = 20,                      -- Maximum steps in a plan
	reflectionInterval = 5,                 -- Self-reflect every N tool calls
	reflectionOnFailure = true,             -- Force reflection after any failure
	complexityThresholds = {
		simple = 1,    -- Fast keyword baseline
		medium = 3,    -- Fast keyword baseline
		complex = 999  -- Managed by AI override in v2.0
	},
	aiEscalationThreshold = 3 -- If AI generates > 3 steps, upgrade to complex
}

-- Context Selection
Constants.CONTEXT_SELECTION = {
	enabled = true,
	maxRelevantScripts = 20,              -- Max scripts to include in prompt
	keywordMatchingEnabled = true,         -- Use keyword matching for relevance
	includeRecentlyEdited = true,          -- Always include recently edited scripts
	recentEditWindowMinutes = 30,          -- How long "recently edited" lasts
}

-- Error Recovery
Constants.ERROR_RECOVERY = {
	enabled = true,
	maxRetries = 3,                        -- Max retries per tool
	backoffMultiplier = 1.5,               -- Exponential backoff multiplier
	classifyErrors = true,                 -- Enable error classification
	suggestRecovery = true,                -- Suggest recovery strategies
	autoRecoveryEnabled = false,           -- Experimental: auto-apply recovery (risky)
}

-- Verification
Constants.VERIFICATION = {
	enabled = true,
	verifyAfterCreate = true,              -- Verify after create_script/create_instance
	verifyAfterEdit = true,                -- Verify after edit_script/patch_script
	verifyUIHierarchy = true,              -- Check UI parent-child relationships
	syntaxCheckEnabled = true,             -- Basic Lua syntax validation (pattern-based)
}

-- Decision Memory (Learning from success/failure patterns)
Constants.DECISION_MEMORY = {
	enabled = true,
	maxPatterns = 100,                     -- Max patterns to store
	minSuccessRate = 0.7,                  -- Min success rate to recommend pattern
	decayDays = 7,                         -- Patterns decay after N days without use (reduced from 14)
	minKeywordMatches = 2,                 -- Require at least N keyword matches to suggest pattern
	requireCapabilityMatch = true,         -- Only suggest patterns with matching capabilities
	storageName = "LuxDecisionMemory",     -- StringValue name for persistence
}

-- Tool Intelligence
Constants.TOOL_INTELLIGENCE = {
	enabled = true,
	useCostAwareness = true,               -- Prefer cheaper tools when possible
	chainingSuggestionsEnabled = true,     -- Suggest follow-up tools
	toolCostTiers = {
		-- Tier 1: Read-only, fast, safe
		get_script = 1,
		get_instance = 1,
		list_children = 1,
		get_descendants_tree = 1,
		search_scripts = 1,
		get_project_context = 1,
		discover_project = 1,
		validate_context = 1,
		-- Tier 2: Write but low risk
		update_project_context = 2,
		set_instance_properties = 2,
		-- Tier 3: Create/modify (needs approval anyway)
		create_instance = 3,
		create_script = 3,
		patch_script = 3,
		edit_script = 3,
		delete_instance = 3,
	}
}

-- Adaptive System Prompt
Constants.ADAPTIVE_PROMPT = {
	enabled = true,
	includeComplexityGuidance = true,      -- Add guidance based on task complexity
	includeRecentFailures = true,          -- Emphasize error recovery if recent failures
	includeSessionHistory = true,          -- Add summary of what's been done this session
}

-- User Feedback / Verification (Interactive Testing)
Constants.USER_FEEDBACK = {
	enabled = true,
	maxPerConversationTurn = 1,            -- Max verification requests per user message
	minToolsBetween = 3,                   -- At least N tool calls between verifications
	cooldownSeconds = 30,                  -- Don't ask again within N seconds
	skipIfUserSaidUrgent = true,           -- Detect urgency keywords and skip verification

	-- Urgency keywords that suggest user doesn't want to be interrupted
	urgencyKeywords = {
		"just do it", "quick", "hurry", "asap", "immediately",
		"don't ask", "no questions", "just make", "skip"
	},

	-- Response presets for quick feedback
	quickResponses = {
		positive = { "Looks good!", "Works perfectly", "Yes, I see it" },
		negative = { "I don't see it", "Something's wrong", "Not working" },
	}
}

-- ============================================================================
-- INDEXING & WORLD MAP (v3.0)
-- ============================================================================

Constants.INDEXING = {
	-- Classes to scan beyond just scripts
	SCAN_CLASSES = {
		"Script", "LocalScript", "ModuleScript",
		"Folder", "Model", "Configuration",
		"RemoteEvent", "RemoteFunction", "BindableEvent", "BindableFunction",
		"ScreenGui", "SurfaceGui", "BillboardGui", "Frame", "ScrollingFrame" 
	},
	
	-- Locations to scan
	SCAN_LOCATIONS = {
		"ServerScriptService",
		"ReplicatedStorage",
		"ReplicatedFirst",
		"StarterGui",
		"StarterPlayer",
		"ServerStorage",
		"Workspace", 
	},
	
	MAX_ITEMS = 2000, 
}

-- ============================================================================
-- SAFETY & RESILIENCE SETTINGS (v3.0)
-- ============================================================================

-- Circuit Breaker (hard safety boundary for failure spirals)
Constants.CIRCUIT_BREAKER = {
	enabled = true,
	failureThreshold = 5,                  -- Failures before blocking execution
	cooldownPeriod = 30,                   -- Seconds before auto-retry (half-open)
	resetOnSuccess = true,                 -- Reset failure counter on any success
	trackPerTool = false,                  -- Separate circuits per tool (advanced)
	warningThreshold = 3,                  -- Warn user after N failures
}

-- Output Validation (catches hallucinations before execution)
Constants.OUTPUT_VALIDATOR = {
	enabled = true,
	checkPathExists = true,                -- Verify paths exist before modification
	checkPlaceholders = true,              -- Detect TODO/FIXME in generated code
	checkSyntax = true,                    -- Basic Lua syntax validation
	suggestSimilarPaths = true,            -- "Did you mean..." suggestions
	maxSuggestions = 3,                    -- Max path suggestions to show
}

-- Error Prediction (pre-flight checks before tool execution)
Constants.ERROR_PREDICTOR = {
	enabled = true,
	staleThresholdSeconds = 120,           -- Script read older than this = warning
	trackModifications = true,             -- Track script modifications for freshness
	warnOnStaleContext = true,             -- Warn when using old script data
}

-- Working Memory (tiered context management)
Constants.WORKING_MEMORY = {
	enabled = true,
	maxWorkingItems = 20,                  -- Max items before compaction
	maxCriticalItems = 10,                 -- Max critical items (goals, key decisions)
	maxBackgroundItems = 50,               -- Max background items (summaries)
	relevanceHalfLifeSeconds = 300,        -- 5 minutes (relevance halves over time)
	minRelevance = 10,                     -- Floor for relevance decay
	compactThreshold = 15,                 -- Compact when working > this
}

-- Session Management (lifecycle coordination)
Constants.SESSION_MANAGER = {
	enabled = true,
	resetCircuitOnNewTask = true,          -- Reset circuit breaker for each new task
	markStaleOnNewTask = true,             -- Mark script reads as stale for new tasks
	trackTaskDuration = true,              -- Track how long tasks take
}

-- Scan Locations (Legacy compat)
Constants.SCAN_LOCATIONS = Constants.INDEXING and Constants.INDEXING.SCAN_LOCATIONS or {
	"ServerScriptService",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterGui",
	"StarterPlayer",
	"ServerStorage",
}

-- Color Scheme (VS Code Dark Theme)
-- Professional, minimal palette optimized for readability
Constants.COLORS = {
	-- Backgrounds (VS Code Dark)
	background = Color3.fromRGB(30, 30, 30),           -- #1E1E1E
	backgroundLight = Color3.fromRGB(37, 37, 38),      -- #252526 Surface
	backgroundDark = Color3.fromRGB(24, 24, 24),       -- Recessed
	backgroundHover = Color3.fromRGB(45, 45, 48),      -- Hover state

	-- Text (High contrast hierarchy)
	textPrimary = Color3.fromRGB(212, 212, 212),       -- #D4D4D4 Primary
	textSecondary = Color3.fromRGB(156, 156, 156),     -- #9C9C9C Secondary
	textMuted = Color3.fromRGB(106, 106, 106),         -- #6A6A6A Muted

	-- Accent Colors (VS Code inspired)
	accentPrimary = Color3.fromRGB(0, 122, 204),       -- #007ACC VS Code Blue
	accentPrimaryHover = Color3.fromRGB(28, 151, 234), -- Lighter blue
	accentSuccess = Color3.fromRGB(35, 134, 54),       -- Green (muted)
	accentWarning = Color3.fromRGB(205, 145, 60),      -- Amber (muted)
	accentError = Color3.fromRGB(196, 57, 57),         -- Red (muted)

	-- UI Elements
	buttonDisabled = Color3.fromRGB(60, 60, 60),
	codeBackground = Color3.fromRGB(24, 24, 24),
	codeBorder = Color3.fromRGB(50, 50, 50),

	-- Chat Messages (Subtle, professional)
	messageUser = Color3.fromRGB(38, 42, 52),          -- User bubble
	messageAssistant = Color3.fromRGB(32, 32, 34),     -- AI bubble (nearly bg)
	messageSystem = Color3.fromRGB(34, 38, 42),        -- System

	-- Planning & Tool Activity
	messagePlanning = Color3.fromRGB(36, 36, 42),      -- Planning
	messageVerification = Color3.fromRGB(34, 40, 48),  -- Verification
	toolActivityBg = Color3.fromRGB(28, 28, 30),       -- Tool operations
	toolSuccessBorder = Color3.fromRGB(35, 134, 54),   -- Matches accentSuccess
	toolPendingBorder = Color3.fromRGB(0, 122, 204),   -- Matches accentPrimary

	-- Collapsible Headers
	collapsibleHeader = Color3.fromRGB(40, 40, 42),    -- Header background
	collapsibleHeaderHover = Color3.fromRGB(50, 50, 54), -- Header hover
}

-- Icons (Emoji + Stylish symbols for Roblox TextLabel)
Constants.ICONS = {
	-- Brand
	LUX = "✨",

	-- Status indicators
	CHECK = "✅",
	ERROR = "❌",
	WARNING = "⚠️",
	INFO = "ℹ️",
	LOADING = "⏳",

	-- Actions
	SEND = "➤",
	REFRESH = "🔄",
	RESET = "🔃",
	SETTINGS = "⚙️",
	SEARCH = "🔍",

	-- UI elements
	EXPAND = "▶",
	COLLAPSE = "▼",
	ARROW_RIGHT = "→",
	ARROW_DOWN = "↓",

	-- Chat/AI
	AI = "🤖",
	USER = "👤",
	SYSTEM = "⚡",
	THINKING = "💭",

	-- Tools
	EDIT = "✏️",
	CREATE = "➕",
	DELETE = "🗑️",
	READ = "📖",
	PATCH = "🔧",
	PROPS = "⚙️",

	-- Status
	SUCCESS = "✅",
	FAIL = "❌",
	PENDING = "⏳",

	-- Currency/Stats
	COST = "💰",
	TOKENS = "🔢",

	-- File tree
	FOLDER = "📁",
	SCRIPT = "📄",

	-- Misc
	KEY = "🔑",
	STAR = "⭐",
	DOT = "•",
	BULLET = "•",
}

-- UI Dimensions (Compact, professional typography)
Constants.UI = {
	WIDGET_DEFAULT_WIDTH = 700,
	WIDGET_DEFAULT_HEIGHT = 550,
	WIDGET_MIN_WIDTH = 400,
	WIDGET_MIN_HEIGHT = 400,
	PADDING = 8,                 -- Reduced from 12
	PADDING_SMALL = 4,           -- Internal padding
	ELEMENT_GAP = 4,             -- Reduced from 8
	CORNER_RADIUS = 4,           -- Reduced from 8

	-- Typography Hierarchy (clean, professional)
	FONT_SIZE_HEADER = 14,       -- Reduced from 20 (section headers)
	FONT_SIZE_SUBHEADER = 11,    -- New: uppercase labels
	FONT_SIZE_NORMAL = 12,       -- Reduced from 14 (body text)
	FONT_SIZE_SMALL = 10,        -- Reduced from 12 (secondary)
	FONT_SIZE_TINY = 9,          -- New: timestamps, hints
	FONT_SIZE_CODE = 11,         -- Code (Fira Mono style)
	LINE_HEIGHT = 1.4,           -- For readability

	-- Fonts
	FONT_HEADER = Enum.Font.GothamBold,
	FONT_NORMAL = Enum.Font.Gotham,
	FONT_CODE = Enum.Font.Code,
	FONT_MONO = Enum.Font.Code,

	-- Layout Heights (compact)
	HEADER_HEIGHT = 28,          -- Reduced from 30
	BUTTON_HEIGHT = 28,          -- Reduced from 40
	INPUT_HEIGHT = 44,           -- Reduced from 60
	STATUS_MIN_HEIGHT = 24,      -- Reduced from 80

	-- Z-Index Layering (for proper UI stacking)
	ZINDEX = {
		BASE = 1,                -- Base UI elements
		WIDGETS = 10,            -- Interactive widgets
		MODAL = 100,             -- Modal dialogs
		TOAST = 1000,            -- Toast notifications (always on top)
	}
}

-- ============================================================================
-- COMMAND CENTER UI (Three-Pane Dashboard)
-- ============================================================================
Constants.COMMAND_CENTER = {
	enabled = true,
	minWidgetWidth = 400,              -- Below this, collapse side panes to icons
	minWidgetHeight = 400,
	paneWidths = {
		left = 0.20,                   -- 20% - Brain pane
		center = 0.60,                 -- 60% - Stream pane (chat)
		right = 0.20                   -- 20% - Mission pane
	},
	collapsedPaneWidth = 36,           -- Width when collapsed (icons only)
	headerHeight = 32,                 -- Reduced from 36
	inputHeight = 44,                  -- Reduced from 60
	statusBarHeight = 24,              -- Reduced from 28
	paneGap = 2,                       -- Gap between panes
	sectionGap = 4,                    -- Reduced from 8

	-- Toast notifications
	toastEnabled = true,
	toastDuration = 3,
	toastMaxVisible = 3,

	-- Colors for Command Center (VS Code theme)
	colors = {
		paneBackground = Color3.fromRGB(30, 30, 30),   -- Match main bg
		paneBorder = Color3.fromRGB(45, 45, 48),
		sectionHeader = Color3.fromRGB(37, 37, 38),
		collapsedPane = Color3.fromRGB(32, 32, 34),
	}
}

-- Error Messages
Constants.ERRORS = {
	TOO_MANY_SCRIPTS = {
		title = "Too Many Scripts",
		icon = "⚠️",
		format = function(count, breakdown)
			return string.format("Found %d scripts (max %d).\nPlease reduce count or use empty baseplate.", count, Constants.MAX_SCRIPTS)
		end
	},
	SERVER_UNREACHABLE = { title = "Cannot Connect", icon = "❌", message = "Unable to reach server." },
	SERVER_ERROR = { title = "Server Error", icon = "❌", format = function(code) return "Error code: " .. code end },
	REQUEST_TIMEOUT = { title = "Timeout", icon = "⏳", format = function(t) return "Request timed out (> " .. t .. "s)" end },
	RATE_LIMITED = { title = "Slow Down", icon = "⚠️", message = "Sending too quickly." },
	SCRIPT_NOT_FOUND = { title = "Not Found", icon = "❌", format = function(p) return "Script not found: " .. p end },
	HTTP_NOT_ENABLED = { title = "HTTP Disabled", icon = "⚠️", message = "Enable HttpService in Game Settings." }
}

-- Status Panel States
Constants.STATUS_STATES = {
	SCANNING = "scanning",
	READY = "ready",
	INDEXING = "indexing",
	ERROR = "error",
	EMPTY = "empty",
	NEEDS_INDEX = "needs_index"
}

return Constants
