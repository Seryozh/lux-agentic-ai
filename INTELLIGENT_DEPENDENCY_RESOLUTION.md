# Intelligent Dependency Resolution for Lux v2

## Overview

**The Approach:** Agent reads code/metadata, infers dependencies, collects a "metadata basket," then requests all needed scripts at once.

**Why it works:** Reduces back-and-forth requests, gets everything needed in one shot, more efficient.

**Example:**
```
User: "Add double jump"

Agent reads code:
  PlayerMovement.lua has:
    - require(game:GetService("UserInputService"))
    - require(Humanoid)
    - humanoid:MoveTo()

Agent infers:
  "I need: PlayerMovement, Humanoid, Input"

Agent creates basket:
  ["PlayerMovement.lua", "Humanoid.lua", "Input.lua"]

Agent requests all at once:
  "Give me metadata for all 3, then full code"
```

---

## How Agent Infers Dependencies

### 1. From Code Analysis (Best)

Agent reads code and looks for:

```lua
-- Explicit requires
local Humanoid = require(game:GetService("ServerStorage").Humanoid)
→ Dependency: "Humanoid.lua" (or Humanoid module)

-- Service usage
game:GetService("UserInputService")
→ Dependency: "Input" (uses input, need input handler)

-- RemoteEvent references
local PlayerHit = ReplicatedStorage:WaitForChild("PlayerHit")
→ Dependency: "PlayerHit" event (may need event handler script)

-- Script references
game.Workspace.Enemy:WaitForChild("EnemyAI")
→ Dependency: "EnemyAI.lua"

-- Function calls
Physics.applyForce(direction)
→ Dependency: "Physics.lua" (exports applyForce)
```

### 2. From Metadata (Fast)

Agent reads script metadata:

```json
{
  "name": "PlayerMovement.lua",
  "imports": ["Humanoid", "Input", "Physics"],
  "exports": ["jump", "walk", "sprint"]
}
```

Agent thinks:
- "PlayerMovement imports Humanoid, Input, Physics"
- "I need those 3 too"

### 3. From Exports (Pattern Matching)

User asks: "Add double jump"

Agent searches metadata exports:
```
Jump-related exports:
  - PlayerMovement exports ["jump", "walk"]
  - Humanoid exports ["setVelocity", "getState"]
  - Animation exports ["play", "stop"]
```

Agent infers:
- "PlayerMovement handles jump"
- "Humanoid sets velocity"
- "Animation plays animation"
- "I need all 3"

---

## Building the Metadata Basket

### Step 1: Initial Query

```python
def build_metadata_basket(user_request, project_map, warm_scripts):
    """
    User says: "Add double jump"
    Agent builds basket of what might be needed
    """

    # What's already warm (in memory)?
    if "PlayerMovement.lua" in warm_scripts:
        # Already loaded, no need to request
        basket = set()
    else:
        # Cold start, need to find it
        basket = set()

    # Search project_map for relevant scripts
    keywords = extract_keywords(user_request)
    # "Add double jump" → ["jump", "double", "movement"]

    for script in project_map.scripts:
        # Check name
        if any(kw in script.name.lower() for kw in keywords):
            basket.add(script.name)

        # Check metadata exports
        if hasattr(script, "exports"):
            for export in script.exports:
                if any(kw in export.lower() for kw in keywords):
                    basket.add(script.name)

    return basket
```

Result: `{"PlayerMovement.lua", "Humanoid.lua", ...}`

### Step 2: Expand with Dependencies

```python
def expand_basket_with_deps(initial_basket, project_map, max_depth=2):
    """
    For each script in basket, add what it imports
    """

    basket = set(initial_basket)
    depth = 0

    while depth < max_depth:
        new_scripts = set()

        for script_name in basket:
            script = project_map.get_script(script_name)

            # Add imports
            if hasattr(script, "imports"):
                for imported in script.imports:
                    if imported not in basket:
                        new_scripts.add(imported)

        # Add new scripts to basket
        basket.update(new_scripts)
        depth += 1

    return basket
```

**Why max_depth?**
- Prevent infinite loops (circular deps)
- Prevent loading entire project (depth limit = 2-3 usually enough)
- Optimization: Don't follow too deep

Result: `{"PlayerMovement.lua", "Humanoid.lua", "Input.lua", "Physics.lua"}`

### Step 3: Confidence Scoring

```python
def score_basket_confidence(basket, user_request, project_map):
    """
    How confident are we this is the right set?
    """

    scores = {}

    for script in basket:
        confidence = 0

        # Direct keyword match = high confidence
        if has_keyword_match(script.name, user_request):
            confidence += 0.8

        # Export match = high confidence
        if has_export_match(script.exports, user_request):
            confidence += 0.7

        # Imported by relevant script = medium confidence
        if imported_by_relevant(script, basket):
            confidence += 0.3

        # Generic name (e.g., "Util") = lower confidence
        if is_generic_name(script.name):
            confidence -= 0.2

        scores[script] = min(confidence, 1.0)

    return scores
```

**Example:**
```
PlayerMovement: 0.9 (name match + export match)
Humanoid: 0.8 (export match + imported by PM)
Input: 0.7 (imported by PM)
Physics: 0.5 (imported by Humanoid, but generic)
Util: 0.2 (generic name, low confidence)
```

### Step 4: Filter by Confidence

```python
def filter_basket(scored_basket, threshold=0.5):
    """
    Only request high-confidence scripts
    Low confidence ones can be requested later if needed
    """

    high_confidence = {
        script: score
        for script, score in scored_basket.items()
        if score >= threshold
    }

    return high_confidence
```

Result: `{"PlayerMovement.lua": 0.9, "Humanoid.lua": 0.8, "Input.lua": 0.7}`

(Physics and Util filtered out)

---

## Request Strategy

### Option A: Request All at Once (Recommended)

```
Agent: "I need metadata for these 4 scripts:
        PlayerMovement.lua, Humanoid.lua, Input.lua, Physics.lua"

Plugin: Sends metadata for all 4

Agent reads metadata:
  PlayerMovement {exports: [...], imports: [...]}
  Humanoid {exports: [...], imports: [...]}
  Input {exports: [...], imports: [...]}
  Physics {exports: [...], imports: [...]}

Agent: "Confirmed, I need all 4. Request full code."

Plugin: Sends full code for all 4

Agent: Generates response
```

**Advantages:**
- Single request (efficient)
- Agent sees full dependency picture
- Can validate: "Do these all connect properly?"

**Cost:** ~3k tokens for metadata + ~10k for code

### Option B: Request in Waves (If Basket is Huge)

```
If basket > 20 scripts:
  Wave 1: Request metadata for top 10 (highest confidence)
  Agent reads metadata
  Agent: "I see, I also need these 5"
  Wave 2: Request full code for 10 + metadata for 5

If basket still growing:
  Wave 3: Request full code for final 5
```

**Advantages:**
- Manages context window size
- Avoids overwhelming agent

**Disadvantages:**
- Multiple requests (less efficient)
- Agent might miss deep dependencies

---

## Handling Edge Cases

### 1. Circular Dependencies

**Problem:**
```
A imports B
B imports A
→ Infinite loop
```

**Solution: Depth Limit + Visited Set**

```python
def expand_basket_with_deps(initial_basket, project_map, max_depth=2):
    basket = set(initial_basket)
    visited = set()
    depth = 0

    while depth < max_depth:
        new_scripts = set()

        for script_name in basket:
            if script_name in visited:
                continue  # Already processed, skip

            visited.add(script_name)

            script = project_map.get_script(script_name)
            for imported in script.imports:
                if imported not in basket:
                    new_scripts.add(imported)

        basket.update(new_scripts)
        depth += 1

    return basket
```

**Result:** Stops after depth 2, breaks circular loops.

### 2. Dynamic Imports

**Problem:**
```lua
-- At runtime, script loads things dynamically
local module = require(moduleName)  -- moduleName is a variable
```

**Solution: Heuristic + User Confirmation**

Agent can't know what `moduleName` is at analysis time.

Options:
```python
# Option A: Ignore dynamic imports
# "I see a dynamic import, might need it, skipping for now"

# Option B: Alert agent
# Agent: "I see dynamic import of variable X"
#        "Based on context, probably is ModuleY"
#        "Include ModuleY in basket?"

# Option C: User hints
# Metadata includes: "expected_dynamic_imports": ["ModuleX", "ModuleY"]
```

For MVP: **Ignore dynamic imports, document in basket as "might need more."**

### 3. False Positives

**Problem:**
```lua
-- Code mentions "Health" but not HealthModule
local msg = "Health bar is broken"

Agent thinks: "Need Health.lua"
Actually: Just a comment
```

**Solution: Code Pattern Analysis**

```python
def is_real_reference(script_content, identifier):
    """
    Is this identifier actually used, or just mentioned?
    """

    # Real usage patterns
    patterns = [
        f"require.*{identifier}",  # require(Health)
        f"local.*{identifier}",    # local Health = ...
        f":{identifier}",          # obj:Health()
        f"\.{identifier}",         # obj.Health
        f"game:GetService.*{identifier}",
    ]

    for pattern in patterns:
        if re.search(pattern, script_content):
            return True

    return False
```

Only include in basket if real usage is detected.

### 4. Missing Scripts

**Problem:**
```
Agent requests: ["PlayerMovement.lua", "NonExistent.lua", "Humanoid.lua"]
Plugin: "NonExistent.lua doesn't exist"
```

**Solution: Graceful Fallback**

```python
# Backend
requested = ["PlayerMovement.lua", "NonExistent.lua", "Humanoid.lua"]
available = []
missing = []

for script in requested:
    if plugin.script_exists(script):
        available.append(script)
    else:
        missing.append(script)

# Send what's available
backend.send(metadata_for=available)

# Tell agent about missing
backend.tell_agent(f"Couldn't find: {missing}")

# Agent handles it
agent.respond_to_missing(missing)
# "I was looking for NonExistent.lua but it doesn't exist"
# "I'll work with what I have"
```

---

## Token Efficiency Analysis

### Scenario: "Add double jump" request

**Without intelligent basket:**
```
Request 1: "What scripts exist?" (full structure)
  Cost: 20k tokens

Request 2: "What's metadata for PlayerMovement?"
  Cost: 2k tokens

Request 3: "What's metadata for Humanoid?"
  Cost: 2k tokens

Request 4: "Send me full code"
  Cost: 10k tokens

Total: 34k tokens
```

**With intelligent basket:**
```
Agent analyzes:
  "I need PlayerMovement, Humanoid, Input"
  Cost: 0 (no request, just analysis)

Request 1: "Send metadata for all 3 + full code for all 3"
  Cost: 12k tokens (metadata + code together)

Total: 12k tokens
Savings: 22k tokens (65% reduction)
```

---

## Accuracy Analysis

### How Often Does Basket Matching Work?

**Test case: Common Roblox requests**

```
Request: "Add jump"
Basket should include: Jump-related scripts
Accuracy: 95% (easy to match)

Request: "Make character faster"
Basket should include: Movement scripts
Accuracy: 80% (less obvious)

Request: "Improve game feel"
Basket should include: ??? (very ambiguous)
Accuracy: 40% (might need user clarification)

Request: "Add double jump"
Basket should include: Jump + Movement scripts
Accuracy: 85% (clear but needs depth-2 analysis)
```

**Real-world:** Accuracy improves with:
- Better metadata (exports/imports)
- Smarter confidence scoring
- User feedback ("Yes, that's relevant")

---

## Potential Holes & Limitations

### 1. **Over-Inclusive Basket**

```
User: "Add jump"

Agent builds: [PlayerMovement, Humanoid, Input, Physics, Animation, Audio, VFX]
(Assumes if touching movement, might need all related)

Result: 7 scripts instead of 3
Waste: Extra tokens
```

**Fix:** Stricter confidence thresholds, feedback from user

### 2. **Under-Inclusive Basket**

```
User: "Add combat"

Agent builds: [Combat, Damage]

But Combat.lua actually imports:
  - Humanoid (for damage targets)
  - Network (for multiplayer)
  - Audio (for hit sounds)

Agent didn't expand deep enough. Missing imports.

Result: Generated code has undefined variables
```

**Fix:** Increase max_depth from 2 to 3

### 3. **Script Dependencies on Non-Script Things**

```
Script imports:
  - Configuration (JSON file, not a script)
  - Data (database, not in project)
  - Asset (model, not a script)

Agent can't find these in project_map
Can't request them
```

**Fix:** Track non-script dependencies separately, document in metadata

### 4. **Metadata Staleness**

```
User edits PlayerMovement.lua:
  - Adds new export: "doubleJump"
  - Adds new import: "CooldownManager"

Metadata is stale. Agent doesn't know about these.
```

**Fix:** Regenerate metadata after each edit, or mark scripts as "modified, metadata stale"

### 5. **Context Window Limits**

```
Basket is 20 scripts
Full code for all 20: 50k tokens
Conversation history: 30k tokens
LangGraph state: 5k tokens

Total: 85k tokens of 100k context window
→ Very little room for response

Agent can't generate
```

**Fix:** Prioritize basket by relevance, request only top 10

### 6. **Agent Confusion with Ambiguous Requests**

```
User: "Add yellow things"

Agent basket confusion:
  - YellowUI.lua (UI elements)?
  - YellowFilter.lua (graphics)?
  - YellowTeam.lua (game logic)?

Agent picks wrong one.
```

**Fix:** Agent asks clarification: "Do you mean UI, graphics, or game logic?"

---

## Best Practices for Implementation

### 1. **Always Include High-Confidence Scripts**

```
Confidence >= 0.7: Include
0.3 to 0.7: Include if space available
< 0.3: Skip, request later if needed
```

### 2. **Respect Depth Limits**

```
max_depth = 2 for MVP
  (Catches direct dependencies + 1 level deep)

max_depth = 3 for optimization later
  (More thorough, higher token cost)
```

### 3. **Validate Basket Before Requesting**

```python
Agent thinks:
  "I need [A, B, C]"

Check:
  - Do all exist? (no missing scripts)
  - Do they connect? (A imports B, B imports C, makes sense)
  - Is basket size reasonable? (< 15 scripts usually good)

If issues:
  Remove questionable scripts
  Request core ones first
```

### 4. **Progressive Requests**

```
Message 1: Request [A, B, C] + metadata
Message 2: If needed, request [D, E]
Message 3: Generate

Not: Request everything at once
```

### 5. **Mark Warm Scripts**

```
Request:
  "Send metadata for [A, B, C]
   But I already have [X, Y] warm
   Don't resend those"

Plugin doesn't resend warm scripts
Backend doesn't re-tokenize them
```

---

## Summary: Does This Approach Work?

**Yes, with caveats:**

✅ **Reduces back-and-forth requests** — Single metadata + code request
✅ **Token efficient** — Only get what's needed
✅ **Handles dependencies** — Depth limits prevent issues
✅ **Graceful fallbacks** — Handles missing scripts
✅ **Context-aware** — Agent infers from conversation
✅ **Scalable** — Works with 100+ script projects

⚠️ **Potential issues:**
- Over/under-inclusive baskets (mitigated with confidence scoring)
- Metadata staleness (mark as stale, regenerate as needed)
- Context window pressure (prioritize, multiple waves)
- Ambiguous requests (ask for clarification)

**For MVP:** This approach is solid. Build it, iterate based on real usage.

**Long-term:** Add smarter dependency analysis, better confidence scoring, user feedback loops.

---

## Implementation Checklist

- [ ] Build dependency graph from metadata (imports/exports)
- [ ] Implement confidence scoring
- [ ] Handle circular dependencies (visited set + depth limit)
- [ ] Graceful handling of missing scripts
- [ ] Mark stale metadata after edits
- [ ] Request high-confidence scripts in one batch
- [ ] Progressive requests if basket > 15 scripts
- [ ] Log basket decisions (for debugging)
- [ ] Test with various request types (jump, combat, UI, etc.)

---

**This approach is sound. Build it.**
