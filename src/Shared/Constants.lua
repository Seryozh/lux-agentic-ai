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
		simple = 2,    -- 1-2 estimated steps = simple
		medium = 5,    -- 3-5 estimated steps = medium  
		complex = 999  -- 6+ estimated steps = complex
	}
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

-- Scan Locations
Constants.SCAN_LOCATIONS = {
	"ServerScriptService",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"StarterGui",
	"StarterPlayer",
	"ServerStorage",
}

-- Color Scheme (Modern Dark Theme)
-- A cohesive, professional palette with subtle blue undertones
Constants.COLORS = {
	-- Backgrounds
	background = Color3.fromRGB(22, 22, 26),           -- Deep charcoal
	backgroundLight = Color3.fromRGB(32, 34, 40),      -- Elevated surface
	backgroundDark = Color3.fromRGB(18, 18, 22),       -- Recessed surface
	backgroundHover = Color3.fromRGB(42, 44, 52),      -- Hover state

	-- Text
	textPrimary = Color3.fromRGB(248, 250, 252),       -- Almost white
	textSecondary = Color3.fromRGB(168, 176, 190),     -- Muted gray-blue
	textMuted = Color3.fromRGB(100, 110, 125),         -- Very muted

	-- Accent Colors (Tailwind-inspired)
	accentPrimary = Color3.fromRGB(99, 102, 241),      -- Indigo 500
	accentPrimaryHover = Color3.fromRGB(129, 140, 248), -- Indigo 400
	accentSuccess = Color3.fromRGB(34, 197, 94),       -- Green 500
	accentWarning = Color3.fromRGB(251, 191, 36),      -- Amber 400
	accentError = Color3.fromRGB(239, 68, 68),         -- Red 500

	-- UI Elements
	buttonDisabled = Color3.fromRGB(75, 80, 95),
	codeBackground = Color3.fromRGB(16, 16, 20),
	codeBorder = Color3.fromRGB(55, 60, 75),

	-- Chat Messages
	messageUser = Color3.fromRGB(45, 50, 80),          -- User bubble (indigo tint)
	messageAssistant = Color3.fromRGB(38, 40, 48),     -- AI bubble (neutral)
	messageSystem = Color3.fromRGB(30, 42, 48),        -- System (subtle teal-gray)

	-- Planning & Tool Activity
	messagePlanning = Color3.fromRGB(38, 38, 55),      -- Planning (purple tint)
	messageVerification = Color3.fromRGB(35, 45, 58),  -- Verification (blue tint)
	toolActivityBg = Color3.fromRGB(28, 32, 42),       -- Tool operations
	toolSuccessBorder = Color3.fromRGB(34, 197, 94),   -- Matches accentSuccess
	toolPendingBorder = Color3.fromRGB(99, 102, 241),  -- Matches accentPrimary

	-- Collapsible Headers
	collapsibleHeader = Color3.fromRGB(45, 50, 65),    -- Header background
	collapsibleHeaderHover = Color3.fromRGB(55, 60, 78), -- Header hover
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

	-- Misc
	KEY = "🔑",
	STAR = "⭐",
	DOT = "•",
	BULLET = "•",
}

-- UI Dimensions
Constants.UI = {
	WIDGET_DEFAULT_WIDTH = 400,
	WIDGET_DEFAULT_HEIGHT = 600,
	WIDGET_MIN_WIDTH = 300,
	WIDGET_MIN_HEIGHT = 400,
	PADDING = 12,
	ELEMENT_GAP = 8,
	CORNER_RADIUS = 8,
	FONT_SIZE_HEADER = 20,
	FONT_SIZE_NORMAL = 14,
	FONT_SIZE_SMALL = 12,
	FONT_SIZE_CODE = 12,
	FONT_HEADER = Enum.Font.GothamBold,
	FONT_NORMAL = Enum.Font.Gotham,
	FONT_CODE = Enum.Font.Code,
	FONT_MONO = Enum.Font.Code,
	HEADER_HEIGHT = 30,
	BUTTON_HEIGHT = 40,
	INPUT_HEIGHT = 60,
	STATUS_MIN_HEIGHT = 80,
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
