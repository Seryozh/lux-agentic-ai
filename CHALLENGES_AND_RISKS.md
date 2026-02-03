# Lux v2 - Challenges & Risks (Build-Phase Reality Check)

These are the real problems you'll hit during development. Reference this when building.

---

## 1. Plugin UX (Underestimated)

**The Problem:**
Making chat feel natural in Roblox Studio is harder than it sounds.

**Why It's Hard:**
- Roblox's UI framework (DockWidget) is limited
- No modern web UI tools (no React, no CSS)
- Manual scrolling, text input, button responsiveness
- Users expect smooth experience but Studio is clunky

**What Will Happen:**
- Scrolling feels janky
- Text input lags
- Buttons feel unresponsive
- Users get frustrated before trying feature

**How To Fix:**
- Keep UI simple (chat box, one "Generate" button)
- Don't try to make it pretty
- Functional > pretty
- Test in actual Studio early (day 2)
- If UI is slow, that's a backend/network problem, not UI problem

**Why It Matters:**
Users give up on broken UI before trying the AI.

---

## 2. Latency (Real Problem)

**The Problem:**
Request travels: Plugin → Backend → OpenRouter → Backend → Plugin

**Timeline:**
- User types and hits "Generate" (1 sec)
- Plugin sends HTTP to backend (0.5 sec)
- Backend processes request (1 sec)
- Backend calls OpenRouter (varies, 0.5-3 sec)
- OpenRouter thinks and generates (5-15 sec)
- Response streams back (0.5-2 sec)
- Plugin receives and renders (1 sec)
- **Total: 10-20 seconds**

**What Will Happen:**
- First time user hits "Generate"
- Waits 5 seconds, nothing happens
- Hits again
- Thinks it's broken
- Closes plugin
- Never comes back

**How To Fix:**
- Show loading indicator IMMEDIATELY (within 100ms)
- Show "Thinking..." or "Generating..." message
- Stream responses (show text as it arrives, not all at once)
- Set expectations upfront: "This takes 10-15 seconds"
- Maybe show fun tip while waiting

**Why It Matters:**
Perceived speed matters more than actual speed.

---

## 3. State Management (Subtle But Dangerous)

**The Problem:**
Metadata gets out of sync with actual code.

**Scenario:**
1. AI generates script, sets metadata
   ```
   PlayerMovement.lua
   metadata: {handles: ["jump", "walk"]}
   ```

2. User manually edits the script (adds "dash" feature)
   ```
   PlayerMovement.lua
   -- Now handles jump, walk, AND dash
   metadata: {handles: ["jump", "walk"]}  ← OUTDATED
   ```

3. User asks "Add double jump"
   ```
   AI reads metadata: "PlayerMovement handles jump already"
   AI thinks: "I'll add double-jump to it"
   But AI doesn't see the "dash" feature
   Conflict! Code breaks.
   ```

**What Will Happen:**
- After a few generations, metadata becomes garbage
- AI makes wrong decisions
- Code breaks mysteriously
- Users blame AI, not metadata

**How To Fix:**
- Metadata versioning (timestamp when updated)
- Before AI uses metadata, check: "Is this fresh?"
- If file was edited after metadata, re-scan it
- Show user: "I'm re-analyzing your scripts..."
- Let user manually refresh metadata if needed

**Why It Matters:**
Trust breaks down if AI makes wrong decisions based on stale info.

---

## 4. Error Handling (Complexity Explosion)

**The Problem:**
Too many things can fail. Each needs smart handling.

**Failure Scenarios:**

| Scenario | What User Sees | Bad vs. Good |
|----------|----------------|-------------|
| OpenRouter key invalid | "Error: 401" | vs. "Your API key isn't working. Check it in settings." |
| Generated code has syntax error | "Error: SyntaxError" | vs. "I generated invalid code. Let me fix it: [shows error]" |
| Metadata corrupted | Plugin crashes | vs. "Metadata is broken. Click to rebuild it." |
| Backend crashes | No response, hangs | vs. "Backend is down. Try again in a minute." |
| Network timeout | Hangs forever | vs. "Request timed out. This happens with slow internet. Retry?" |
| User OOMs (too much context) | Plugin freezes | vs. "Your project is too big. Analyze fewer scripts." |

**What Will Happen:**
First 5 errors, users get confused. By 10th error, they give up.

**How To Fix:**
- Each error needs a human-readable message
- Show what went wrong + how to fix it
- Log everything (for debugging)
- Graceful degradation (if metadata fails, disable that feature)
- Never show raw error codes to users

**Why It Matters:**
Good error messages = users think you're competent. Bad ones = you look broken.

---

## 5. Testing (The Hard Reality)

**The Problem:**
Hard to test without actual Roblox project and Studio.

**What You Can't Test:**
- How plugin looks/feels in actual Studio
- How slow the UI actually is
- Real network latency
- Edge cases with actual Roblox API
- User behavior (how people actually use it)

**What You Can Test:**
- Backend API (use curl/Postman)
- LangGraph decomposition (unit tests)
- Code validation logic (unit tests)
- Error handling (mocked scenarios)

**What Will Happen:**
- You build backend, think it's perfect
- Deploy plugin, find 5 bugs you didn't anticipate
- Have to rebuild, redeploy, test again

**How To Fix:**
- Test backend early and often (before plugin)
- Use Postman to simulate plugin requests
- Test plugin in actual Studio with test project (day 3)
- Don't wait for "done" to test
- Manual testing required (no full automation)

**Why It Matters:**
Finding bugs in week 2 is way easier than week 4.

---

## 6. Scope Creep (The Silent Killer)

**The Problem:**
Easy to say "oh we should also add X, Y, Z"

**What Will Happen:**
- "We should add multiplayer collaboration"
- "We should store patterns in Supabase"
- "We should make YouTube tutorials automatically"
- "We should support C#"
- Features explode
- Ship date moves from week 2 to week 6
- Burnout, quality drops

**How To Fix:**
- Look at the plan
- ONLY build Phase 1-4
- Say "no" to Phase 5 ideas
- Write them down for v2.1+
- Ship the MVP

**Why It Matters:**
Perfect later > broken never. Get something shipped.

---

## 7. Metadata Overhead (Performance)

**The Problem:**
Scanning all scripts on first run could be slow.

**Scenario:**
- Game has 200 scripts
- System scans all 200
- Takes 30 seconds
- User: "Why is this so slow?"

**How To Fix:**
- Show progress: "Scanning scripts... 45/200"
- Do it in background
- Cache results
- Let user cancel if needed

**Why It Matters:**
Users won't wait 30 seconds. They'll think it's broken.

---

## 8. Backend Deployment (Hidden Complexity)

**The Problem:**
Getting Python/LangGraph running on Vercel isn't trivial.

**Challenges:**
- Vercel free tier has limits (timeout, memory)
- Python/FastAPI needs specific setup
- LangGraph might be slow on serverless
- Cold starts (first request takes 5 seconds)

**How To Fix:**
- Test deployment early (week 1)
- Use Railway ($5/month) instead of Vercel if needed
- Profile performance (see where bottlenecks are)
- Cache responses if possible

**Why It Matters:**
Discovering backend won't deploy on week 3 is bad timing.

---

## 9. OpenRouter Rate Limits (Real Constraint)

**The Problem:**
OpenRouter has rate limits. If users hammer it, they'll hit limits.

**Scenario:**
- User asks for 10 features quickly
- Each request calls OpenRouter
- Rate limit hit
- User blocked temporarily

**How To Fix:**
- Document rate limits for users
- Queue requests (don't fire them all at once)
- Show user: "Waiting for previous request..."
- Cache responses (if same request made twice, reuse result)

**Why It Matters:**
Users shouldn't get blocked. It feels broken.

---

## 10. The Interview Question: "Why This Architecture?"

**They Will Ask:**
- "Why Python + LangGraph?"
- "Why metadata in Roblox attributes?"
- "Why decomposition before generation?"
- "What would you change?"

**How To Answer:**
- Be able to explain each choice
- Know the trade-offs
- "I chose X because Y. The downside is Z. Future version would..."
- Show you THOUGHT, not just followed instructions

**This Is How You Get Hired:**
Not the code. The reasoning.

---

## Summary: What Actually Matters

| Priority | What It Is | Why |
|----------|-----------|-----|
| 🔴 Critical | Latency UX (show loading ASAP) | Users give up if it feels broken |
| 🔴 Critical | Error messages (clear, helpful) | Users trust you if failures are clear |
| 🟠 High | Plugin testing (test day 2) | Can't ship broken plugin |
| 🟠 High | Backend API design (before building) | Everything depends on it |
| 🟠 High | Metadata sync (keep it fresh) | Stale data breaks AI decisions |
| 🟡 Medium | Scope creep (stick to plan) | Shipping matters more than features |
| 🟡 Medium | Deployment testing (test week 1) | Don't find issues week 4 |
| 🟢 Low | Perfect error handling (iterate) | Good enough for MVP |
| 🟢 Low | Performance optimization | Speed comes after working |

---

## Building Order (What To Do First)

1. **Week 1: Backend API Design**
   - Define endpoints
   - Design LangGraph loop
   - NO implementation yet, just plan

2. **Week 1-2: Backend Implementation**
   - Build FastAPI
   - Implement LangGraph
   - Build validation layer

3. **Week 2: Backend Testing**
   - Use Postman/curl
   - Test every endpoint
   - Fix bugs

4. **Week 2-3: Plugin Implementation**
   - Build UI
   - Connect to backend
   - Handle responses

5. **Week 3: Integration Testing**
   - Plugin + Backend together
   - Test in actual Studio
   - Fix real issues

6. **Week 4: Polish & Deploy**
   - Error handling
   - Edge cases
   - Deploy backend
   - Release plugin

---

## What Makes This Hireable

✅ You shipped something (works, even if MVP)
✅ You thought about architecture (not just hacked it)
✅ You handled real problems (latency, errors, testing)
✅ You documented everything (this file proves it)
✅ You can explain WHY you built it this way
✅ You know the limitations and next steps

❌ Perfect code
❌ 10,000 features
❌ Fancy UI
❌ Maximum performance

Choose the first 5.
