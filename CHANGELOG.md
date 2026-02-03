# Changelog

All notable changes to Lux (Luxembourg) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive project documentation (README.md, CONTRIBUTING.md)
- Issue templates for bug reports and feature requests
- Pull request template
- Environment configuration via .env file
- Session cleanup with configurable TTL
- Input validation with Pydantic validators
- Improved .gitignore for Python and Roblox projects

### Changed
- Made all hardcoded configuration values environment-based
- Added max retry limit for JSON parsing (prevents infinite loops)
- Improved error messages and exception handling
- Updated Backend.lua with clear comments for URL configuration

### Fixed
- Added CORS middleware for cross-origin requests
- Fixed potential memory leak from uncleaned sessions
- Added proper docstrings to all API endpoints
- Standardized tool parameter names with fallbacks

### Security
- Added API key validation
- Improved request validation to prevent malformed inputs

## [1.0.0] - 2024-XX-XX

### Added
- Initial release
- Natural language game modification for Roblox Studio
- Two-model architecture (orchestrator + worker) for cost optimization
- Polling bridge pattern for bidirectional communication over one-way HTTP
- 8 action types: set_property, create_instance, delete_instance, move_instance, clone_instance, create_script, modify_script, delete_script
- User approval workflow with Apply/Skip/Deny All buttons
- Project-aware AI with three-level exploration (structure → metadata → code)
- Intelligent caching for metadata and script contents
- BYOK (Bring Your Own Key) design for privacy
- FastAPI backend with LangGraph agent orchestration
- Lua plugin for Roblox Studio
- Session management with asyncio synchronization
- Comprehensive logging for debugging

### Technical Highlights
- LangGraph state machine for agent flow
- AsyncIO event-based polling synchronization
- Pydantic models for request/response validation
- Background task for periodic maintenance
- Configurable timeouts and retry limits
- Railway deployment configuration

---

## Release Notes Format

### Added
New features and capabilities

### Changed
Changes to existing functionality

### Deprecated
Features that will be removed in future versions

### Removed
Removed features

### Fixed
Bug fixes

### Security
Security improvements and vulnerability patches

---

[Unreleased]: https://github.com/Seryozh/lux-agentic-ai/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Seryozh/lux-agentic-ai/releases/tag/v1.0.0
