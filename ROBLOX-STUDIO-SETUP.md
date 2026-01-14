# Roblox Studio Plugin Setup - CRITICAL

## The Problem You're Having

The error `Attempted to call require with invalid argument(s)` at line 19 of OpenRouterClient means the **Tools folder is missing its init ModuleScript** in your Roblox Studio model.

## The Root Cause

When you have local files like `src/Tools/init.lua`, Roblox Studio **does not automatically** convert them. You must manually:
1. Create a ModuleScript
2. Name it `init` (no .lua extension)
3. Copy the file contents into it

## Complete Setup Checklist

### Step 1: Create the Base Structure

In Roblox Studio Explorer:

```
Lux (Folder) ← Right-click Workspace → Insert Object → Folder, rename to "Lux"
├── Main (Script) ← Insert Object → Script, rename to "Main"
└── src (Folder)
```

### Step 2: Create Module Folders

Inside `Lux/src/`, create these **Folders**:

- Core
- Memory
- Safety
- Context
- Planning
- Tools
- Coordination
- UI
- Shared

### Step 3: For EACH Folder, Add init ModuleScript

This is the CRITICAL step you're missing:

**For each folder (Core, Memory, Safety, Context, Planning, Tools, Coordination, UI, Shared):**

1. Right-click the folder in Explorer
2. Insert Object → ModuleScript
3. Rename it to exactly `init` (delete "ModuleScript")
4. Open the corresponding `src/[FolderName]/init.lua` file from your local files
5. Copy ALL the contents
6. Paste into the Roblox ModuleScript
7. Save (Ctrl+S or File → Save)

**Example for Tools folder:**
```
Tools (Folder)
└── init (ModuleScript) ← Contains contents of src/Tools/init.lua
```

### Step 4: Add Other ModuleScripts

For each .lua file in the local folders, create a ModuleScript:

**src/Tools/ files:**
- ApprovalQueue.lua → Tools/ApprovalQueue (ModuleScript)
- ProjectTools.lua → Tools/ProjectTools (ModuleScript)
- ReadTools.lua → Tools/ReadTools (ModuleScript)
- ToolDefinitions.lua → Tools/ToolDefinitions (ModuleScript)
- ToolExecutor.lua → Tools/ToolExecutor (ModuleScript)
- WriteTools.lua → Tools/WriteTools (ModuleScript)

Repeat for ALL other folders.

### Step 5: Add OpenRouterClient

In `Lux/src/`:
- Create ModuleScript named `OpenRouterClient`
- Copy contents of `src/OpenRouterClient.lua`
- Paste and save

### Step 6: Verify Structure

Your Explorer should look EXACTLY like this:

```
Lux (Folder)
├── Main (Script)
└── src (Folder)
    ├── Core (Folder)
    │   ├── init (ModuleScript)
    │   ├── AgenticLoop (ModuleScript)
    │   ├── ApiClient (ModuleScript)
    │   ├── ConversationHistory (ModuleScript)
    │   └── MessageConverter (ModuleScript)
    ├── Memory (Folder)
    │   ├── init (ModuleScript)
    │   ├── WorkingMemory (ModuleScript)
    │   ├── DecisionMemory (ModuleScript)
    │   └── ProjectContext (ModuleScript)
    ├── Safety (Folder)
    │   ├── init (ModuleScript)
    │   ├── CircuitBreaker (ModuleScript)
    │   ├── OutputValidator (ModuleScript)
    │   ├── ErrorAnalyzer (ModuleScript)
    │   ├── ErrorPredictor (ModuleScript)
    │   └── ToolResilience (ModuleScript)
    ├── Context (Folder)
    │   ├── init (ModuleScript)
    │   ├── ContextSelector (ModuleScript)
    │   ├── SystemPrompt (ModuleScript)
    │   └── CompressionFallback (ModuleScript)
    ├── Planning (Folder)
    │   ├── init (ModuleScript)
    │   ├── TaskPlanner (ModuleScript)
    │   └── Verification (ModuleScript)
    ├── Tools (Folder)
    │   ├── init (ModuleScript) ← YOU'RE MISSING THIS ONE!
    │   ├── ToolExecutor (ModuleScript)
    │   ├── ToolDefinitions (ModuleScript)
    │   ├── ReadTools (ModuleScript)
    │   ├── WriteTools (ModuleScript)
    │   ├── ProjectTools (ModuleScript)
    │   └── ApprovalQueue (ModuleScript)
    ├── Coordination (Folder)
    │   ├── init (ModuleScript)
    │   └── SessionManager (ModuleScript)
    ├── UI (Folder)
    │   ├── init (ModuleScript)
    │   ├── Builder (ModuleScript)
    │   ├── ChatRenderer (ModuleScript)
    │   ├── InputApproval (ModuleScript)
    │   ├── UserFeedback (ModuleScript)
    │   ├── KeySetup (ModuleScript)
    │   ├── Create (ModuleScript)
    │   └── Components (ModuleScript)
    ├── Shared (Folder)
    │   ├── init (ModuleScript)
    │   ├── Constants (ModuleScript)
    │   ├── Utils (ModuleScript)
    │   ├── IndexManager (ModuleScript)
    │   └── MarkdownParser (ModuleScript)
    └── OpenRouterClient (ModuleScript)
```

### Step 7: Test Locally

1. Right-click the `Lux` folder
2. Save to Roblox → Save to your inventory (private)
3. Close Studio
4. Reopen Studio
5. Insert from your inventory
6. Run and check for errors

### Step 8: Publish

Only after local testing succeeds:
1. Right-click `Lux` folder
2. Save to Roblox → Update existing plugin
3. Wait 5 minutes for Roblox servers to sync
4. Test fresh install

## Common Mistakes

❌ **Naming init.lua instead of init**
- Wrong: `init.lua (ModuleScript)`
- Right: `init (ModuleScript)`

❌ **Using Script instead of ModuleScript**
- Wrong: `init (Script)`
- Right: `init (ModuleScript)`

❌ **Forgetting to add init to some folders**
- All 9 folders need init: Core, Memory, Safety, Context, Planning, Tools, Coordination, UI, Shared

❌ **Not copying file contents**
- Empty init files will cause errors
- Must paste the actual code from init.lua

## Quick Verification

Run this in Command Bar in Studio:

```lua
local src = game.ServerStorage.Lux.src -- or wherever you put it
for _, folder in ipairs(src:GetChildren()) do
    if folder:IsA("Folder") then
        local init = folder:FindFirstChild("init")
        if not init then
            warn("MISSING init in: " .. folder.Name)
        elseif not init:IsA("ModuleScript") then
            warn("Wrong type in " .. folder.Name .. ": " .. init.ClassName)
        else
            print("✓ " .. folder.Name .. " has init")
        end
    end
end
```

This will tell you exactly which folders are missing init ModuleScripts.

## Your Current Error

```
Script 'cloud_131392966327387.Lux.src.OpenRouterClient', Line 19
```

Line 19 of OpenRouterClient is:
```lua
local Tools = require(script.Parent.Tools)
```

This means `script.Parent.Tools` exists (it's a Folder), but when Roblox tries to require a Folder, it looks for `Tools.init` as a ModuleScript. **You don't have that**, so it fails.

## Fix Right Now

1. Open Roblox Studio
2. Find your Lux plugin in Explorer (or open the model)
3. Navigate to `Lux/src/Tools/`
4. Right-click Tools → Insert Object → ModuleScript
5. Rename to `init`
6. Open `src/Tools/init.lua` from your local files
7. Copy ALL contents, paste into the Roblox ModuleScript
8. Save
9. Repeat for all other folders if needed
10. Test again

After this, the error should either go away or show a different error (next missing init file).
