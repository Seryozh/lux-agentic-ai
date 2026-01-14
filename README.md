# Lux Agentic AI

A Roblox AI agent system with memory, planning, and tool execution capabilities.

## Rojo Setup

This project uses Rojo to sync code into Roblox Studio.

### Installation

1. Install the Rojo VS Code extension from the marketplace: [Rojo - Roblox Studio Sync](https://marketplace.visualstudio.com/items?itemName=evaera.vscode-rojo)
2. The extension will automatically manage the Rojo server for you

### Usage

1. **Open the project in VS Code:**
   - Open this folder in VS Code
   - The Rojo extension will detect the `default.project.json` file

2. **Start syncing:**
   - Open the Command Palette (Ctrl/Cmd+Shift+P)
   - Run "Rojo: Start server"
   - Or click the "Start Rojo" button in the status bar

3. **Connect from Roblox Studio:**
   - Open your place in Roblox Studio
   - Install the Rojo Studio plugin if you haven't already
   - Click the Rojo plugin button and click "Connect"

3. **Your project structure in Studio:**
   ```
   ServerStorage
   ├── LuxAgenticAI (src folder)
   │   ├── Core
   │   ├── Memory
   │   ├── Safety
   │   ├── Context
   │   ├── Planning
   │   ├── Tools
   │   ├── Coordination
   │   ├── Shared
   │   └── UI
   └── Main (Main.lua)
   ```

### Building a Place File

To generate a `.rbxl` file:

```bash
rojo build -o lux-agentic-ai.rbxl
```

## Project Structure

- `src/` - Main source code organized into modules
  - `Core/` - Core agent functionality
  - `Memory/` - Memory management
  - `Safety/` - Safety checks and constraints
  - `Context/` - Context handling
  - `Planning/` - Planning system
  - `Tools/` - Tool definitions and execution
  - `Coordination/` - Multi-agent coordination
  - `Shared/` - Shared utilities and constants
  - `UI/` - User interface components
- `Main.lua` - Entry point script
- `default.project.json` - Rojo project configuration
