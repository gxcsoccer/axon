# Axon

macOS computer use CLI & server — gives AI agents (and humans) the ability to control desktop applications.

## What It Does

Control macOS desktop via CLI commands or HTTP API: launch apps, click UI elements, type text (including Chinese/CJK), take screenshots, manage windows, and more.

**Three-layer hybrid architecture**:
1. **AppleScript/JXA** — most reliable for apps with scripting dictionaries
2. **Accessibility API** — structured UI tree traversal and element interaction
3. **Screenshot + coordinate clicking** — visual fallback for WebView apps (e.g. Electron)

## Install

```bash
# Build and install to /usr/local/bin (may need sudo)
sudo make install

# Or install to user directory (no sudo)
make install PREFIX=~/.local

# Or build only
make build

# Verify
axon --version
axon permissions
```

**Requirements**: macOS 14+, Swift 6.0+

**macOS Permissions** (System Settings > Privacy & Security):
- **Accessibility** — UI element control, keyboard/mouse simulation
- **Screen Recording** — screenshots

Run `axon permissions` to check and request permissions.

## CLI Usage

```bash
# App management
axon apps                                    # List running apps
axon launch com.apple.Safari                 # Launch app
axon activate com.apple.Safari               # Bring to front
axon quit com.apple.Safari                   # Quit app

# Mouse
axon click 500 300                           # Click at coordinates
axon click --app com.apple.Safari --role AXButton --title "Submit"
axon double-click 500 300                    # Double-click
axon right-click 500 300                     # Right-click
axon move 500 300                            # Move mouse
axon scroll 500 300 down --amount 5          # Scroll
axon drag 100 200 500 600                    # Drag from A to B
axon cursor-pos                              # Get cursor position

# Keyboard & Text
axon type "Hello World"                      # Type ASCII text
axon type "安溥的最好的时光"                    # Type Chinese (auto clipboard paste)
axon key return                              # Press key
axon key v --modifiers command               # Key combo (Cmd+V)
axon key a --modifiers command,shift          # Multiple modifiers

# Screenshots
axon screenshot                              # Full screen
axon screenshot --output ~/shot.jpg          # Save to specific path
axon screenshot --app com.apple.Safari       # Window screenshot
axon screenshot --region 0,0,800,600         # Region screenshot
axon screenshot --base64                     # Output base64 to stdout

# Screen & Window Info
axon screen-info                             # Display resolution & count
axon active-window                           # Current focused window info
axon move-window com.apple.Safari 0 25       # Move window
axon resize-window com.apple.Safari 1200 800 # Resize window

# UI Inspection (Accessibility API)
axon ui-tree com.apple.Safari --depth 5      # Get UI element tree
axon find com.apple.Safari --role AXButton --title "Submit"
axon wait com.apple.Safari --role AXTextField --timeout 10
axon text com.apple.Safari --role AXStaticText --title "heading"
axon perform com.apple.Safari AXPress --role AXButton --title "OK"

# Clipboard
axon clipboard-get                           # Read clipboard
axon clipboard-set "hello"                   # Write clipboard

# Scripting
axon script 'tell application "Finder" to activate'
axon jxa 'Application("Safari").name()'

# Raw action (JSON input, JSON output)
axon run '{"launchApp":{"bundleId":"com.apple.Safari"}}'
```

## Agent Integration

Axon is designed to be used by AI agents. Two integration modes:

### Mode 1: CLI (recommended for local agents)

Set `AXON_OUTPUT=json` for structured JSON output on all commands:

```bash
export AXON_OUTPUT=json

axon apps                    # Returns JSON array of apps
axon screenshot --base64     # Returns base64 image data
axon screen-info             # Returns {"displayCount":1,"displays":[...]}
axon cursor-pos              # Returns {"success":true,"data":{"cursorPosition":{"x":500,"y":300}}}
axon permissions             # Returns {"accessibility":true,"screenRecording":true,"allGranted":true}
```

Or use `axon run '<json>'` as a unified entry point — always returns JSON:

```bash
axon run '{"screenshot":{"displayId":null}}'
axon run '{"clickAt":{"x":500,"y":300}}'
axon run '{"typeText":{"text":"安溥的最好的时光"}}'
```

### Mode 2: HTTP Server (for remote agents or multi-client)

```bash
axon serve                   # Start on 127.0.0.1:29170
axon serve --port 8080       # Custom port
axon serve --no-auth         # Disable auth (dev only)
```

All endpoints return JSON. Bearer Token auth required (except `/health`).

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/action` | POST | Unified action endpoint |
| `/apps` | GET | List running apps |
| `/launch` | POST | Launch app |
| `/quit` | POST | Quit app |
| `/ui-tree` | POST | Get UI tree |
| `/find` | POST | Find element |
| `/wait` | POST | Wait for element |
| `/click` | POST | Click (element or coordinates) |
| `/type` | POST | Type text |
| `/key` | POST | Key press |
| `/screenshot` | GET/POST | Screenshot (full/window/region) |
| `/drag` | POST | Drag from A to B |
| `/cursor-position` | GET | Current cursor position |
| `/screen-info` | GET | Display info |
| `/clipboard` | GET/POST | Read/write clipboard |
| `/active-window` | GET | Active window info |
| `/move-window` | POST | Move window |
| `/resize-window` | POST | Resize window |
| `/text` | POST | Get element text |
| `/perform-action` | POST | Execute AX action |
| `/script` | POST | Run AppleScript/JXA |
| `/audit` | GET | Audit log |
| `/config` | GET | Security config |

### CJK Text Input

Chinese/Japanese/Korean text is automatically handled via clipboard paste (NSPasteboard + Cmd+V), bypassing CGEvent unicode which garbles IME input. The original clipboard is saved and restored.

```bash
axon type "最好的时光"       # Works correctly
```

## Security

- **Bearer Token auth** — auto-generated, saved to `~/.config/axon/auth-token`
- **App allowlist/denylist** — configurable via `~/.config/axon/security.json`
- **AX role denylist** — blocks `AXSecureTextField` (password fields)
- **Script sandbox** — blocks shell escapes (`do shell script`, `NSTask`, etc.)
- **Rate limiting** — 30 actions/minute default
- **Read-only mode** — `readOnlyMode: true` for query-only access
- **Audit log** — `~/.config/axon/axon-audit.jsonl`

## Project Structure

```
├── Sources/
│   ├── Axon/                     # CLI + HTTP server
│   │   ├── CLI.swift             # 30+ subcommands via ArgumentParser
│   │   └── Server.swift          # Hummingbird HTTP routes
│   └── AxonCore/                 # Core engine library
│       ├── Axon.swift            # AxonController — action orchestrator
│       ├── AXEngine.swift        # Accessibility API (UI tree, element actions)
│       ├── InputSimulator.swift  # CGEvent mouse/keyboard + clipboard paste
│       ├── ScreenCapture.swift   # ScreenCaptureKit screenshots
│       ├── AppManager.swift      # NSWorkspace app lifecycle
│       ├── ScriptEngine.swift    # osascript + script sandbox
│       ├── Security.swift        # Auth, rate limiting, audit
│       └── Types.swift           # ComputerAction enum, models
├── Tests/AxonCoreTests/          # 52 unit tests
├── openclaw-plugin/              # AI agent plugin (TypeScript)
└── Makefile                      # build / install / uninstall
```

## Development

```bash
make build                               # Build (debug)
make test                                # Run all tests (52)
swift build -c release                   # Build (release)
swift test --filter SecurityTests        # Run specific tests
swift run axon serve --no-auth           # Dev server without auth
```

## License

MIT

---

[中文文档](./README.zh-CN.md)
