# Lux Plugin - Publishing Guide

## Critical: Folder Structure for Publishing

### The Problem
You renamed the Roblox Studio model folder from `Lux` to `LuxAgenticAI`. When you publish updates with a different folder name, users who have the old version cached will experience:
- Module loading errors ("Attempted to call require with invalid argument")
- Plugin button disappearing
- Complete plugin failure

### The Solution: Rename Back to "Lux"

**In Roblox Studio**, your plugin model hierarchy should be:

```
Lux (Folder)
├── Main (Script)
└── src (Folder)
    ├── Core (Folder)
    ├── Memory (Folder)
    ├── Safety (Folder)
    ├── Context (Folder)
    ├── Planning (Folder)
    ├── Tools (Folder)
    ├── Coordination (Folder)
    ├── UI (Folder)
    ├── Shared (Folder)
    └── OpenRouterClient (ModuleScript)
```

**Top-level folder MUST be named exactly: `Lux`**

This matches:
- `Constants.PLUGIN_NAME = "Lux"`
- Previous published versions
- User expectations

## Step-by-Step Publishing Process

### 1. Prepare the Model in Roblox Studio

1. **Open a blank Roblox Studio place**
2. **In Explorer**, right-click and create a new **Folder**
3. **Rename it to exactly: `Lux`** (case-sensitive)
4. **Copy all plugin files into this folder:**
   - Main.lua (as a Script)
   - src/ folder with all subfolders

### 2. Verify Structure

Before publishing, verify the structure is EXACTLY:
```
Lux/
├── Main (Script) ✓
└── src (Folder) ✓
    ├── Core (Folder) ✓
    ├── Memory (Folder) ✓
    ├── Safety (Folder) ✓
    ├── Context (Folder) ✓
    ├── Planning (Folder) ✓
    ├── Tools (Folder) ✓
    ├── Coordination (Folder) ✓
    ├── UI (Folder) ✓
    ├── Shared (Folder) ✓
    └── OpenRouterClient (ModuleScript) ✓
```

**Double-check:**
- Top folder is named `Lux` (not `LuxAgenticAI`, not `LuxPlugin`, just `Lux`)
- `Main` is a **Script**, not ModuleScript
- `src` is a **Folder**
- All subfolders are **Folders** containing ModuleScripts
- `OpenRouterClient.lua` is a **ModuleScript** directly in `src/`

### 3. Test Locally First

Before publishing to Creator Store:

1. **Right-click the `Lux` folder** → "Save to Roblox..."
2. **Save as a Model** to your inventory (private)
3. **Close Studio completely**
4. **Reopen Studio**
5. **Install from your saved model**
6. **Test that it loads without errors**

This mimics what users will experience.

### 4. Publish to Creator Store

1. **Right-click the `Lux` folder**
2. **Select "Save to Roblox..."**
3. **Choose "Update Existing"** (select your plugin from list)
4. **Update version in description**: Mention "v2.0.5 - Critical bug fix"
5. **Click Save**

### 5. Version Bump

Before publishing, update the version number:

**In `src/Shared/Constants.lua`:**
```lua
Constants.PLUGIN_VERSION = "2.0.5"  -- Update from "2.0.4"
```

### 6. Post-Publishing Verification

After publishing:

1. **Wait 5-10 minutes** for Roblox servers to sync
2. **Close Studio completely**
3. **Reopen Studio**
4. **Install from Creator Store** (like a fresh user would)
5. **Verify:**
   - Toolbar button appears
   - Plugin opens without errors
   - All features work

## What NOT to Do

❌ **Don't rename the top-level folder** after initial publish
❌ **Don't publish with different folder structure**
❌ **Don't skip local testing** before publishing
❌ **Don't forget to version bump**

## Fixing the Current Issue

### For You (Before Next Publish):
1. In Roblox Studio, rename `LuxAgenticAI` folder back to `Lux`
2. Verify structure matches guide above
3. Test locally
4. Bump version to 2.0.5
5. Publish as update

### For Users (Immediate Workaround):
Tell users to:
1. Completely close Studio
2. Uninstall Lux plugin
3. Restart Studio
4. Wait for your 2.0.5 update to publish
5. Reinstall from Creator Store

## Future Updates

For all future updates:
- **Keep folder name as `Lux`** forever
- Only change version number in Constants.lua
- Only modify files inside the structure, never the structure itself
- Test with fresh install before publishing to public

## Why This Matters

When users install plugins:
1. Roblox caches them as: `cloud_ASSETID.FolderName`
2. Scripts use relative requires: `script.Parent.src.Core`
3. Renaming folder → cache mismatch → require() fails
4. No error handling → button never created → looks like plugin disappeared

With your fix in Main.lua (pcall error handling), future issues will at least show an error button instead of silent failure.

---

## Current Publishing Checklist

Before you publish 2.0.5:

- [ ] Rename model folder to exactly `Lux` in Studio
- [ ] Update `Constants.PLUGIN_VERSION = "2.0.5"`
- [ ] Test locally by saving model and reinstalling
- [ ] Verify error handling works (temporarily break a module to test)
- [ ] Publish to Creator Store as update
- [ ] Test fresh install after publish
- [ ] Respond to winpo1 with updated instructions

---

**Remember:** The local file system folder (`lux-agentic-ai`) doesn't matter. What matters is the **Roblox Studio model folder name** that you right-click and publish.
