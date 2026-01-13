# Contributing to Lux

Thank you for your interest in contributing! This document provides guidelines for contributing to the Lux project.

## Code of Conduct

- Be respectful and constructive
- Focus on what is best for the community
- Show empathy towards other community members

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues. When creating a bug report, include:

- **Clear title** - Describe the issue concisely
- **Steps to reproduce** - Detailed steps to trigger the bug
- **Expected behavior** - What should happen
- **Actual behavior** - What actually happens
- **Environment** - OS, Studio version, plugin version
- **Error messages** - Full error text from Output window

**Bug Report Template:**
```markdown
**Bug Description:**
[Clear description of the issue]

**Steps to Reproduce:**
1. Open Studio with Lux installed
2. Send message: "..."
3. Observe error

**Expected:** [What should happen]
**Actual:** [What actually happens]

**Environment:**
- OS: Windows 11 / macOS 14
- Studio Version: 0.xxx
- Lux Version: 4.0

**Error Log:**
```
[Paste error from Output window]
```
```

### Suggesting Features

Feature requests are welcome! Include:

- **Use case** - Why is this feature needed?
- **Proposed solution** - How should it work?
- **Alternatives** - Other approaches you considered
- **Impact** - Who benefits and how?

### Pull Requests

#### Before Submitting

1. **Search existing PRs** - Avoid duplicates
2. **Open an issue first** - Discuss major changes
3. **Follow code style** - Match existing patterns
4. **Test thoroughly** - Verify in Studio

#### PR Guidelines

**Good PR:**
- Focused scope (one feature/fix per PR)
- Clear description of changes
- Links to related issues
- Test instructions included

**PR Template:**
```markdown
## Description
[What does this PR do?]

## Motivation
[Why is this change needed?]

## Related Issues
Fixes #123

## Testing
1. Open Studio
2. Test scenario: [...]
3. Verify: [...]

## Checklist
- [ ] Code follows project style
- [ ] Tested in Studio
- [ ] No breaking changes (or documented)
- [ ] Updated relevant documentation
```

### Code Style

**Lua Conventions:**
```lua
-- Use tabs for indentation (match Studio defaults)
-- PascalCase for modules/classes
local MyModule = {}

-- camelCase for functions and variables
local function doSomething(parameterName)
    local localVariable = "value"
end

-- SCREAMING_SNAKE_CASE for constants
local MAX_RETRIES = 3

-- Clear, descriptive names
local function calculateRelevanceScore() -- Good
local function calc() -- Bad

-- Document complex logic
-- Checks if script was modified since last read
if timestamp > lastReadTime then
    -- ...
end
```

**Comments:**
- Explain **why**, not **what**
- Document non-obvious behavior
- Keep comments concise and up-to-date

**Module Structure:**
```lua
--[[
    ModuleName.lua
    Brief description of module purpose
]]

local ModuleName = {}

-- Module dependencies
local SomeService = game:GetService("SomeService")
local OtherModule = require(script.Parent.OtherModule)

-- Private functions
local function helperFunction()
    -- Implementation
end

-- Public API
function ModuleName.publicFunction()
    -- Implementation
end

return ModuleName
```

### Testing

**Manual Testing Checklist:**
- [ ] Test in empty baseplate
- [ ] Test in project with 50+ scripts
- [ ] Test approval flow (approve/deny)
- [ ] Test undo functionality
- [ ] Test error scenarios
- [ ] Check Output window for errors
- [ ] Verify UI responsiveness

**Test Scenarios:**
```lua
-- Example test cases to verify manually

-- 1. Basic functionality
"Read my PlayerHealth script"
"Add a print statement to line 10"

-- 2. Error handling
"Modify a script that doesn't exist"
"Create instance with invalid parent"

-- 3. Multi-step tasks
"Create a shop UI with 6 items"
"Refactor this script to use ModuleScripts"
```

### Architecture Guidelines

**Adding New Features:**

1. **Plan first** - Consider impact on existing modules
2. **Minimal changes** - Don't refactor unrelated code
3. **Backwards compatible** - Preserve existing behavior
4. **Configurable** - Add Constants.lua option if appropriate
5. **Fail gracefully** - Handle errors without crashing

**Module Dependencies:**
- Keep dependencies minimal
- Avoid circular dependencies
- Use SessionManager for cross-module coordination

**Performance:**
- Minimize API calls (check cache first)
- Avoid blocking main thread (use task.spawn for heavy work)
- Clean up resources (connections, instances)

### Documentation

**Update Documentation When:**
- Adding new features → Update README.md
- Changing behavior → Update inline comments
- Adding configuration → Update Constants.lua comments
- Breaking changes → Update CHANGELOG.md

**Documentation Style:**
```lua
--[[
    Function description in one line

    @param paramName type - Description
    @return type - Description
]]
function ModuleName.functionName(paramName)
    -- Implementation
end
```

## Development Workflow

### Setting Up

```bash
# Clone repository
git clone https://github.com/yourusername/lux.git
cd lux

# Install in Roblox Studio
# Plugins folder location:
# Windows: %LOCALAPPDATA%\Roblox\Plugins
# macOS: ~/Documents/Roblox/Plugins

# Create symlink or copy to Plugins folder
```

### Making Changes

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Make changes
# ... edit files ...

# Test in Studio
# Reload Studio after each change

# Commit with clear message
git commit -m "Add: Brief description of change"

# Push to fork
git push origin feature/your-feature-name

# Open PR on GitHub
```

### Commit Message Format

```
Type: Brief description (50 chars max)

Detailed explanation if needed (wrap at 72 chars)

Fixes #123
```

**Types:**
- `Add:` New feature
- `Fix:` Bug fix
- `Update:` Modify existing feature
- `Refactor:` Code restructuring without behavior change
- `Docs:` Documentation only
- `Style:` Code style/formatting
- `Test:` Add or update tests
- `Chore:` Maintenance tasks

## Release Process

(For maintainers)

1. Update version in Constants.lua
2. Update CHANGELOG.md
3. Test thoroughly in Studio
4. Create release on GitHub
5. Upload to Creator Store
6. Update DevForum thread

## Questions?

- **General questions**: [DevForum Thread](https://devforum.roblox.com/t/lux-cursorclaude-code-but-for-roblox-free-plugin/4207506)
- **Bug reports**: [GitHub Issues](https://github.com/yourusername/lux/issues)
- **Feature discussions**: [GitHub Discussions](https://github.com/yourusername/lux/discussions)

Thank you for contributing to Lux! 🚀
