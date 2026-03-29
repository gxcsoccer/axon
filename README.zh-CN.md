# Axon

macOS computer use CLI & 服务器 — 让 AI agent（和人类）控制 macOS 桌面应用。

## 它能做什么

通过 CLI 命令或 HTTP API 控制 macOS 桌面：启动应用、点击 UI 元素、输入文字（支持中文）、截图、管理窗口等。

**三层混合架构**：
1. **AppleScript/JXA** — 最可靠，适合有脚本字典的应用
2. **Accessibility API** — 结构化 UI 树遍历和元素交互
3. **Screenshot + 坐标点击** — 视觉兜底方案，适用于 WebView/Electron 应用

## 安装

```bash
# 构建并安装到 /usr/local/bin（可能需要 sudo）
sudo make install

# 或安装到用户目录（无需 sudo）
make install PREFIX=~/.local

# 或仅构建
make build

# 验证
axon --version
axon permissions
```

**系统要求**：macOS 14+, Swift 6.0+

**macOS 权限**（系统设置 > 隐私与安全性）：
- **辅助功能** — UI 元素控制、键盘鼠标模拟
- **屏幕录制** — 截图

运行 `axon permissions` 检查和申请权限。

## CLI 使用

```bash
# 应用管理
axon apps                                    # 列出运行中的应用
axon launch com.netease.163music             # 启动应用
axon activate com.netease.163music           # 切到前台
axon quit com.netease.163music               # 退出应用

# 鼠标操作
axon click 500 300                           # 坐标点击
axon click --app com.apple.Safari --role AXButton --title "提交"
axon double-click 500 300                    # 双击
axon right-click 500 300                     # 右键
axon move 500 300                            # 移动鼠标
axon scroll 500 300 down --amount 5          # 滚动
axon drag 100 200 500 600                    # 从 A 拖到 B
axon cursor-pos                              # 获取鼠标位置

# 键盘和文字输入
axon type "Hello World"                      # 输入英文
axon type "安溥的最好的时光"                    # 输入中文（自动剪贴板粘贴）
axon key return                              # 按键
axon key v --modifiers command               # 快捷键 (Cmd+V)

# 截图
axon screenshot                              # 全屏截图
axon screenshot --output ~/shot.jpg          # 保存到指定路径
axon screenshot --app com.netease.163music   # 窗口截图
axon screenshot --region 0,0,800,600         # 区域截图
axon screenshot --base64                     # 输出 base64

# 屏幕和窗口信息
axon screen-info                             # 显示器分辨率和数量
axon active-window                           # 当前活跃窗口信息
axon move-window com.apple.Safari 0 25       # 移动窗口
axon resize-window com.apple.Safari 1200 800 # 调整窗口大小

# UI 检查（Accessibility API）
axon ui-tree com.apple.Safari --depth 5      # 获取 UI 元素树
axon find com.apple.Safari --role AXButton --title "提交"
axon wait com.apple.Safari --role AXTextField --timeout 10
axon text com.apple.Safari --role AXStaticText
axon perform com.apple.Safari AXPress --role AXButton --title "确定"

# 剪贴板
axon clipboard-get                           # 读取剪贴板
axon clipboard-set "你好"                     # 写入剪贴板

# 脚本
axon script 'tell application "Finder" to activate'
axon jxa 'Application("Safari").name()'

# Raw action（JSON 输入，JSON 输出）
axon run '{"launchApp":{"bundleId":"com.apple.Safari"}}'
```

## Agent 集成

Axon 为 AI agent 而设计，提供两种集成方式：

### 方式一：CLI（推荐本地 agent 使用）

设置 `AXON_OUTPUT=json` 让所有命令输出结构化 JSON：

```bash
export AXON_OUTPUT=json

axon apps                    # 返回应用列表 JSON
axon screen-info             # 返回 {"displayCount":1,"displays":[...]}
axon cursor-pos              # 返回 {"success":true,"data":{"cursorPosition":{"x":500,"y":300}}}
axon permissions             # 返回 {"accessibility":true,"screenRecording":true,"allGranted":true}
```

或用 `axon run '<json>'` 作为统一入口 — 始终返回 JSON：

```bash
axon run '{"screenshot":{"displayId":null}}'
axon run '{"clickAt":{"x":500,"y":300}}'
axon run '{"typeText":{"text":"安溥的最好的时光"}}'
```

### 方式二：HTTP 服务器（远程 agent 或多客户端）

```bash
axon serve                   # 启动在 127.0.0.1:29170
axon serve --port 8080       # 自定义端口
axon serve --no-auth         # 无认证模式（仅开发用）
```

所有端点返回 JSON，需要 Bearer Token 认证。

| 端点 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/action` | POST | 统一 action 端点 |
| `/apps` | GET | 列出应用 |
| `/launch` | POST | 启动应用 |
| `/quit` | POST | 退出应用 |
| `/ui-tree` | POST | 获取 UI 树 |
| `/find` | POST | 查找元素 |
| `/wait` | POST | 等待元素 |
| `/click` | POST | 点击（元素或坐标）|
| `/type` | POST | 输入文字 |
| `/key` | POST | 按键 |
| `/screenshot` | GET/POST | 截图（全屏/窗口/区域）|
| `/drag` | POST | 拖拽 |
| `/cursor-position` | GET | 鼠标位置 |
| `/screen-info` | GET | 显示器信息 |
| `/clipboard` | GET/POST | 读写剪贴板 |
| `/active-window` | GET | 活跃窗口信息 |
| `/move-window` | POST | 移动窗口 |
| `/resize-window` | POST | 调整窗口大小 |
| `/text` | POST | 获取元素文本 |
| `/perform-action` | POST | 执行 AX action |
| `/script` | POST | 运行 AppleScript/JXA |
| `/audit` | GET | 审计日志 |
| `/config` | GET | 安全配置 |

### 中文输入

中文/日文/韩文自动通过 NSPasteboard + Cmd+V 粘贴输入，避免 CGEvent unicode 输入导致的 IME 乱码问题。粘贴后自动恢复原剪贴板内容。

```bash
axon type "最好的时光"       # 直接可用
```

## 安全机制

- **Bearer Token 认证** — 首次启动自动生成，保存在 `~/.config/axon/auth-token`
- **应用白名单/黑名单** — 通过 `~/.config/axon/security.json` 配置
- **AX 角色黑名单** — 默认屏蔽 `AXSecureTextField`（密码框）
- **脚本沙箱** — 拦截 `do shell script`、`NSTask`、`Process()` 等 shell 逃逸
- **速率限制** — 默认 30 次/分钟
- **只读模式** — `readOnlyMode: true` 时只允许查询操作
- **审计日志** — 所有操作记录到 `~/.config/axon/axon-audit.jsonl`

## 项目结构

```
├── Sources/
│   ├── Axon/                     # CLI + HTTP 服务器
│   │   ├── CLI.swift             # 30+ 子命令（ArgumentParser）
│   │   └── Server.swift          # Hummingbird HTTP 路由
│   └── AxonCore/                 # 核心引擎库
│       ├── Axon.swift            # AxonController — action 调度器
│       ├── AXEngine.swift        # Accessibility API（UI 树、元素操作）
│       ├── InputSimulator.swift  # CGEvent 键鼠模拟 + 剪贴板粘贴
│       ├── ScreenCapture.swift   # ScreenCaptureKit 截图
│       ├── AppManager.swift      # NSWorkspace 应用管理
│       ├── ScriptEngine.swift    # osascript + 脚本沙箱
│       ├── Security.swift        # 认证、限流、审计
│       └── Types.swift           # ComputerAction 枚举、模型定义
├── Tests/AxonCoreTests/          # 52 个单元测试
├── openclaw-plugin/              # AI agent 插件（TypeScript）
└── Makefile                      # build / install / uninstall
```

## 开发

```bash
make build                               # 构建（debug）
make test                                # 运行所有测试（52 个）
swift build -c release                   # 构建（release）
swift test --filter SecurityTests        # 只跑安全测试
swift run axon serve --no-auth           # 无认证模式（仅开发用）
```

## License

MIT
