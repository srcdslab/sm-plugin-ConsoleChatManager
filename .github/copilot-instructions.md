# Copilot Instructions - ConsoleChatManager

## Repository Overview
ConsoleChatManager is a SourceMod plugin for Source engine games that manages console messages and enhances chat functionality. The plugin intercepts, modifies, and redirects console messages with translation support, HUD display capabilities, and spam filtering.

## Project Architecture

### Core Components
- **Main Plugin**: `addons/sourcemod/scripting/ConsoleChatManager.sp` (950+ lines)
- **Game Data**: `addons/sourcemod/gamedata/ConsoleChatManager.games.txt` - DHooks signatures for ClientPrint detour
- **Configuration**: `addons/sourcemod/configs/consolechatmanager/` - Translation and message replacement configs
- **Build System**: SourceKnight (`sourceknight.yaml`) with automated CI/CD

### Key Features
- Console message interception and replacement
- Multi-language translation support
- HUD message display with customizable positioning and styling
- Spam detection and blocking
- DHooks detour for ClientPrint (Counter-Strike: Source only)
- Real-time configuration via ConVars

## Technical Environment

### Dependencies
- **SourceMod**: 1.11.0+ (specified in sourceknight.yaml)
- **Required Includes**:
  - `multicolors` - Color formatting library
  - `utilshelper` - Utility functions
  - `dhooks` - Dynamic hooking
  - `DynamicChannels` (optional) - Advanced HUD channel management

### Build System
- **Tool**: SourceKnight 0.2
- **Compiler**: SourceMod spcomp (latest compatible)
- **CI/CD**: GitHub Actions with automated building, testing, and releases
- **Output**: `addons/sourcemod/plugins/ConsoleChatManager.smx`

## Code Style & Conventions

### SourcePawn Specific
```sourcepawn
#pragma semicolon 1
#pragma newdecls required

// Global variable naming
ConVar g_ConsoleMessage, g_EnableTranslation;  // ConVars
StringMap g_hColorMap;                          // Handles with 'h' prefix
char g_sConsoleTag[255];                       // Strings with 's' prefix
bool g_bTranslation;                           // Booleans with 'b' prefix
int g_iNumber;                                 // Integers with 'i' prefix
float g_fHudDuration;                          // Floats with 'f' prefix
```

### Memory Management
```sourcepawn
// Always use delete directly - no null checks needed
delete g_hColorMap;
g_hColorMap = new StringMap();

// Never use .Clear() on StringMap/ArrayList - creates memory leaks
// Instead: delete and recreate
```

### ConVar Patterns
```sourcepawn
// Create with proper descriptions and bounds
g_cBlockSpam = CreateConVar("sm_consolechatmanager_block_spam", "1", 
    "Blocks console messages that repeat the same message.", 
    FCVAR_NONE, true, 0.0, true, 1.0);

// Hook for real-time updates
g_cBlockSpam.AddChangeHook(OnConVarChanged);

// Cache values for performance
g_bBlockSpam = g_cBlockSpam.BoolValue;
```

## Development Patterns

### Event Handling
```sourcepawn
public void OnPluginStart()
{
    // Initialize resources
    g_hHudSync = CreateHudSynchronizer();
    
    // Register events
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    
    // Setup DHooks (game-specific)
    if (GetEngineVersion() == Engine_CSS)
        SetupClientPrintDetour();
}
```

### DHooks Usage (CSS Only)
```sourcepawn
// Setup detour for ClientPrint interception
GameData gd = new GameData("ConsoleChatManager.games");
g_hClientPrintDtr = DynamicDetour.FromConf(gd, "ClientPrint");
DHookEnableDetour(g_hClientPrintDtr, false, Detour_ClientPrint);
```

### Translation System
```sourcepawn
// File format: configs/consolechatmanager/mapname.txt
"Console_C"
{
    "message_key"
    {
        "default"   "English message"
        "es"        "Spanish message"
        "chi"       "Chinese message"
        "sound"     "optional/sound/path.mp3"
        "blocked"   "1"  // Optional: block this message
    }
}
```

## Performance Considerations

### Critical Optimizations
1. **Timer Management**: Always use `DeleteTimer()` before creating new timers
2. **String Operations**: Cache frequently used strings in global variables
3. **ConVar Caching**: Store ConVar values in globals, update via hooks
4. **Memory Cleanup**: Use `delete` without null checks for all handles

### Frequently Called Functions
- Message processing hooks run on every console message
- ConVar change hooks should be lightweight
- HUD updates should minimize string formatting

## Configuration Management

### ConVar Categories
- **Message Handling**: `sm_consolechatmanager_tag`, `sm_consolechatmanager_remove_tag`
- **Translation**: `sm_consolechatmanager_translation`
- **HUD Display**: `sm_consolechatmanager_hud*` (position, color, duration, etc.)
- **Spam Control**: `sm_consolechatmanager_block_spam*`

### Translation Files
- Location: `addons/sourcemod/configs/consolechatmanager/`
- Format: KeyValues with language-specific translations
- Support for sounds and message blocking
- Per-map configuration support

## Build & Testing

### Build Process
```bash
# Using SourceKnight
sourceknight build

# Manual compilation (if needed)
spcomp ConsoleChatManager.sp -o ConsoleChatManager.smx
```

### Testing Approach
1. **Load Testing**: Verify plugin loads without errors
2. **ConVar Testing**: Test all configuration variables
3. **Message Processing**: Send console messages and verify interception
4. **HUD Display**: Test positioning, colors, and timing
5. **Translation**: Test with different client languages
6. **Memory**: Monitor for leaks using SM profiler

### Game Compatibility
- **Primary**: Counter-Strike: Source (full features including detours)
- **Secondary**: Other Source games (limited to basic functionality)
- **Engine Version**: Check `GetEngineVersion()` for feature availability

## Common Pitfalls & Solutions

### Memory Leaks
```sourcepawn
// WRONG - causes memory leaks
if (g_hColorMap != null)
    g_hColorMap.Clear();

// CORRECT - properly manages memory
delete g_hColorMap;
g_hColorMap = new StringMap();
```

### Timer Cleanup
```sourcepawn
// WRONG - can create multiple timers
CreateTimer(1.0, TimerCallback);

// CORRECT - cleanup existing timer first
DeleteTimer();
g_hTimerHandle = CreateTimer(1.0, TimerCallback);
```

### DHooks Game Compatibility
```sourcepawn
// Always check engine version for detours
EngineVersion iEngine = GetEngineVersion();
if (iEngine != Engine_CSS)
    return; // Skip detour setup for unsupported games
```

## Security Considerations

### Input Validation
- All console messages should be validated for length and content
- SQL operations must be asynchronous and use proper escaping
- User input in ConVars should be bounds-checked

### Permission Checks
```sourcepawn
// Admin commands require proper permission checks
RegAdminCmd("sm_ccm_reloadcfg", Command_ReloadConfig, ADMFLAG_CONFIG);
```

## Debugging & Diagnostics

### Logging Patterns
```sourcepawn
LogMessage("[ConsoleChatManager] Successfully detoured ClientPrint()");
LogError("[ConsoleChatManager] Failed to setup ClientPrint detour!");
```

### Console Output
- Use `PrintToServer()` for debugging information
- Implement debug ConVars for verbose logging
- Monitor console for DHooks setup success/failure

## Integration Guidelines

### Optional Plugin Support
```sourcepawn
#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
#define REQUIRE_PLUGIN

bool g_bPlugin_DynamicChannels = false;

public void OnAllPluginsLoaded()
{
    g_bPlugin_DynamicChannels = LibraryExists("DynamicChannels");
}
```

### API Patterns
- Use methodmaps for cleaner native function calls
- Implement proper error handling for all external API calls
- Cache expensive operations (e.g., client language lookups)

## Release & Deployment

### Version Management
- Update version in plugin info block
- Use semantic versioning (MAJOR.MINOR.PATCH)
- Tag releases in Git for automated CI/CD

### Packaging
- SourceKnight automatically packages plugins
- Include all required config files and gamedata
- Test final package on clean server installation

This repository follows established SourceMod development patterns with specific optimizations for console message processing and multi-language support. When making changes, prioritize performance and memory efficiency, as message processing occurs frequently during gameplay.