# Lux v2: Complete Implementation Plan

## Executive Summary

Building an agentic AI plugin for Roblox Studio that:
- **What:** Lets non-programmers build Roblox games through natural conversation
- **How:** Two-model architecture (lightweight orchestrator + powerful worker) with on-demand tools
- **Cost:** $0.05-0.90 per chat session (BYOK via OpenRouter)
- **Timeline:** 3-4 weeks to MVP (ship it, iterate later)
- **Target:** Game creators, builders, designers

See `SIMPLE_TWO_MODEL_APPROACH.md` for the final architecture decision.

---

## Phase 1: Foundation (Days 1-2)

### Goal: Setup + Backend API Design

Everything here is planning and setup. **NO CODE YET.**

#### 1.1 Environment Setup

```bash
# Create project structure
mkdir -p lux-plugin
cd lux-plugin

# Create subdirectories
mkdir backend plugin shared
mkdir backend/tests

# Backend dependencies
cd backend
python3 -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows

# Will install these later
pip install fastapi uvicorn langgraph langchain openrouter pydantic python-dotenv
```

#### 1.2 Define API Contract (Plugin ↔ Backend)

**This is CRITICAL. Get this right before coding.**

```python
# backend/schemas.py (pydantic models)

from pydantic import BaseModel
from typing import List, Dict, Any, Optional

# ======================
# REQUEST SCHEMAS
# ======================

class ScriptMetadata(BaseModel):
    """Lightweight metadata for each script"""
    name: str
    type: str  # "LocalScript", "ModuleScript", "Script"
    parent: str  # Path like "StarterPlayer/StarterCharacterScripts"
    tags: List[str]  # ["jump", "movement", "input"]
    imports: List[str]  # What modules it requires
    exports: List[str]  # What functions/values it exports
    size: int  # Bytes
    first_100_chars: str  # Just summary, not full code

class ChatRequest(BaseModel):
    """User sends this when they want AI help"""
    user_message: str
    session_id: str
    project_metadata: List[ScriptMetadata]  # Metadata for ALL scripts
    conversation_history: List[Dict[str, str]]  # Previous messages
    user_openrouter_key: str  # User's API key

class RequestScriptsRequest(BaseModel):
    """Backend asks plugin for specific full scripts"""
    session_id: str
    script_names: List[str]  # ["PlayerMovement.lua", "Humanoid.lua"]

# ======================
# RESPONSE SCHEMAS
# ======================

class ChatResponse(BaseModel):
    """Backend sends this back to plugin"""
    success: bool
    message: str  # AI's response
    generated_code: Optional[str]  # Code that was generated
    modified_scripts: Optional[Dict[str, str]]  # {filename: new_code}
    created_scripts: Optional[Dict[str, str]]  # {filename: new_code}
    metadata_updates: Optional[Dict[str, Dict]]  # What metadata changed
    error: Optional[str]  # If something failed

class ScriptsResponse(BaseModel):
    """Plugin sends back full scripts to backend"""
    scripts: Dict[str, str]  # {filename: full_code}
```

#### 1.3 Design Backend Endpoints

```python
# backend/main.py (FastAPI endpoints)

@app.post("/chat")
async def chat(request: ChatRequest) -> ChatResponse:
    """
    Main endpoint: User sends message, AI processes it

    Flow:
    1. Receive chat request with metadata for all scripts
    2. Pass to LangGraph agent
    3. Agent might call tools:
       - query_metadata(tags) → find relevant scripts
       - request_scripts(names) → ask plugin for specific scripts
       - list_scripts(folder) → see what's available
    4. Return result to plugin
    """
    pass

@app.post("/scripts")
async def get_scripts(request: RequestScriptsRequest) -> ScriptsResponse:
    """
    Backend requests full scripts from plugin
    Plugin calls this endpoint to get scripts

    WAIT. This is backwards. Backend requests, plugin responds?

    Actually, needs callback. See below.
    """
    pass

@app.post("/request-scripts")
async def request_scripts_from_plugin(request: RequestScriptsRequest):
    """
    BETTER: Backend sends a request to plugin asking for scripts
    Plugin has a callback handler that receives this
    Plugin responds by calling /provide-scripts endpoint
    """
    # Send this to plugin somehow (websocket, polling, etc.)
    # For MVP: Plugin polls or we use callback URLs
    pass

@app.post("/provide-scripts")
async def provide_scripts(request: ScriptsResponse):
    """
    Plugin calls this to provide requested scripts
    Backend stores them in the agent's context
    Agent continues running
    """
    pass

@app.get("/health")
async def health():
    """Health check for deployment"""
    return {"status": "ok"}
```

**ISSUE: How does backend ask plugin for scripts?**

Options:
1. **Long polling:** Plugin periodically asks "do you need anything?"
2. **Websocket:** Keep connection open, backend pushes requests
3. **Callback URL:** Backend has URL to call to request scripts
4. **All at once:** Plugin sends scripts upfront (defeats the purpose)

**MVP Decision:** Option 1 - Long polling
- Plugin polls `/pending-requests` endpoint every 2 seconds
- Backend returns requests if any
- Plugin sends response via `/provide-scripts`
- Simple, no infrastructure needed

#### 1.4 LangGraph Agent Structure (Design Only)

```python
# backend/agent.py (LangGraph agent design)

from langgraph.graph import StateGraph
from langgraph.graph import END

# Agent state (what it remembers during loop)
class AgentState(TypedDict):
    messages: List[Dict]  # Conversation history
    user_input: str  # Current user message
    project_metadata: List[ScriptMetadata]  # All available scripts
    loaded_scripts: Dict[str, str]  # Full scripts agent has read
    current_task: str  # What the agent is working on
    generated_code: Dict[str, str]  # Code generated so far
    tool_calls: List[Dict]  # Tools the agent wants to use
    pending_script_requests: List[str]  # Scripts we're waiting for
    errors: List[str]  # Errors that occurred

class LuxAgent:
    def __init__(self, openrouter_key: str, initial_metadata: List[ScriptMetadata]):
        self.openrouter_key = openrouter_key
        self.metadata = initial_metadata
        self.state = AgentState(...)

    def build_graph(self):
        """Build the LangGraph state machine"""
        graph = StateGraph(AgentState)

        # Nodes (steps in the agent loop)
        graph.add_node("analyze", self.analyze_request)
        graph.add_node("request_scripts", self.request_scripts)
        graph.add_node("wait_for_scripts", self.wait_for_scripts)
        graph.add_node("generate", self.generate_code)
        graph.add_node("validate", self.validate_code)
        graph.add_node("finalize", self.finalize_response)

        # Edges (transitions between nodes)
        graph.add_edge("analyze", "request_scripts")
        graph.add_edge("request_scripts", "wait_for_scripts")
        graph.add_edge("wait_for_scripts", "generate")
        graph.add_edge("generate", "validate")
        graph.add_conditional_edge(
            "validate",
            self.validation_passed,  # Function that returns True/False
            {True: "finalize", False: "generate"}  # If True→finalize, False→generate
        )
        graph.add_edge("finalize", END)

        return graph.compile()

    async def analyze_request(self, state: AgentState) -> AgentState:
        """
        Step 1: Understand what user is asking
        Call OpenRouter to analyze request
        Decide what scripts we need
        """
        # Call OpenRouter with user message + project metadata
        # Model responds: "I need scripts X, Y, Z"
        # Return state with updated pending_script_requests
        pass

    async def request_scripts(self, state: AgentState) -> AgentState:
        """
        Step 2: Ask plugin for specific scripts
        Store the request, wait for response
        """
        state.pending_script_requests = [...]  # Scripts we want
        return state

    async def wait_for_scripts(self, state: AgentState) -> AgentState:
        """
        Step 3: Wait for plugin to provide scripts
        Poll for responses, timeout if taking too long
        """
        # This is handled by /provide-scripts endpoint
        # When plugin responds, this state updates
        pass

    async def generate_code(self, state: AgentState) -> AgentState:
        """
        Step 4: Generate code
        Call OpenRouter with loaded scripts
        Return generated code
        """
        pass

    async def validate_code(self, state: AgentState) -> AgentState:
        """
        Step 5: Check if code is valid
        Syntax check, API check, etc.
        """
        pass

    def validation_passed(self, state: AgentState) -> bool:
        """Decide: is code valid? True→finalize, False→regenerate"""
        return len(state.errors) == 0

    async def finalize_response(self, state: AgentState) -> AgentState:
        """
        Step 6: Prepare final response to plugin
        Include generated code, metadata updates, message
        """
        pass
```

#### 1.5 Tools Available to Agent

```python
# backend/tools.py (What the agent can do)

def get_metadata(script_name: str, metadata_list: List[ScriptMetadata]) -> Dict:
    """
    Agent calls this: "What's the metadata for PlayerMovement.lua?"
    Returns: exports, imports, tags
    """
    for script in metadata_list:
        if script.name == script_name:
            return {
                "name": script.name,
                "imports": script.imports,
                "exports": script.exports,
                "tags": script.tags,
                "type": script.type
            }
    return None

def analyze_dependencies(initial_scripts: List[str], metadata_list: List[ScriptMetadata]) -> List[str]:
    """
    Agent calls this: "Build a metadata basket"
    Given initial scripts (from keyword matching), expand with dependencies
    Returns: List of all needed scripts

    Implementation:
    1. Start with initial_scripts
    2. For each script in initial_scripts:
       - Read imports
       - Add imported scripts to basket
    3. Repeat for depth=2
    4. Return final basket
    """
    pass

def request_scripts_from_plugin(script_names: List[str], session_id: str):
    """
    Agent calls this: "I need these full scripts: [...]"
    Backend stores request, plugin will fetch them
    Agent waits until scripts are provided
    """
    pass

# These are called by the agent through OpenRouter
AGENT_TOOLS = [
    {
        "name": "get_metadata",
        "description": "Get metadata (exports, imports) for a script",
        "parameters": {
            "type": "object",
            "properties": {
                "script_name": {"type": "string", "description": "Name of the script"}
            },
            "required": ["script_name"]
        }
    },
    {
        "name": "analyze_dependencies",
        "description": "Build a metadata basket of related scripts",
        "parameters": {
            "type": "object",
            "properties": {
                "initial_scripts": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Scripts to start with"
                }
            },
            "required": ["initial_scripts"]
        }
    },
    {
        "name": "request_scripts",
        "description": "Request full code for specific scripts",
        "parameters": {
            "type": "object",
            "properties": {
                "script_names": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Which scripts to get"
                }
            },
            "required": ["script_names"]
        }
    }
]
```

#### 1.6 File Structure

```
lux-backend/
├── main.py                 # FastAPI app, endpoints
├── agent.py                # LangGraph agent logic
├── tools.py                # Tools for the agent
├── schemas.py              # Pydantic models
├── openrouter_client.py    # Calls OpenRouter API
├── validator.py            # Code validation
├── config.py               # Configuration (API keys, etc.)
├── requirements.txt        # Dependencies
├── .env.example            # Example environment variables
└── tests/
    ├── test_schemas.py
    ├── test_tools.py
    ├── test_agent.py
    └── test_integration.py

lux-plugin/
├── init.lua                # Plugin entry point
├── main.lua                # Main plugin logic
├── ui.lua                  # UI components (chat box, etc.)
├── api_client.lua          # HTTP calls to backend
├── metadata_scanner.lua    # Scans project for script metadata
└── config.lua              # Plugin configuration

lux-shared/
├── types.ts                # TypeScript types (if using web UI)
└── README.md
```

---

## Phase 2: Backend Implementation (Days 3-5)

### Goal: Build working HTTP server + agent loop

#### 2.1 Setup & Dependencies

```bash
# backend/requirements.txt
fastapi==0.109.0
uvicorn==0.27.0
langgraph==0.0.52
langchain==0.1.10
langchain-openai==0.0.2
pydantic==2.5.3
python-dotenv==1.0.0
httpx==0.25.2
pytest==7.4.4
```

#### 2.2 OpenRouter Client

```python
# backend/openrouter_client.py

import httpx
import json
from typing import List, Dict, Optional

class OpenRouterClient:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://openrouter.io/api/v1"
        self.model = "google/gemini-2.0-flash-exp"  # Fast + cheap for MVP

    async def call_model(
        self,
        system_prompt: str,
        user_message: str,
        tools: List[Dict] = None,
        conversation_history: List[Dict] = None
    ) -> Dict:
        """
        Call OpenRouter API

        Args:
            system_prompt: System instructions
            user_message: What the user said
            tools: Available tools (OpenRouter format)
            conversation_history: Previous messages

        Returns:
            {
                "content": "response text",
                "tool_calls": [...],
                "stop_reason": "end_turn" or "tool_use"
            }
        """
        messages = conversation_history or []
        messages.append({"role": "user", "content": user_message})

        request_body = {
            "model": self.model,
            "messages": messages,
            "system": system_prompt,
            "temperature": 0.7,
            "max_tokens": 4096,
        }

        if tools:
            request_body["tools"] = tools

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "HTTP-Referer": "https://lux-roblox.app",
                    "X-Title": "Lux"
                },
                json=request_body,
                timeout=60.0
            )

        if response.status_code != 200:
            raise Exception(f"OpenRouter error: {response.text}")

        result = response.json()

        # Parse response
        message = result["choices"][0]["message"]

        return {
            "content": message.get("content", ""),
            "tool_calls": message.get("tool_calls", []),
            "stop_reason": result["choices"][0].get("finish_reason", "end_turn")
        }
```

#### 2.3 Basic FastAPI Server

```python
# backend/main.py

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import asyncio
import logging

app = FastAPI()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global state for managing agent sessions
sessions = {}  # {session_id: agent_instance}
pending_requests = {}  # {session_id: [script_names_to_request]}
provided_scripts = {}  # {session_id: {script_name: code}}

@app.post("/chat")
async def chat(request: ChatRequest) -> ChatResponse:
    """Main chat endpoint"""
    try:
        logger.info(f"Chat request: {request.session_id}")

        # Create or get existing agent
        if request.session_id not in sessions:
            agent = LuxAgent(
                openrouter_key=request.user_openrouter_key,
                initial_metadata=request.project_metadata
            )
            sessions[request.session_id] = agent
        else:
            agent = sessions[request.session_id]

        # Run agent (it will make tool calls as needed)
        result = await agent.run(request.user_message)

        return ChatResponse(
            success=True,
            message=result["message"],
            generated_code=result.get("generated_code"),
            modified_scripts=result.get("modified_scripts"),
            metadata_updates=result.get("metadata_updates")
        )

    except Exception as e:
        logger.error(f"Error in chat: {e}")
        return ChatResponse(
            success=False,
            message="Error processing request",
            error=str(e)
        )

@app.post("/pending-requests")
async def get_pending_requests(session_id: str):
    """Plugin polls this to see if backend needs anything"""
    if session_id in pending_requests:
        requests = pending_requests[session_id]
        pending_requests[session_id] = []  # Clear after sending
        return {"requests": requests}
    return {"requests": []}

@app.post("/provide-scripts")
async def provide_scripts(request: ScriptsResponse):
    """Plugin calls this to provide requested scripts"""
    session_id = request.get("session_id")
    if session_id and session_id in sessions:
        # Store scripts for agent
        if session_id not in provided_scripts:
            provided_scripts[session_id] = {}
        provided_scripts[session_id].update(request["scripts"])
        return {"status": "ok"}
    return {"status": "error", "message": "Unknown session"}

@app.get("/health")
async def health():
    """Health check"""
    return {"status": "ok"}

# Run with: uvicorn main:app --reload
```

#### 2.4 Agent Implementation (MVP - Simplified)

```python
# backend/agent.py (MVP Version - No full LangGraph yet)

class LuxAgent:
    def __init__(self, openrouter_key: str, initial_metadata: List[ScriptMetadata]):
        self.openrouter_key = openrouter_key
        self.metadata = initial_metadata
        self.loaded_scripts = {}
        self.client = OpenRouterClient(openrouter_key)
        self.conversation_history = []

    async def run(self, user_message: str) -> Dict:
        """
        MVP Agent Loop (simplified, not full LangGraph):

        1. Analyze request → Understand what user wants
        2. Request scripts → Ask for what we need
        3. Generate code → Create solution
        4. Validate → Check it's correct
        5. Return → Send to plugin
        """

        # Step 1: Analyze request
        logger.info("Step 1: Analyzing request")
        analysis = await self.analyze_request(user_message)
        needed_scripts = analysis["needed_scripts"]  # e.g., ["PlayerMovement.lua", "Humanoid.lua"]

        # Step 2: Request scripts from plugin
        logger.info(f"Step 2: Requesting scripts: {needed_scripts}")
        pending_requests[self.session_id] = needed_scripts

        # Step 3: Wait for plugin to provide scripts
        logger.info("Step 3: Waiting for scripts from plugin")
        await asyncio.sleep(1)  # Wait for plugin to respond

        if self.session_id not in provided_scripts:
            return {
                "message": "Timed out waiting for scripts. Check your connection.",
                "generated_code": None
            }

        self.loaded_scripts = provided_scripts[self.session_id]

        # Step 4: Generate code
        logger.info("Step 4: Generating code")
        generated_code = await self.generate_code(user_message)

        # Step 5: Validate
        logger.info("Step 5: Validating code")
        validation_result = self.validate_code(generated_code)

        if not validation_result["valid"]:
            logger.warning(f"Validation failed: {validation_result['errors']}")
            # Try to fix
            generated_code = await self.fix_code(generated_code, validation_result["errors"])

        # Step 6: Return result
        return {
            "message": f"I've updated your scripts. Check the code below.",
            "generated_code": generated_code,
            "modified_scripts": {"PlayerMovement.lua": generated_code}  # Which scripts changed
        }

    async def analyze_request(self, user_message: str) -> Dict:
        """
        Figure out what the user wants
        Use model to analyze + metadata to find relevant scripts
        """

        # Create summary of available scripts from metadata
        scripts_summary = "\n".join([
            f"- {m.name} (tags: {', '.join(m.tags)}, exports: {', '.join(m.exports)})"
            for m in self.metadata[:20]  # Limit to first 20 for context
        ])

        prompt = f"""
You are a Roblox game development AI. Analyze the user's request and identify which scripts you need to see.

Available scripts in project:
{scripts_summary}

User wants: {user_message}

Respond in this JSON format:
{{
    "analysis": "Brief explanation of what user is asking",
    "needed_scripts": ["PlayerMovement.lua", "Humanoid.lua"],
    "confidence": 0.85
}}

Only return JSON, nothing else.
"""

        response = await self.client.call_model(
            system_prompt="You are a Roblox development expert.",
            user_message=prompt
        )

        import json
        result = json.loads(response["content"])
        return result

    async def generate_code(self, user_message: str) -> str:
        """Generate Lua code based on request + loaded scripts"""

        scripts_context = "\n".join([
            f"--- {name} ---\n{code}\n"
            for name, code in self.loaded_scripts.items()
        ])

        prompt = f"""
The user wants: {user_message}

Here are the relevant scripts from their project:

{scripts_context}

Generate Lua code that accomplishes what they asked.
Return ONLY the code, no explanations.
"""

        response = await self.client.call_model(
            system_prompt="You are an expert Roblox Lua developer.",
            user_message=prompt
        )

        return response["content"]

    def validate_code(self, code: str) -> Dict:
        """Basic validation: syntax, API calls, etc."""

        errors = []

        # Check for matching function/end
        if code.count("function") != code.count("end"):
            errors.append("Mismatched 'function'/'end' keywords")

        # Check for common mistakes
        if "MoveTo" in code and "Humanoid" not in self.loaded_scripts.get("Humanoid.lua", ""):
            errors.append("Code uses Humanoid but script not loaded")

        return {
            "valid": len(errors) == 0,
            "errors": errors
        }

    async def fix_code(self, code: str, errors: List[str]) -> str:
        """Try to fix errors"""

        prompt = f"""
The code I generated has errors:
{chr(10).join(errors)}

Original code:
{code}

Fix the errors. Return ONLY the fixed code.
"""

        response = await self.client.call_model(
            system_prompt="You are an expert Roblox Lua developer.",
            user_message=prompt
        )

        return response["content"]
```

#### 2.5 Test Endpoints with Postman/Curl

```bash
# Test health check
curl http://localhost:8000/health

# Test chat (create a JSON file: test_request.json)
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d @test_request.json

# test_request.json
{
  "user_message": "Add a script that makes the player jump",
  "session_id": "test-session-1",
  "project_metadata": [
    {
      "name": "PlayerMovement.lua",
      "type": "LocalScript",
      "parent": "StarterPlayer/StarterCharacterScripts",
      "tags": ["movement", "jump", "input"],
      "imports": ["Humanoid", "Input"],
      "exports": ["jump", "walk"],
      "size": 2500,
      "first_100_chars": "local Humanoid = require(...)"
    }
  ],
  "conversation_history": [],
  "user_openrouter_key": "sk-..."
}
```

---

## Phase 3: Plugin Implementation (Days 6-8)

### Goal: Build Roblox Studio plugin that communicates with backend

#### 3.1 Plugin Structure

```lua
-- plugin/init.lua (Plugin entry point)

local RunService = game:GetService("RunService")

-- Only run in Studio
if not RunService:IsStudio() then
    return
end

-- Load modules
local main = require(script.main)
local ui = require(script.ui)
local apiClient = require(script.api_client)
local metadataScanner = require(script.metadata_scanner)

-- Initialize plugin
local toolbar = plugin:CreateToolbar("Lux")
local button = toolbar:CreateButton("Lux", "Open Lux AI", "rbxasset://textures/Cursors/DragCursor.png")

local dockWidget = plugin:CreateDockWidgetPluginGui(
    "LuxChat",
    DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Bottom, true, false, 200, 300)
)
dockWidget.Title = "Lux - AI Builder"

-- Build UI inside widget
ui.initialize(dockWidget)

-- Handle button click
button.Click:Connect(function()
    dockWidget.Enabled = not dockWidget.Enabled
end)

print("Lux plugin loaded!")
```

#### 3.2 API Client

```lua
-- plugin/api_client.lua

local HttpService = game:GetService("HttpService")

local ApiClient = {}

function ApiClient.initialize(backendUrl, userOpenRouterKey)
    ApiClient.backendUrl = backendUrl or "http://localhost:8000"
    ApiClient.userOpenRouterKey = userOpenRouterKey
    ApiClient.sessionId = game:GetService("HttpService"):GenerateGUID(false)
end

function ApiClient.sendChat(userMessage, projectMetadata)
    local requestBody = {
        user_message = userMessage,
        session_id = ApiClient.sessionId,
        project_metadata = projectMetadata,
        conversation_history = {},
        user_openrouter_key = ApiClient.userOpenRouterKey
    }

    local success, response = pcall(function()
        return HttpService:JSONEncode(requestBody)
    end)

    if not success then
        return {success = false, error = "Failed to encode request"}
    end

    success, response = pcall(function()
        return HttpService:PostAsync(
            ApiClient.backendUrl .. "/chat",
            response,
            Enum.HttpContentType.ApplicationJson
        )
    end)

    if not success then
        return {success = false, error = "Network error: " .. tostring(response)}
    end

    -- Parse response
    local decoded = HttpService:JSONDecode(response)
    return decoded
end

function ApiClient.pollPendingRequests()
    local success, response = pcall(function()
        return HttpService:PostAsync(
            ApiClient.backendUrl .. "/pending-requests?session_id=" .. ApiClient.sessionId,
            ""
        )
    end)

    if success then
        return HttpService:JSONDecode(response)
    end
    return {requests = {}}
end

function ApiClient.provideScripts(scripts)
    local requestBody = {
        session_id = ApiClient.sessionId,
        scripts = scripts
    }

    local encoded = HttpService:JSONEncode(requestBody)

    pcall(function()
        HttpService:PostAsync(
            ApiClient.backendUrl .. "/provide-scripts",
            encoded,
            Enum.HttpContentType.ApplicationJson
        )
    end)
end

return ApiClient
```

#### 3.3 Metadata Scanner

```lua
-- plugin/metadata_scanner.lua

local MetadataScanner = {}

function MetadataScanner.scanProject()
    """
    Scan all scripts in the game and extract metadata
    Returns: List of ScriptMetadata
    """

    local metadata = {}
    local scannedScripts = {}

    -- Recursively scan all scripts
    local function scanInstance(instance, parentPath)
        parentPath = parentPath or instance:GetFullName()

        if instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript") then
            local scriptType = instance.ClassName
            local scriptName = instance.Name .. ".lua"
            local source = instance.Source

            -- Extract metadata from script attributes or comments
            local metadata = {
                name = scriptName,
                type = scriptType,
                parent = parentPath,
                tags = MetadataScanner.extractTags(scriptName, source),
                imports = MetadataScanner.extractImports(source),
                exports = MetadataScanner.extractExports(source),
                size = #source,
                first_100_chars = source:sub(1, 100)
            }

            table.insert(metadata, metadata)
            scannedScripts[scriptName] = source  -- Keep full code for later
        end

        -- Scan children
        for _, child in ipairs(instance:GetChildren()) do
            scanInstance(child, parentPath)
        end
    end

    -- Start from game root
    scanInstance(game)

    return {
        metadata = metadata,
        scripts = scannedScripts
    }
end

function MetadataScanner.extractTags(scriptName, source)
    """Extract tags from script name and comments"""

    local tags = {}

    -- From filename
    local nameWords = string.lower(scriptName):split("_")
    for _, word in ipairs(nameWords) do
        if word ~= "lua" then
            table.insert(tags, word)
        end
    end

    -- From first comment block
    local commentMatch = source:match("^%-%-(.+)\n")
    if commentMatch then
        -- Parse: -- @tags: jump, movement, input
        local tagsMatch = commentMatch:match("@tags:(.+)")
        if tagsMatch then
            for tag in tagsMatch:gmatch("[^,]+") do
                table.insert(tags, tag:trim())
            end
        end
    end

    return tags
end

function MetadataScanner.extractImports(source)
    """Extract require() statements from source"""

    local imports = {}

    -- Match: require(...), module(...), etc
    for match in source:gmatch('require%s*%(%s*["\']([^"\']+)["\']') do
        table.insert(imports, match)
    end

    return imports
end

function MetadataScanner.extractExports(source)
    """Extract function definitions"""

    local exports = {}

    -- Match: function name(...) or local function name(...)
    for match in source:gmatch("function%s+([a-zA-Z_][a-zA-Z0-9_]*)") do
        table.insert(exports, match)
    end

    return exports
end

return MetadataScanner
```

#### 3.4 UI Component

```lua
-- plugin/ui.lua

local Ui = {}

function Ui.initialize(parent)
    -- Create main container
    local container = Instance.new("Frame")
    container.Name = "LuxContainer"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    container.Parent = parent

    -- Chat display area
    local chatArea = Instance.new("TextLabel")
    chatArea.Name = "ChatArea"
    chatArea.Size = UDim2.new(1, -10, 1, -60)
    chatArea.Position = UDim2.new(0, 5, 0, 5)
    chatArea.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    chatArea.TextColor3 = Color3.fromRGB(255, 255, 255)
    chatArea.TextWrapped = true
    chatArea.TextXAlignment = Enum.TextXAlignment.Left
    chatArea.TextYAlignment = Enum.TextYAlignment.Top
    chatArea.Text = "Lux AI Chat\n\n"
    chatArea.Parent = container

    -- Input box
    local inputBox = Instance.new("TextBox")
    inputBox.Name = "InputBox"
    inputBox.Size = UDim2.new(1, -70, 0, 30)
    inputBox.Position = UDim2.new(0, 5, 1, -35)
    inputBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    inputBox.PlaceholderText = "Ask me to add a feature..."
    inputBox.TextWrapped = false
    inputBox.Parent = container

    -- Send button
    local sendButton = Instance.new("TextButton")
    sendButton.Name = "SendButton"
    sendButton.Size = UDim2.new(0, 60, 0, 30)
    sendButton.Position = UDim2.new(1, -65, 1, -35)
    sendButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    sendButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    sendButton.Text = "Send"
    sendButton.Parent = container

    -- Handle send button click
    sendButton.MouseButton1Click:Connect(function()
        local message = inputBox.Text
        inputBox.Text = ""

        chatArea.Text = chatArea.Text .. "You: " .. message .. "\n"

        -- TODO: Call backend
        chatArea.Text = chatArea.Text .. "Lux: Processing...\n"
    end)

    return {
        container = container,
        chatArea = chatArea,
        inputBox = inputBox,
        sendButton = sendButton
    }
end

return Ui
```

---

## Phase 4: Integration & Testing (Days 9-10)

### Goal: Connect plugin ↔ backend, test end-to-end

#### 4.1 Workflow Test

```
1. Start backend: python -m uvicorn backend.main:app --reload
2. Open Roblox Studio with test project
3. Install plugin
4. Click "Lux" button → Opens chat
5. Type: "Add a script that prints hello"
6. Click Send
7. Backend receives request
8. Backend analyzes project metadata
9. Backend creates task for agent
10. Agent requests scripts from plugin
11. Plugin sends scripts to backend
12. Agent generates code
13. Backend sends code back to plugin
14. Plugin displays generated code
15. User can copy/paste into their game
```

#### 4.2 Real-World Testing Checklist

```
✅ Backend can start without errors
✅ Plugin can connect to backend
✅ Plugin sends project metadata
✅ Backend receives metadata
✅ Backend can analyze request
✅ Backend requests scripts from plugin
✅ Plugin responds with scripts
✅ Backend generates code
✅ Plugin receives generated code
✅ Generated code is syntactically valid
✅ Generated code uses correct Roblox API
✅ Error messages are clear
✅ Latency is acceptable (< 30 seconds per request)
✅ Plugin doesn't freeze while waiting
✅ Backend handles missing scripts gracefully
```

---

## Phase 5: Polish & Deploy (Days 11-14)

### Goal: Production-ready, deployable code

#### 5.1 Deployment Options

**Option A: Vercel (Free, but cold starts)**
```bash
# Deploy backend to Vercel
vercel deploy
# Plugin talks to: https://lux-backend.vercel.app
```

**Option B: Railway ($5/month, better for always-on)**
```bash
# Deploy to Railway
railway up
# Plugin talks to: https://lux-backend.railway.app
```

**Option C: Local Testing**
```bash
# During development
python -m uvicorn backend.main:app --reload
# Plugin talks to: http://localhost:8000
```

#### 5.2 Plugin Publishing

```lua
-- For Roblox Creator Store:
1. Create plugin package (rbxm file)
2. Test thoroughly
3. Submit to Creator Store
4. Document usage
5. Wait for approval
```

#### 5.3 User Setup Flow

```
1. User installs Lux plugin from Creator Store
2. User enters OpenRouter API key in settings
3. User sets backend URL (or uses default)
4. Plugin scans their project on first run
5. User can start asking questions
```

#### 5.4 Error Handling & UX

```python
# Errors to handle:
- Invalid API key → Clear message, link to OpenRouter
- Backend offline → "Can't reach server, try later"
- Network timeout → "Request took too long, retrying..."
- Invalid Lua generated → "I made a mistake, let me fix it"
- Too many requests → "Rate limit hit, wait a moment"
- Project too large → "Your project is huge, analyze fewer scripts"

# Key UX improvements:
- Loading indicator that appears immediately
- Show "Thinking..." status
- Stream responses word-by-word if possible
- Allow canceling long requests
- Save conversation history
- Clear error messages
- Helpful suggestions
```

---

## Key Architectural Decisions (Reference)

See these files for detailed explanations:

- **SIMPLE_TWO_MODEL_APPROACH.md** — Why two models + on-demand tools
- **CHALLENGES_AND_RISKS.md** — Real problems you'll hit, how to solve them
- **CONTEXT_FILTERING_EXPLAINED.md** — How to filter what scripts to send
- **INTELLIGENT_DEPENDENCY_RESOLUTION.md** — Smart metadata basket building

---

## Testing Strategy

### Unit Tests (Backend)

```python
# test_tools.py
- Test get_metadata() returns correct format
- Test analyze_dependencies() finds related scripts
- Test validate_code() catches syntax errors

# test_schemas.py
- Test ChatRequest validation
- Test ChatResponse serialization

# test_agent.py
- Test agent.analyze_request() extracts needed scripts
- Test agent.generate_code() produces valid Lua
```

### Integration Tests

```python
# test_integration.py
- Test full chat flow: request → analysis → generation → response
- Test script request/response cycle
- Test error handling
- Test with different project sizes
```

### Manual Testing (Plugin)

```
- Test in actual Roblox Studio
- Test with real project
- Test with various requests:
  - Simple: "Add a script that prints hello"
  - Complex: "Add double jump system"
  - Edge case: "Add something that doesn't make sense"
- Test error scenarios:
  - Disconnect backend while requesting
  - Invalid API key
  - Request timeout
```

---

## Success Criteria (MVP)

✅ **Functional**
- Plugin can connect to backend
- Backend processes requests
- Code is generated and returned
- User can use it to build

✅ **Reliable**
- No crashes
- Clear error messages
- Handles edge cases

✅ **Fast Enough**
- Full request < 30 seconds
- Loading indicator shows immediately

✅ **Hireable**
- Code is clean and documented
- Architecture is sound
- You understand every part

❌ **NOT Required (v2.1+)**
- Perfect UI
- All edge cases
- Maximum performance
- 10,000 features

---

## Building Order Summary

1. **Phase 1 (Days 1-2):** Plan everything. NO code.
2. **Phase 2 (Days 3-5):** Build backend. Test with Postman.
3. **Phase 3 (Days 6-8):** Build plugin. Connect to backend.
4. **Phase 4 (Days 9-10):** Full integration. Test end-to-end.
5. **Phase 5 (Days 11-14):** Polish, error handling, deploy.

**Total: 2-3 weeks to shipping MVP**

---

## Next Steps

1. ✅ Read and understand this entire plan
2. ✅ Read the referenced architecture documents
3. Start Phase 1: Environment setup + API design
4. Create Python files (main.py, agent.py, tools.py, schemas.py)
5. Create Lua files (plugin/init.lua, ui.lua, api_client.lua)
6. Implement Phase 2 backend
7. Test with Postman
8. Implement Phase 3 plugin
9. Full integration testing
10. Deploy to Railway
11. Publish plugin

---

**This plan is ambitious but achievable. Focus on shipping Phase 1-3 first. Polish in Phase 5.**
