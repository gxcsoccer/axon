# Axon

macOS 桌面自动化服务器，让 AI agent 能控制 macOS 桌面应用。

## 它能做什么

通过 HTTP API 让 AI agent 执行桌面操作：打开应用、点击按钮、输入文字、截图、运行 AppleScript 等。

**三层混合架构**：
1. **AppleScript/JXA** — 最可靠，适合有脚本字典的应用
2. **Accessibility API** — 结构化 UI 树遍历和元素交互
3. **Screenshot + 坐标点击** — 视觉兜底方案

## 快速开始

```bash
# 构建
swift build

# 启动服务器（默认 127.0.0.1:29170）
swift run axon serve

# 首次启动自动生成 auth token，保存在 ~/.config/axon/auth-token
# 所有 API 请求需要 Authorization: Bearer <token>（/health 除外）

# 测试
curl http://127.0.0.1:29170/health
curl -H "Authorization: Bearer $(cat ~/.config/axon/auth-token)" http://127.0.0.1:29170/apps
```

**系统要求**：macOS 14+, Swift 6.0+

**macOS 权限**（系统设置 > 隐私与安全性）：
- **辅助功能** — UI 元素控制
- **屏幕录制** — 截图
- **输入监控** — 键盘/鼠标模拟

## HTTP API

所有端点返回 JSON，需要 Bearer Token 认证（`/health` 除外）。

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查（免认证） |
| `/action` | POST | 统一 action 端点，body 是 `ComputerAction` JSON |
| `/apps` | GET | 列出运行中的 GUI 应用 |
| `/launch` | POST | 启动应用 `{ "bundleId": "..." }` |
| `/quit` | POST | 退出应用 `{ "bundleId": "..." }` |
| `/ui-tree` | POST | 获取 UI 树 `{ "bundleId": "...", "maxDepth": 4 }` |
| `/find` | POST | 查找 UI 元素 `{ "bundleId": "...", "query": {...} }` |
| `/wait` | POST | 等待元素出现 `{ "bundleId": "...", "query": {...}, "timeout": 10 }` |
| `/click` | POST | 点击元素（query）或坐标（x, y） |
| `/type` | POST | 输入文字 `{ "text": "..." }`（非 ASCII 自动走剪贴板粘贴） |
| `/key` | POST | 按键 `{ "key": "return", "modifiers": ["command"] }` |
| `/screenshot` | GET/POST | 截图（可指定 `bundleId` 截窗口） |
| `/text` | POST | 获取元素文本内容 |
| `/perform-action` | POST | 执行 AX action（如 AXPress, AXShowMenu） |
| `/script` | POST | 运行 AppleScript/JXA |
| `/audit` | GET | 审计日志 |
| `/config` | GET | 安全配置 |

## 安全机制

- **Bearer Token 认证** — 首次启动自动生成，保存在 `~/.config/axon/auth-token`
- **应用白名单/黑名单** — 通过 `~/.config/axon/security.json` 配置
- **AX 角色黑名单** — 默认屏蔽 `AXSecureTextField`（密码框）
- **脚本沙箱** — 拦截 `do shell script`、`NSTask`、`Process()` 等 shell 逃逸
- **速率限制** — 默认 30 次/分钟
- **只读模式** — `readOnlyMode: true` 时只允许查询操作
- **审计日志** — 所有操作记录到 `~/.config/axon/axon-audit.jsonl`

## AI Agent 插件

`openclaw-plugin/` 包含 AI 助手平台插件，将 Axon 暴露为统一的 `computer_use` tool。

### 功能

- **统一 `computer_use` tool** — 单个 tool 涵盖所有桌面操作（匹配 Anthropic computer-use 范式）
- **6 位确认码授权** — 写操作需要用户回复 6 位数字确认，防止误操作
- **只读操作免确认** — screenshot、list_apps 等直接执行
- **截图直送** — 截图通过消息平台 API 直接发送给用户，不经过 LLM
- **CJK 输入支持** — 非 ASCII 文本自动走 AppleScript 剪贴板粘贴
- **自动 server 管理** — 可配置 `autoStart: true` 自动启动 Axon 服务

### 确认流程

```
用户: 打开文本编辑

Agent: 我要启动「文本编辑」，请回复 847291 确认

用户: 847291

Agent: ✅ 文本编辑已启动
```

确认码绑定原始参数（不可篡改），10 分钟过期，一次性使用。

## 项目结构

```
├── Sources/
│   ├── Axon/                     # CLI + HTTP 服务器
│   │   ├── CLI.swift             # ArgumentParser: serve/run/permissions
│   │   └── Server.swift          # Hummingbird 路由 + Bearer Token 中间件
│   └── AxonCore/                 # 核心引擎库
│       ├── Axon.swift            # AxonController actor — 调度器
│       ├── AXEngine.swift        # Accessibility API 引擎
│       ├── InputSimulator.swift  # CGEvent 键鼠模拟
│       ├── ScreenCapture.swift   # ScreenCaptureKit 截图
│       ├── AppManager.swift      # NSWorkspace 应用管理
│       ├── ScriptEngine.swift    # osascript + 脚本沙箱
│       ├── Security.swift        # SecurityGate: 权限、限流、审计
│       └── Types.swift           # 共享类型定义
├── Tests/
│   └── AxonCoreTests/
│       ├── TypesTests.swift      # 类型编解码 + action 分类测试
│       └── SecurityTests.swift   # 安全门 + 脚本沙箱测试
└── openclaw-plugin/              # AI agent 插件
    ├── index.ts
    ├── package.json
    └── openclaw.plugin.json
```

## 开发

```bash
swift build                              # 构建
swift test                               # 运行所有测试（33 个）
swift test --filter SecurityTests        # 只跑安全测试
swift run axon serve                     # 启动服务
swift run axon serve --no-auth           # 无认证模式（仅开发用）
swift run axon serve --token <token>     # 指定 token
swift run axon permissions               # 检查 macOS 权限
```

## License

MIT
