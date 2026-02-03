# Contributing to Lux (Luxembourg)

First off, thank you for considering contributing to Lux! It's people like you that make Lux such a great tool for the Roblox developer community.

## 🌟 Ways to Contribute

There are many ways to contribute to Lux:

- **Bug Reports**: Submit detailed bug reports with reproduction steps
- **Feature Requests**: Propose new features or improvements
- **Code Contributions**: Submit pull requests with bug fixes or features
- **Documentation**: Improve documentation, add examples, fix typos
- **Testing**: Test the plugin in different scenarios and report issues
- **Feedback**: Share your experience using Lux

## 🐛 Reporting Bugs

Before submitting a bug report:
1. **Check existing issues** to see if it's already been reported
2. **Use the latest version** to ensure the bug hasn't been fixed
3. **Collect information** about your environment

### Bug Report Template

```markdown
## Description
A clear description of the bug.

## Steps to Reproduce
1. Open Roblox Studio
2. Type "..."
3. Click "Apply"
4. See error

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Environment
- Lux Version: [e.g., 1.0.0]
- Roblox Studio Version: [e.g., 0.612.0]
- Operating System: [e.g., Windows 11, macOS 14]
- Backend URL: [Production/Local]

## Screenshots/Logs
If applicable, add screenshots or log output.
```

## 💡 Feature Requests

We love feature ideas! Before submitting:
1. **Search existing issues** to avoid duplicates
2. **Be specific** about the use case and benefits
3. **Consider alternatives** you've thought about

### Feature Request Template

```markdown
## Feature Description
A clear description of the feature.

## Use Case
Why this feature would be useful. What problem does it solve?

## Proposed Solution
How you envision this working (if you have ideas).

## Alternatives Considered
Other approaches you've thought about.

## Additional Context
Any other information, mockups, or examples.
```

## 🔨 Code Contributions

### Development Setup

#### Backend
```bash
# Clone repository
git clone https://github.com/Seryozh/lux-agentic-ai.git
cd lux-agentic-ai/backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment template
cp .env.example .env

# Run development server
python main.py
```

#### Plugin
```bash
# Install Rojo
# https://rojo.space/docs/v7/getting-started/installation/

# Build plugin
cd plugin
rojo build -o Luxembourg.rbxm

# Or use Rojo sync for live development
rojo serve
```

### Coding Standards

#### Python (Backend)
- **Style**: Follow [PEP 8](https://pep8.org/)
- **Type Hints**: Use type hints for all function signatures
- **Docstrings**: Use Google-style docstrings
- **Formatting**: Use `black` for code formatting
- **Linting**: Use `ruff` or `flake8`

Example:
```python
async def get_full_script(session: Session, script_name: str) -> str:
    """
    Retrieves full source code for a script from the plugin.

    Args:
        session: Active session containing request handlers
        script_name: Name or path of the script to retrieve

    Returns:
        Full source code as a string

    Raises:
        TimeoutError: If plugin doesn't respond within timeout
    """
    # Implementation...
```

#### Lua (Plugin)
- **Style**: Follow [Roblox Lua Style Guide](https://roblox.github.io/lua-style-guide/)
- **Comments**: Use clear, descriptive comments
- **Error Handling**: Wrap HTTP calls in `pcall`
- **Naming**: Use camelCase for variables, PascalCase for modules

Example:
```lua
--[[
    Sends a chat message to the backend and returns the response.

    @param sessionId string - Unique session identifier
    @param message string - User's message
    @param projectMap string - Current project structure
    @param apiKey string - OpenRouter API key
    @return table|nil, string|nil - Response data or nil, error message
]]
function Backend.sendChat(sessionId, message, projectMap, apiKey)
    -- Implementation...
end
```

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding/updating tests
- `chore`: Maintenance tasks

**Examples**:
```
feat(agent): add support for Claude models

Adds Claude Opus and Sonnet as alternative models to Gemini.
Users can now select their preferred model in plugin settings.

Closes #42
```

```
fix(session): prevent memory leak from uncleaned sessions

Implements background task to clean up sessions older than 1 hour.
Adds session_ttl configuration parameter.

Fixes #38
```

### Pull Request Process

1. **Fork the repository** and create your branch from `main`
   ```bash
   git checkout -b feat/my-new-feature
   ```

2. **Make your changes**
   - Write clean, commented code
   - Follow coding standards
   - Add tests if applicable

3. **Test your changes**
   - Ensure backend still runs without errors
   - Test plugin functionality in Roblox Studio
   - Run any existing tests

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add my new feature"
   ```

5. **Push to your fork**
   ```bash
   git push origin feat/my-new-feature
   ```

6. **Submit a Pull Request**
   - Use a clear, descriptive title
   - Fill out the PR template
   - Link related issues
   - Add screenshots/demos if applicable

### Pull Request Template

```markdown
## Description
Brief description of what this PR does.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Related Issues
Closes #[issue number]

## Testing
How has this been tested?
- [ ] Backend tests pass
- [ ] Plugin builds successfully
- [ ] Tested in Roblox Studio
- [ ] Tested with [specific scenarios]

## Screenshots/Videos
If applicable, add screenshots or demo videos.

## Checklist
- [ ] My code follows the project's style guidelines
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have updated the documentation accordingly
- [ ] My changes generate no new warnings or errors
- [ ] I have tested my changes thoroughly
```

## 🧪 Testing

Currently, the project doesn't have a comprehensive test suite. **Adding tests is a great way to contribute!**

Desired test coverage:
- [ ] Backend API endpoint tests
- [ ] Agent orchestration tests
- [ ] Session management tests
- [ ] Tool function tests
- [ ] Pydantic model validation tests
- [ ] Plugin HTTP client tests
- [ ] Action executor tests

Example test structure:
```python
# tests/test_session.py
import pytest
from backend.session import get_or_create_session, cleanup_expired_sessions

def test_create_session():
    session = get_or_create_session("test-id", "test-key")
    assert session.session_id == "test-id"
    assert session.openrouter_key == "test-key"

def test_session_cleanup():
    # Create old session
    # Wait for TTL
    # Run cleanup
    # Assert session removed
    pass
```

## 📖 Documentation

Documentation improvements are always welcome:

- **README.md**: Main project documentation
- **CONTRIBUTING.md**: This file (you're reading it!)
- **Code Comments**: Inline documentation
- **textbooks/README_LUXEMBOURG.md**: Technical architecture deep-dive

When updating documentation:
- Use clear, simple language
- Add code examples where helpful
- Keep formatting consistent
- Check for typos and grammar

## 🎨 Design Philosophy

When contributing, keep these principles in mind:

**User Control**: Users should always review and approve changes before execution

**Privacy First**: No server-side data storage, BYOK design, minimal data collection

**Cost Optimization**: Minimize API calls and token usage where possible

**Simplicity**: Simple solutions are better than complex ones

**Reliability**: Graceful error handling, clear error messages, no crashes

## 💬 Community

- **Discussions**: Use GitHub Discussions for questions and ideas
- **Issues**: Use GitHub Issues for bugs and feature requests
- **Discord**: [Coming soon] Join our community Discord

## 📜 Code of Conduct

### Our Pledge

We are committed to providing a welcoming and inclusive environment for everyone, regardless of:
- Age, body size, disability, ethnicity, gender identity and expression
- Level of experience, nationality, personal appearance, race, religion
- Sexual identity and orientation

### Our Standards

**Positive behaviors**:
- Using welcoming and inclusive language
- Being respectful of differing viewpoints
- Gracefully accepting constructive criticism
- Focusing on what's best for the community
- Showing empathy towards others

**Unacceptable behaviors**:
- Trolling, insulting/derogatory comments, personal or political attacks
- Public or private harassment
- Publishing others' private information without permission
- Other conduct which could reasonably be considered inappropriate

### Enforcement

Violations may result in:
1. Warning
2. Temporary ban
3. Permanent ban

Report violations by opening a GitHub issue.

## 🏆 Recognition

Contributors will be recognized in:
- README.md acknowledgments section
- Release notes for their contributions
- Project credits

Top contributors may be invited to become maintainers.

## ❓ Questions?

Feel free to:
- Open a GitHub Discussion
- Open a GitHub Issue

---

**Thank you for contributing to Lux!** 🚀

Together, we're making Roblox game development more accessible and efficient for everyone.
