# Lux Agentic AI

A Roblox AI agent system with memory, planning, and tool execution capabilities.

## Rojo Setup

This project uses Rojo to sync code into Roblox Studio.

### Usage

The Rojo binary is included in the `Rojo/` folder. To start syncing:

1. **Start the Rojo server:**
   ```bash
   ./Rojo/rojo serve
   ```

   The server will start on `localhost:34872`

2. **Connect from Roblox Studio:**
   - Open your place in Roblox Studio
   - Install the Rojo Studio plugin: https://www.roblox.com/library/13916111004/Rojo-7-4
   - Click the Rojo plugin button and click "Connect"
   - Your code will now sync automatically!

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
