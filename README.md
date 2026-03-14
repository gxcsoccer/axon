# Axon

macOS desktop automation server that gives AI agents the ability to control desktop applications.

## What It Does

Exposes macOS desktop control via HTTP API: launch apps, click buttons, type text, take screenshots, run AppleScript, and more.

**Three-layer hybrid architecture**:
1. **AppleScript/JXA** — most reliable for apps with scripting dictionaries
2. **Accessibility API** — structured UI tree traversal and element interaction
3. **Screenshot + coordinate clicking** — visual fallback

## Quick Start

```bash
# Build
swift build

# Start server (default: 127.0.0.1:29170)
swift run axon serve

# Auto-generates auth token on first run, saved to ~/.config/axon/auth-token
# All API requests require Authorization: Bearer <token> (except /health)

# Test
curl http://127.0.0.1:29170/health
curl -H "Authorization: Bearer $(cat ~/.config/axon/auth-token)" http://127.0.0.1:29170/apps
```

**Requirements**: macOS 14+, Swift 6.0+

**macOS Permissions** (System Settings > Privacy & Security):
- **Accessibility** — UI element control
- **Screen Recording** — screenshots
- **Input Monitoring** — keyboard/mouse simulation

## HTTP API

All endpoints return JSON. Bearer Token auth required (except `/health`).

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (no auth) |
| `/action` | POST | Unified action endpoint, body is a `ComputerAction` JSON |
| `/apps` | GET | List running GUI apps |
| `/launch` | POST | Launch app `{ "bundleId": "..." }` |
| `/quit` | POST | Quit app `{ "bundleId": "..." }` |
| `/ui-tree` | POST | Get UI tree `{ "bundleId": "...", "maxDepth": 4 }` |
| `/find` | POST | Find UI element `{ "bundleId": "...", "query": {...} }` |
| `/wait` | POST | Wait for element `{ "bundleId": "...", "query": {...}, "timeout": 10 }` |
| `/click` | POST | Click element (by query) or coordinates (x, y) |
| `/type` | POST | Type text `{ "text": "..." }` (non-ASCII auto-pastes via clipboard) |
| `/key` | POST | Key press `{ "key": "return", "modifiers": ["command"] }` |
| `/screenshot` | GET/POST | Screenshot (optional `bundleId` for window capture) |
| `/text` | POST | Get element text content |
| `/perform-action` | POST | Execute AX action (e.g. AXPress, AXShowMenu) |
| `/script` | POST | Run AppleScript/JXA |
| `/audit` | GET | Audit log |
| `/config` | GET | Security config |

## Security

- **Bearer Token auth** — auto-generated on first run, saved to `~/.config/axon/auth-token`
- **App allowlist/denylist** — configurable via `~/.config/axon/security.json`
- **AX role denylist** — blocks `AXSecureTextField` (password fields) by default
- **Script sandbox** — blocks `do shell script`, `NSTask`, `Process()`, and other shell escapes
- **Rate limiting** — 30 actions/minute by default
- **Read-only mode** — `readOnlyMode: true` restricts to query-only operations
- **Audit log** — all actions logged to `~/.config/axon/axon-audit.jsonl`

## AI Agent Plugin

`openclaw-plugin/` contains a plugin for AI assistant platforms that exposes Axon as a unified `computer_use` tool.

### Features

- **Single `computer_use` tool** — one tool covering all desktop actions (matches Anthropic computer-use paradigm)
- **6-digit confirmation codes** — mutation actions require user to reply with a code before execution
- **Read-only actions skip confirmation** — screenshot, list_apps, etc. execute immediately
- **Direct image delivery** — screenshots sent via messaging API, bypassing LLM round-trip
- **CJK input support** — non-ASCII text auto-pastes via AppleScript clipboard
- **Auto server management** — optional `autoStart: true` to launch Axon server on plugin load

### Confirmation Flow

```
User: Open TextEdit

Agent: I'll launch TextEdit. Reply 847291 to confirm.

User: 847291

Agent: ✅ TextEdit launched
```

Codes are bound to original params (tamper-proof), expire in 10 minutes, single-use.

## Project Structure

```
├── Sources/
│   ├── Axon/                     # CLI + HTTP server
│   │   ├── CLI.swift             # ArgumentParser: serve/run/permissions
│   │   └── Server.swift          # Hummingbird routes + Bearer Token middleware
│   └── AxonCore/                 # Core engine library
│       ├── Axon.swift            # AxonController actor — orchestrator
│       ├── AXEngine.swift        # Accessibility API engine
│       ├── InputSimulator.swift  # CGEvent keyboard/mouse simulation
│       ├── ScreenCapture.swift   # ScreenCaptureKit screenshots
│       ├── AppManager.swift      # NSWorkspace app lifecycle
│       ├── ScriptEngine.swift    # osascript + script sandbox
│       ├── Security.swift        # SecurityGate: permissions, rate limiting, audit
│       └── Types.swift           # Shared type definitions
├── Tests/
│   └── AxonCoreTests/
│       ├── TypesTests.swift      # Type codable + action classification tests
│       └── SecurityTests.swift   # Security gate + script sandbox tests
└── openclaw-plugin/              # AI agent plugin
    ├── index.ts
    ├── package.json
    └── openclaw.plugin.json
```

## Development

```bash
swift build                              # Build
swift test                               # Run all tests (33)
swift test --filter SecurityTests        # Run security tests only
swift run axon serve                     # Start server
swift run axon serve --no-auth           # No auth (dev only)
swift run axon serve --token <token>     # Custom token
swift run axon permissions               # Check macOS permissions
```

## License

MIT

---

[中文文档](./README.zh-CN.md)
