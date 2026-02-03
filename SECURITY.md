# Security Policy

## 🔒 Security Overview

Lux (Luxembourg) takes security and privacy seriously. This document outlines our security practices and how to report vulnerabilities.

## 🛡️ Security Features

### Privacy-First Design
- **BYOK (Bring Your Own Key)**: Users provide their own OpenRouter API keys
- **No Server-Side Key Storage**: API keys are never stored on the backend
- **No Data Retention**: User messages and game data are not persisted
- **Session Cleanup**: Sessions expire after 1 hour of inactivity

### Input Validation
- **Pydantic Models**: All API requests validated with strict schemas
- **Field Constraints**: Length limits, type checking, pattern validation
- **Sanitization**: API keys validated before use

### Network Security
- **CORS Configuration**: Controlled cross-origin resource sharing
- **HTTPS Only**: Production backend uses secure connections
- **Request Timeouts**: All requests have configurable timeouts
- **Rate Limiting**: (Recommended for production deployments)

### Error Handling
- **No Information Leakage**: Error messages don't expose internal details
- **Comprehensive Logging**: Server-side logging for debugging
- **Graceful Degradation**: Failures don't crash the server

## 🔍 Security Considerations

### API Key Handling
- API keys are transmitted with each request (necessary for stateless architecture)
- Keys are only stored in memory during active sessions
- Keys are cleared when sessions expire
- **Recommendation**: Use environment-specific keys (development vs production)

### Plugin Security
- Plugin runs in Roblox Studio's sandbox environment
- Cannot access files outside Roblox Studio
- HTTP requests are controlled by Roblox's HttpService
- All user actions require explicit approval

### Backend Security
- Backend is stateless (can be scaled horizontally)
- No database = no SQL injection risk
- Minimal attack surface
- **Recommendation**: Deploy behind a reverse proxy (nginx, Cloudflare)

## 🚨 Reporting a Vulnerability

We take all security vulnerabilities seriously. If you discover a security issue, please report it responsibly.

### Reporting Process

**DO:**
1. **GitHub Issue**: Open a security advisory on GitHub
2. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if you have one)
3. **Wait**: Give us at least 48 hours to respond before public disclosure

**DON'T:**
- Don't open a public GitHub issue for security vulnerabilities
- Don't disclose the vulnerability publicly until we've had a chance to fix it
- Don't test vulnerabilities on the production server without permission

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 1-7 days
  - High: 1-2 weeks
  - Medium: 2-4 weeks
  - Low: Next release cycle

### Disclosure Policy

- We will acknowledge your contribution (unless you prefer to remain anonymous)
- We will credit you in the release notes (with your permission)
- We will coordinate disclosure timing with you

## 🎖️ Security Hall of Fame

We'll recognize security researchers who responsibly disclose vulnerabilities:

<!-- No vulnerabilities reported yet -->

## 🔐 Best Practices for Users

### API Key Security
- ✅ Use dedicated API keys for Lux (not shared with other apps)
- ✅ Use OpenRouter's usage limits to cap spending
- ✅ Rotate keys periodically
- ✅ Monitor API usage on OpenRouter dashboard
- ❌ Don't share your API key with others
- ❌ Don't commit API keys to version control
- ❌ Don't use production keys for testing

### Development Security
- ✅ Use local backend for development and testing
- ✅ Keep dependencies up to date (`pip install --upgrade -r requirements.txt`)
- ✅ Review actions before clicking "Apply"
- ✅ Backup your game before making AI modifications
- ❌ Don't run untrusted modifications of the plugin
- ❌ Don't disable action approval workflow

### Deployment Security
- ✅ Use HTTPS for production backend
- ✅ Set up firewall rules to restrict access
- ✅ Enable logging and monitoring
- ✅ Set appropriate CORS origins (not `*` in production)
- ✅ Use environment variables for configuration
- ❌ Don't expose `.env` file publicly
- ❌ Don't run backend as root
- ❌ Don't disable CORS (security measure)

## 🔄 Security Updates

Security updates will be released as soon as possible after a vulnerability is confirmed:

1. **Critical Vulnerabilities**: Immediate patch release
2. **High Severity**: Emergency patch within 1 week
3. **Medium Severity**: Included in next scheduled release
4. **Low Severity**: Included in next minor version

Security releases will be tagged with version bumps and documented in [CHANGELOG.md](CHANGELOG.md).

## 📜 Security Audit

Lux has not undergone a formal security audit. We welcome security researchers to review the codebase and report findings.

**Areas of Interest:**
- [ ] API key handling and transmission
- [ ] Session management and cleanup
- [ ] Input validation and sanitization
- [ ] Error handling and information disclosure
- [ ] Plugin sandboxing and permissions
- [ ] Dependency security (supply chain)

## 🛠️ Dependency Security

We monitor dependencies for known vulnerabilities:

- **Backend**: Python packages tracked via pip
- **Plugin**: Pure Lua (no external dependencies)
- **Recommended**: Use `pip-audit` or `safety` to check dependencies

```bash
pip install pip-audit
pip-audit -r backend/requirements.txt
```

## 📞 Contact

For security-related inquiries:
- **GitHub Security Advisories**: Use the Security tab on the repository

For general questions, use [GitHub Issues](https://github.com/Seryozh/lux-agentic-ai/issues).

---

**Thank you for helping keep Lux secure!** 🛡️
