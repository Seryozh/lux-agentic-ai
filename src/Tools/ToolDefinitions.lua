--[[
    ToolDefinitions.lua
    Gemini API tool declarations with RICH EXAMPLES (Optimized V4)

    v4.0 Changes:
    - Added PRECONDITIONS for each tool (LLM-readable requirements)
    - Added CHAIN hints to suggest follow-up tools
    - Added cost tier metadata comments
    - Improved descriptions for better LLM understanding

    PRECONDITION FORMAT:
    Each tool may include a `preconditions` array with declarative requirements.
    These are checked by OutputValidator before tool execution.
    Format: { check = "type", ... type-specific params ... }

    Check types:
    - path_exists: Verify a path exists { check = "path_exists", param = "path" }
    - path_read: Verify path was read recently { check = "path_read", param = "path" }
    - parent_exists: Verify parent path exists { check = "parent_exists", param = "parent" }
    - not_placeholder: Verify param isn't a placeholder { check = "not_placeholder", param = "name" }
    - script_fresh: Script was read and not modified since { check = "script_fresh", param = "path" }
]]

return {
	-- TIER 1: Read-only, fast, safe
	{
		name = "get_script",
		description = "Get the complete source code of a script. ALWAYS read a script before editing it.\n\n" ..
			"WORKFLOW:\n" ..
			"  Before: Use list_children if unsure about path\n" ..
			"  During: Read and analyze current state\n" ..
			"  After: Use patch_script for edits OR search_scripts to find references\n\n" ..
			"CHAIN: After reading, you can use patch_script for small changes or edit_script for rewrites.",
		parameters = {
			type = "object",
			properties = { path = { type = "string", description = "Script path (e.g., 'ServerScriptService.DataHandler')" } },
			required = { "path" }
		},
		-- No preconditions - this is a read operation
		preconditions = {},
		llm_hints = {
			"MANDATORY: Use this BEFORE any patch_script or edit_script call",
			"Store the result - you'll need EXACT content for patching",
			"This is safe to call - it only reads, doesn't modify",
			"If path doesn't exist, you'll get an error - use list_children first if unsure"
		},
		anti_patterns = {
			"Editing scripts without reading them first",
			"Reading once at start of conversation then editing 10 messages later",
			"Assuming you know the content from a previous session"
		}
	},

	{
		name = "get_instance",
		description = "Get detailed information about any Instance including its properties. Use this to inspect Parts, GUI elements, Models, etc.\n\n" ..
			"EXAMPLES:\n" ..
			"1. Check Part properties: get_instance({path='Workspace.SpawnPoint'})\n" ..
			"2. Inspect specific props: get_instance({path='StarterGui.Menu.Frame', properties=['Size','Visible','BackgroundColor3']})",
		parameters = {
			type = "object",
			properties = {
				path = { type = "string", description = "Instance path (e.g., 'Workspace.SpawnPoint')" },
				properties = {
					type = "array",
					items = { type = "string" },
					description = "Optional: specific property names to read. If omitted, returns common properties."
				}
			},
			required = { "path" }
		},
		preconditions = {},
		llm_hints = {
			"Safe read operation - won't modify anything",
			"Use to verify instance exists before modifying it",
			"Returns class info, parent, and key properties"
		}
	},

	{
		name = "list_children",
		description = "List all children of an Instance with summary info. Great for exploring game structure.\n\n" ..
			"EXAMPLES:\n" ..
			"1. See what's in Workspace: list_children({path='Workspace'})\n" ..
			"2. List only scripts: list_children({path='ServerScriptService', classFilter='Script'})",
		parameters = {
			type = "object",
			properties = {
				path = { type = "string", description = "Instance path to list children of" },
				classFilter = { type = "string", description = "Optional: only show children of this class (e.g., 'BasePart', 'GuiObject')" }
			},
			required = { "path" }
		},
		preconditions = {},
		llm_hints = {
			"Start here when exploring an unfamiliar area",
			"Use before create_instance to verify parent exists",
			"classFilter is powerful - use 'Script' to find all scripts"
		}
	},

	{
		name = "get_descendants_tree",
		description = "Get a hierarchical tree view of an Instance and its descendants. Perfect for understanding UI or Model structure.\n\n" ..
			"EXAMPLES:\n" ..
			"1. Map UI structure: get_descendants_tree({path='StarterGui.MainMenu', maxDepth=4})\n" ..
			"2. See model contents: get_descendants_tree({path='Workspace.PlayerHouse'})",
		parameters = {
			type = "object",
			properties = {
				path = { type = "string", description = "Root instance path" },
				maxDepth = { type = "number", description = "Max depth to traverse (default 3)" },
				classFilter = { type = "string", description = "Optional: only include instances of this class" }
			},
			required = { "path" }
		},
		preconditions = {},
		llm_hints = {
			"Great for understanding complex UI hierarchies",
			"Keep maxDepth <= 4 for readability",
			"Use to find the exact path to a nested element"
		}
	},

	{
		name = "patch_script",
		description = "Surgically replace a specific block of code. PREFERRED over editing the whole file.\n" ..
			"BEST PRACTICES:\n" ..
			"- Include 2-3 lines of context in search_content\n" ..
			"- search_content must handle indentation EXACTLY as it appears",
		parameters = {
			type = "object",
			properties = {
				path = { type = "string", description = "Script path" },
				search_content = { type = "string", description = "EXACT code to find (copy-paste from get_script output)" },
				replace_content = { type = "string", description = "New code to insert" }
			},
			required = {"path", "search_content", "replace_content"}
		},
		preconditions = {
			{ check = "path_read", param = "path", message = "You must read a script with get_script before patching it" },
			{ check = "script_fresh", param = "path", message = "Script may have changed since you read it - re-read first" },
			{ check = "not_placeholder", param = "search_content", message = "search_content looks like a placeholder" },
			{ check = "not_placeholder", param = "replace_content", message = "replace_content looks like a placeholder" }
		},
		llm_hints = {
			"CRITICAL: Always get_script first to see current code",
			"Copy search_content EXACTLY from get_script output (including whitespace)",
			"If search fails, re-read the script - it may have changed"
		}
	},

	{
		name = "create_script",
		description = "Create a new script. REMEMBER: Creating it is only step 1. You MUST verify it loads afterwards.",
		parameters = {
			type = "object",
			properties = {
				path = { type = "string" },
				scriptType = { type = "string", enum = { "Script", "LocalScript", "ModuleScript" } },
				source = { type = "string" },
				purpose = { type = "string" }
			},
			required = { "path", "scriptType", "source", "purpose" }
		},
		preconditions = {
			{ check = "parent_exists", param = "path", message = "Parent container doesn't exist - verify path or create parent first" },
			{ check = "path_not_exists", param = "path", message = "A script already exists at this path - use patch_script or edit_script instead" },
			{ check = "not_placeholder", param = "source", message = "source looks like placeholder content" },
			{ check = "not_placeholder", param = "purpose", message = "purpose looks like a placeholder" }
		},
		llm_hints = {
			"Use list_children first to verify parent exists",
			"Script vs LocalScript: Script=server, LocalScript=client",
			"ModuleScript can run on either but must be required()"
		}
	},

	{
		name = "edit_script",
		description = "Rewrite an entire script. Only use for massive changes (>90%) where patching is too complex.",
		parameters = {
			type = "object",
			properties = {
				path = { type = "string" },
				newSource = { type = "string" },
				explanation = { type = "string" }
			},
			required = { "path", "newSource", "explanation" }
		},
		preconditions = {
			{ check = "path_exists", param = "path", message = "Script doesn't exist - use create_script instead" },
			{ check = "path_read", param = "path", message = "You must read a script with get_script before rewriting it" },
			{ check = "script_fresh", param = "path", message = "Script may have changed since you read it - re-read first" },
			{ check = "not_placeholder", param = "newSource", message = "newSource looks like placeholder content" }
		},
		llm_hints = {
			"Prefer patch_script for targeted changes",
			"Use edit_script only when >90% of script is changing",
			"Always preserve critical existing logic unless explicitly changing it"
		}
	},

	{
		name = "create_instance",
		description = "Create a new Instance (Part, Frame, etc). Requires className, parent path, and name.\n\n" ..
			"EXAMPLES:\n" ..
			"1. Create a Part: create_instance({className='Part', parent='Workspace', name='SpawnPlatform', properties={Size='10,1,10', Anchored=true, BrickColor='Bright green'}})\n" ..
			"2. Create a Frame: create_instance({className='Frame', parent='StarterGui.MainMenu', name='Header', properties={Size='0,0,1,50', BackgroundColor3='45,45,45'}})\n" ..
			"3. Create a ScreenGui: create_instance({className='ScreenGui', parent='StarterGui', name='HUD'})\n" ..
			"4. Create UICorner: create_instance({className='UICorner', parent='StarterGui.HUD.Frame', name='Corner', properties={CornerRadius='0,8'}})\n\n" ..
			"?? IMPORTANT - CLASS-AWARE PROPERTY TYPES:\n" ..
			"Size and Position mean DIFFERENT THINGS on different classes!\n" ..
			"- On GUI (Frame, TextLabel, etc.): Size/Position use UDim2 (4 numbers)\n" ..
			"- On Parts/Models: Size/Position use Vector3 (3 numbers)\n\n" ..
			"PROPERTY VALUE FORMATS:\n" ..
			"- UDim2 (GUI Size/Position): 'ScaleX,OffsetX,ScaleY,OffsetY' (e.g., '0,100,0,50' = 100px wide, 50px tall)\n" ..
			"- UDim (CornerRadius, Padding): 'Scale,Offset' (e.g., '0,8') or just '8' for offset-only\n" ..
			"- Vector3 (Part Size/Position): 'X,Y,Z' (e.g., '10,5,20')\n" ..
			"- Vector2 (AnchorPoint): 'X,Y' (e.g., '0.5,0.5')\n" ..
			"- Color3: 'R,G,B' in 0-255 (e.g., '255,128,0') or hex '#FF8000'\n" ..
			"- Boolean: true or false (not strings)\n" ..
			"- Number: just the number (e.g., 0.5, 100)\n" ..
			"- BrickColor: color name string (e.g., 'Bright red')\n" ..
			"- Enum: value name only (e.g., 'Neon' for Material)",
		parameters = {
			type = "object",
			properties = {
				className = { type = "string", description = "Roblox class name (e.g., 'Part', 'Frame', 'TextLabel', 'ScreenGui')" },
				parent = { type = "string", description = "Path to parent instance (e.g., 'Workspace', 'StarterGui.MainMenu')" },
				name = { type = "string", description = "Name for the new instance" },
				properties = {
					type = "object",
					description = "Key-value pairs of properties to set. The parser is CLASS-AWARE and will interpret Size/Position correctly based on className."
				}
			},
			required = { "className", "parent", "name" }
		},
		preconditions = {
			{ check = "parent_exists", param = "parent", message = "Parent path doesn't exist - verify with list_children first" },
			{ check = "valid_classname", param = "className", message = "Invalid Roblox class name" },
			{ check = "not_placeholder", param = "name", message = "name looks like a placeholder" }
		},
		llm_hints = {
			"Use list_children to verify parent exists first",
			"For GUI: Frame goes in ScreenGui, not directly in StarterGui",
			"Check className spelling - 'TextButton' not 'textbutton'"
		}
	},

	{
		name = "set_instance_properties",
		description = "Modify properties of an existing Instance.\n\n" ..
			"EXAMPLES:\n" ..
			"1. Resize a Frame (GUI - uses UDim2): set_instance_properties({path='StarterGui.MainMenu.Frame', properties={Size='0.5,0,0.5,0', BackgroundColor3='100,150,200'}})\n" ..
			"2. Move a Part (uses Vector3): set_instance_properties({path='Workspace.SpawnPoint', properties={Position='0,10,0', Size='4,1,4'}})\n" ..
			"3. Update text label: set_instance_properties({path='StarterGui.HUD.ScoreLabel', properties={Text='Score: 0', TextColor3='255,255,255', TextSize=24}})\n" ..
			"4. Set UICorner radius: set_instance_properties({path='StarterGui.HUD.Frame.Corner', properties={CornerRadius='0,12'}})\n\n" ..
			"?? IMPORTANT - CLASS-AWARE PROPERTY TYPES:\n" ..
			"The parser automatically detects the instance class and interprets values accordingly.\n" ..
			"- Frame.Size expects UDim2 (4 numbers: scaleX,offsetX,scaleY,offsetY)\n" ..
			"- Part.Size expects Vector3 (3 numbers: X,Y,Z)\n" ..
			"- UICorner.CornerRadius expects UDim (2 numbers: scale,offset OR just offset)\n\n" ..
			"PROPERTY VALUE FORMATS:\n" ..
			"- UDim2: 'ScaleX,OffsetX,ScaleY,OffsetY' (e.g., '0,100,0,50')\n" ..
			"- UDim: 'Scale,Offset' or just 'Offset' (e.g., '0,8' or '8')\n" ..
			"- Vector3: 'X,Y,Z' (e.g., '10,5,20')\n" ..
			"- Vector2: 'X,Y' (e.g., '0.5,0.5')\n" ..
			"- Color3: 'R,G,B' in 0-255 or hex '#FF8000'\n" ..
			"- NumberRange: 'min,max' or just 'value' (e.g., '1,5' or '3')\n" ..
			"- Enum: value name only (e.g., 'Neon' for Material)",
		parameters = {
			type = "object",
			properties = {
				path = { type = "string", description = "Path to the instance to modify" },
				properties = {
					type = "object",
					description = "Key-value pairs. The parser is CLASS-AWARE and interprets Size/Position based on the instance's class."
				}
			},
			required = { "path", "properties" }
		},
		preconditions = {
			{ check = "path_exists", param = "path", message = "Instance doesn't exist - verify path or use create_instance" },
			{ check = "instance_inspected", param = "path", message = "Consider using get_instance first to see current properties" }
		},
		llm_hints = {
			"Use get_instance first to see current property values",
			"GUI Size uses UDim2 (4 numbers), Part Size uses Vector3 (3 numbers)",
			"Color3 can be RGB 0-255 or hex '#RRGGBB'"
		}
	},

	{
		name = "delete_instance",
		description = "Delete an Instance from the game.",
		parameters = {
			type = "object",
			properties = { path = { type = "string" } },
			required = { "path" }
		},
		preconditions = {
			{ check = "path_exists", param = "path", message = "Instance doesn't exist - nothing to delete" }
		},
		llm_hints = {
			"This is IRREVERSIBLE - be certain before deleting",
			"Deleting a parent deletes all children too",
			"Use get_descendants_tree first to see what will be deleted"
		}
	},

	{
		name = "search_scripts",
		description = "Search for scripts containing specific code patterns.",
		parameters = {
			type = "object",
			properties = { query = { type = "string" } },
			required = { "query" }
		},
		preconditions = {
			{ check = "not_placeholder", param = "query", message = "query looks like a placeholder" }
		},
		llm_hints = {
			"Use specific function/variable names for better results",
			"Supports partial matches - 'DataStore' finds 'GetDataStore'",
			"Returns script paths and matching lines"
		}
	},

	{
		name = "update_project_context",
		description = "Save key architectural decisions/patterns to memory for future sessions.",
		parameters = {
			type = "object",
			properties = {
				contextType = { type = "string", enum = { "architecture", "convention", "warning", "dependency" } },
				content = { type = "string" },
				anchorPath = { type = "string" }
			},
			required = { "contextType", "content" }
		},
		preconditions = {
			{ check = "not_placeholder", param = "content", message = "content looks like a placeholder" }
		},
		llm_hints = {
			"Use for important patterns the user wants remembered",
			"anchorPath ties context to a specific script for validation",
			"context persists across sessions until invalidated"
		}
	},

	{
		name = "get_project_context",
		description = "Retrieve saved project memory.",
		parameters = {
			type = "object",
			properties = { includeStale = { type = "boolean" } },
			required = {}
		},
		preconditions = {},
		llm_hints = {
			"Call early in conversation to see what's known",
			"Stale context means the anchor script changed",
			"Use validate_context to check freshness"
		}
	},

	{
		name = "discover_project",
		description = "Analyze existing codebase (first run only).",
		parameters = {
			type = "object",
			properties = {},
			required = {}
		},
		preconditions = {},
		llm_hints = {
			"Run once at start of new project",
			"Finds all scripts and common patterns",
			"Results are cached - no need to run repeatedly"
		}
	},

	{
		name = "validate_context",
		description = "Check if saved memory is still valid.",
		parameters = {
			type = "object",
			properties = {},
			required = {}
		},
		preconditions = {},
		llm_hints = {
			"Checks if anchored scripts have changed",
			"Marks stale context that needs re-verification",
			"Run after major codebase changes"
		}
	},

	-- User Feedback / Interactive Verification
	{
		name = "request_user_feedback",
		description = "Ask the user to visually verify or test something in Studio/Play mode.\n\n" ..
			"?? USE SPARINGLY - This pauses your work and waits for user response!\n\n" ..
			"**GOOD times to use this:**\n" ..
			"• After creating visible UI elements ? 'Can you see the new button in the top-right?'\n" ..
			"• After implementing gameplay mechanics ? 'Please test in Play mode: does the jump feel right?'\n" ..
			"• At major milestones ? 'The inventory UI is set up. Please check it before I add logic.'\n" ..
			"• When debugging ? 'Can you still reproduce the issue?'\n\n" ..
			"**DON'T use for:**\n" ..
			"• After every small change (annoying!)\n" ..
			"• Invisible changes (scripts, DataStores)\n" ..
			"• Things you can verify with get_instance\n" ..
			"• When user indicated urgency ('just do it', 'quick', etc.)\n\n" ..
			"**Tips:**\n" ..
			"• Ask SPECIFIC questions, not 'does it work?'\n" ..
			"• Provide checklist items so user knows what to look at\n" ..
			"• Max 1 verification per user request",
		parameters = {
			type = "object",
			properties = {
				question = { 
					type = "string", 
					description = "Specific question to ask. Be concrete: 'Do you see a red button in the top-right corner?' not 'Does it work?'" 
				},
				context = { 
					type = "string", 
					description = "Brief explanation of what was just done and why verification helps" 
				},
				verification_type = { 
					type = "string", 
					enum = { "visual", "functional", "both" },
					description = "visual = just look at it, functional = test in Play mode, both = look then test"
				},
				suggestions = {
					type = "array",
					items = { type = "string" },
					description = "Optional: 2-4 specific things for user to check (e.g., ['Button is visible', 'Text reads Start', 'Position is top-right'])"
				}
			},
			required = { "question", "context", "verification_type" }
		},
		preconditions = {
			{ check = "not_placeholder", param = "question", message = "question looks like a placeholder" },
			{ check = "not_placeholder", param = "context", message = "context looks like a placeholder" }
		},
		llm_hints = {
			"Use SPARINGLY - this pauses work and waits for user",
			"Only for visual/functional verification you can't do programmatically",
			"Ask SPECIFIC questions, not 'does it work?'"
		}
	},

}
