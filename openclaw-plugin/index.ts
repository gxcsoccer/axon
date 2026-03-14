import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { spawn, type ChildProcess } from "node:child_process";

const AXON_PROJECT_DIR = join(__dirname, "..");
const DEFAULT_URL = "http://127.0.0.1:29170";
const TOKEN_FILE = join(
  process.env.HOME ?? "~",
  ".config",
  "axon",
  "auth-token",
);

// ─── Axon HTTP Client ───────────────────────────────────────────────

class AxonClient {
  constructor(
    private baseUrl: string,
    private token?: string,
  ) {}

  private headers(): Record<string, string> {
    const h: Record<string, string> = { "Content-Type": "application/json" };
    if (this.token) h["Authorization"] = `Bearer ${this.token}`;
    return h;
  }

  private async request(method: "GET" | "POST", path: string, body?: unknown) {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: this.headers(),
      body: body ? JSON.stringify(body) : undefined,
    });
    return (await res.json()) as { success: boolean; data?: unknown; error?: string };
  }

  async health(): Promise<boolean> {
    try {
      const res = await fetch(`${this.baseUrl}/health`);
      return res.ok;
    } catch {
      return false;
    }
  }

  listApps() { return this.request("GET", "/apps"); }
  launch(bundleId: string) { return this.request("POST", "/launch", { bundleId }); }
  quit(bundleId: string) { return this.request("POST", "/quit", { bundleId }); }
  uiTree(bundleId: string, maxDepth?: number) { return this.request("POST", "/ui-tree", { bundleId, maxDepth }); }
  find(bundleId: string, query: Record<string, unknown>) { return this.request("POST", "/find", { bundleId, query }); }
  waitFor(bundleId: string, query: Record<string, unknown>, timeout?: number) { return this.request("POST", "/wait", { bundleId, query, timeout }); }
  click(params: Record<string, unknown>) { return this.request("POST", "/click", params); }
  type(params: Record<string, unknown>) { return this.request("POST", "/type", params); }
  key(key: string, modifiers?: string[]) { return this.request("POST", "/key", { key, modifiers }); }
  screenshot(params?: Record<string, unknown>) { return params ? this.request("POST", "/screenshot", params) : this.request("GET", "/screenshot"); }
  getText(bundleId: string, query: Record<string, unknown>) { return this.request("POST", "/text", { bundleId, query }); }
  performAction(bundleId: string, query: Record<string, unknown>, action: string) { return this.request("POST", "/perform-action", { bundleId, query, action }); }
  script(script: string, language?: string) { return this.request("POST", "/script", { script, language }); }
}

// ─── Confirmation Store (6-digit code → action) ─────────────────────

const READ_ONLY_ACTIONS = new Set([
  "list_apps", "get_ui_tree", "find_element", "wait_for_element",
  "screenshot", "get_text",
]);

type PendingAction = {
  code: string;
  params: Record<string, unknown>;
  description: string;
  createdAt: number;
};

class ConfirmationStore {
  private pending = new Map<string, PendingAction>();
  private readonly TTL_MS = 10 * 60 * 1000; // 10 minutes

  create(params: Record<string, unknown>, description: string): PendingAction {
    this.prune();
    const code = String(Math.floor(100000 + Math.random() * 900000)); // 6-digit
    const entry: PendingAction = { code, params: { ...params }, description, createdAt: Date.now() };
    this.pending.set(code, entry);
    return entry;
  }

  consume(code: string): PendingAction | undefined {
    const entry = this.pending.get(code);
    if (!entry) return undefined;
    this.pending.delete(code);
    if (Date.now() - entry.createdAt > this.TTL_MS) return undefined;
    return entry;
  }

  has(code: string): boolean {
    const entry = this.pending.get(code);
    if (!entry) return false;
    if (Date.now() - entry.createdAt > this.TTL_MS) {
      this.pending.delete(code);
      return false;
    }
    return true;
  }

  private prune() {
    const now = Date.now();
    for (const [code, entry] of this.pending) {
      if (now - entry.createdAt > this.TTL_MS) this.pending.delete(code);
    }
  }
}

// ─── Human-readable descriptions ────────────────────────────────────

const APP_NAMES: Record<string, string> = {
  "com.netease.163music": "网易云音乐",
  "com.tencent.QQMusicMac": "QQ音乐",
  "com.apple.Safari": "Safari",
  "com.apple.finder": "访达",
  "com.apple.systempreferences": "系统设置",
  "com.tencent.xinWeChat": "微信",
  "com.lark.Feishu": "飞书",
  "com.apple.TextEdit": "文本编辑",
  "com.googlecode.iterm2": "iTerm2",
};

function appName(bundleId?: string): string {
  if (!bundleId) return "未知应用";
  return APP_NAMES[bundleId] ?? bundleId;
}

function describeAction(params: Record<string, unknown>): string {
  const { action, bundleId, text, key_name, modifiers, x, y, script, language, axAction, query } = params as {
    action: string; bundleId?: string; text?: string; key_name?: string;
    modifiers?: string[]; x?: number; y?: number; script?: string;
    language?: string; axAction?: string; query?: Record<string, unknown>;
  };
  const app = appName(bundleId);
  const queryDesc = query
    ? Object.entries(query).filter(([,v]) => v).map(([k,v]) => `${k}="${v}"`).join(", ")
    : "";
  switch (action) {
    case "launch_app": return `启动应用「${app}」`;
    case "quit_app": return `退出应用「${app}」`;
    case "click":
      if (bundleId && query) return `在「${app}」中点击元素 (${queryDesc})`;
      if (x != null && y != null) return `点击坐标 (${x}, ${y})`;
      return "点击操作";
    case "type": return `输入文字「${text}」` + (bundleId ? ` → ${app}` : "");
    case "key": {
      const mod = modifiers?.length ? modifiers.join("+") + "+" : "";
      return `按键 ${mod}${key_name}` + (bundleId ? ` → ${app}` : "");
    }
    case "perform_action": return `在「${app}」中执行 ${axAction} (${queryDesc})`;
    case "script": {
      const lang = language === "jxa" ? "JXA" : "AppleScript";
      const preview = (script ?? "").length > 60 ? (script ?? "").slice(0, 60) + "…" : script;
      return `执行 ${lang}: ${preview}`;
    }
    default: return `${action}` + (bundleId ? ` → ${app}` : "");
  }
}

// ─── Tool ───────────────────────────────────────────────────────────

function errorResult(msg: string) {
  return { content: [{ type: "text" as const, text: `Error: ${msg}` }], details: { error: msg } };
}

function buildComputerUseTool(
  client: AxonClient,
  store: ConfirmationStore,
  feishuCfg: FeishuConfig | null,
  senderId: string | undefined,
  logger: PluginApi["logger"],
) {
  return {
    name: "computer_use",
    label: "Computer Use",
    description: `Control the macOS desktop via Axon.

Two categories:
- READ-ONLY (execute immediately): list_apps, get_ui_tree, find_element, wait_for_element, screenshot, get_text
- MUTATION (require user confirmation): launch_app, quit_app, click, type, key, perform_action, script

Mutation flow:
1. Call with the action and params → returns a 6-digit confirmation code and action description
2. Tell the user: "我要 [操作描述]，请回复 [6位数字] 确认"
3. User replies with the 6-digit code
4. Call computer_use(action="confirm", code="123456") → executes the stored action

The code is bound to the original params (tamper-proof), valid for 10 minutes, single-use.

Actions: list_apps, launch_app, quit_app, get_ui_tree, find_element, wait_for_element, click, type, key, screenshot, get_text, perform_action, script, confirm`,

    parameters: {
      type: "object" as const,
      properties: {
        action: {
          type: "string",
          description: 'Action to perform, or "confirm" to execute a previously approved action by code',
          enum: [
            "list_apps", "launch_app", "quit_app", "get_ui_tree",
            "find_element", "wait_for_element", "click", "type", "key",
            "screenshot", "get_text", "perform_action", "script",
            "confirm",
          ],
        },
        code: {
          type: "string",
          description: "6-digit confirmation code from the user. Use with action='confirm'.",
        },
        bundleId: { type: "string", description: "App bundle ID" },
        query: {
          type: "object",
          properties: {
            role: { type: "string" }, title: { type: "string" },
            identifier: { type: "string" }, value: { type: "string" },
            subrole: { type: "string" }, description: { type: "string" },
            index: { type: "number" },
            matchMode: { type: "string", enum: ["exact", "contains", "prefix", "regex"] },
          },
          additionalProperties: false,
        },
        text: { type: "string" },
        key_name: { type: "string" },
        modifiers: { type: "array", items: { type: "string" } },
        x: { type: "number" }, y: { type: "number" },
        timeout: { type: "number" },
        maxDepth: { type: "number" },
        axAction: { type: "string" },
        script: { type: "string" },
        language: { type: "string" },
        windowTitle: { type: "string" },
      },
      required: ["action"],
    },

    async execute(_toolCallId: string, params: Record<string, unknown>) {
      console.log(`[axon] computer_use: ${JSON.stringify(params)}`);
      const action = params.action as string;

      // ── confirm: execute stored action by code ──
      if (action === "confirm") {
        const code = (params.code as string ?? "").trim();
        if (!code) return errorResult("code required");
        const pending = store.consume(code);
        if (!pending) return errorResult(`确认码 ${code} 不存在或已过期（10分钟有效）`);
        console.log(`[axon] confirmed [${code}]: ${pending.description}`);
        return executeAction(client, pending.params, feishuCfg, senderId, logger);
      }

      // ── read-only: execute directly ──
      if (READ_ONLY_ACTIONS.has(action)) {
        return executeAction(client, params, feishuCfg, senderId, logger);
      }

      // ── mutation: generate confirmation code ──
      const desc = describeAction(params);
      const entry = store.create(params, desc);
      return {
        content: [{
          type: "text" as const,
          text: `🖥️ 桌面操作授权\n\n` +
            `**操作**: ${desc}\n` +
            `**确认码**: ${entry.code}\n\n` +
            `请告知用户操作内容，让用户回复 ${entry.code} 确认执行。10分钟内有效。`,
        }],
        details: {
          needsConfirmation: true,
          code: entry.code,
          description: desc,
        },
      };
    },
  };
}

async function executeAction(
  client: AxonClient,
  params: Record<string, unknown>,
  feishuCfg: FeishuConfig | null,
  senderId: string | undefined,
  logger: PluginApi["logger"],
) {
  const {
    action, bundleId, query, text, key_name, modifiers,
    x, y, timeout, maxDepth, axAction, script, language, windowTitle,
  } = params as {
    action: string; bundleId?: string; query?: Record<string, unknown>;
    text?: string; key_name?: string; modifiers?: string[];
    x?: number; y?: number; timeout?: number; maxDepth?: number;
    axAction?: string; script?: string; language?: string; windowTitle?: string;
  };

  let result;
  switch (action) {
    case "list_apps": result = await client.listApps(); break;
    case "launch_app":
      if (!bundleId) return errorResult("bundleId required");
      result = await client.launch(bundleId); break;
    case "quit_app":
      if (!bundleId) return errorResult("bundleId required");
      result = await client.quit(bundleId); break;
    case "get_ui_tree":
      if (!bundleId) return errorResult("bundleId required");
      result = await client.uiTree(bundleId, maxDepth); break;
    case "find_element":
      if (!bundleId || !query) return errorResult("bundleId and query required");
      result = await client.find(bundleId, query); break;
    case "wait_for_element":
      if (!bundleId || !query) return errorResult("bundleId and query required");
      result = await client.waitFor(bundleId, query, timeout); break;
    case "click":
      if (bundleId && query) result = await client.click({ bundleId, query });
      else if (x != null && y != null) result = await client.click({ x, y });
      else return errorResult("(bundleId + query) or (x + y) required");
      break;
    case "type":
      if (!text) return errorResult("text required");
      result = bundleId && query
        ? await client.type({ bundleId, query, text })
        : await client.type({ text });
      break;
    case "key":
      if (!key_name) return errorResult("key_name required");
      result = await client.key(key_name, modifiers); break;
    case "screenshot":
      result = bundleId
        ? await client.screenshot({ bundleId, windowTitle })
        : await client.screenshot();
      break;
    case "get_text":
      if (!bundleId || !query) return errorResult("bundleId and query required");
      result = await client.getText(bundleId, query); break;
    case "perform_action":
      if (!bundleId || !query || !axAction) return errorResult("bundleId, query, axAction required");
      result = await client.performAction(bundleId, query, axAction); break;
    case "script":
      if (!script) return errorResult("script required");
      result = await client.script(script, language); break;
    default:
      return errorResult(`Unknown action: ${action}`);
  }

  if (!result.success) {
    return { content: [{ type: "text" as const, text: `Error: ${result.error}` }], details: result };
  }

  const data = result.data as Record<string, unknown> | undefined;
  if (data && typeof data === "object" && "screenshot" in data) {
    const ss = data.screenshot as { base64: string; width: number; height: number };
    // Save to temp file so agent can send it via channel (e.g. Feishu)
    const dir = "/tmp/axon-screenshots";
    try { mkdirSync(dir, { recursive: true }); } catch {}
    const filename = `screenshot-${Date.now()}.jpg`;
    const filePath = join(dir, filename);
    writeFileSync(filePath, Buffer.from(ss.base64, "base64"));
    console.log(`[axon] screenshot saved: ${filePath} (${ss.width}×${ss.height})`);

    // Send screenshot directly to user via Feishu API
    if (feishuCfg && senderId) {
      const sent = await sendImageToFeishu(feishuCfg, senderId, filePath);
      if (sent) {
        logger.info?.(`[axon] screenshot sent to Feishu user ${senderId}`);
        return {
          content: [{ type: "text" as const, text: `截图已直接发送给用户 (${ss.width}×${ss.height})` }],
          details: { filePath, width: ss.width, height: ss.height, sent: true },
        };
      }
      logger.warn?.(`[axon] failed to send screenshot to Feishu, returning path`);
    }

    return {
      content: [{ type: "text" as const, text: `MEDIA: ${filePath}` }],
      details: { filePath, width: ss.width, height: ss.height },
    };
  }

  return {
    content: [{ type: "text" as const, text: JSON.stringify(result.data ?? { ok: true }, null, 2) }],
    details: result.data,
  };
}

// ─── Plugin Entry ───────────────────────────────────────────────────

function readTokenFile(): string | undefined {
  try { return readFileSync(TOKEN_FILE, "utf-8").trim(); } catch { return undefined; }
}

type PluginApi = {
  pluginConfig?: Record<string, unknown>;
  config?: Record<string, unknown>;
  logger: { info?: (msg: string) => void; error?: (msg: string) => void; debug?: (msg: string) => void; warn?: (msg: string) => void };
  registerTool: (tool: unknown) => void;
  on: (event: string, handler: (...args: unknown[]) => unknown) => void;
  registerService: (service: { id: string; start: (ctx: unknown) => void | Promise<void>; stop?: (ctx: unknown) => void | Promise<void> }) => void;
};

type FeishuConfig = { appId: string; appSecret: string; domain: string };

function resolveFeishuConfig(apiConfig: Record<string, unknown> | undefined): FeishuConfig | null {
  const channels = apiConfig?.channels as Record<string, unknown> | undefined;
  const feishu = channels?.feishu as Record<string, unknown> | undefined;
  if (!feishu?.appId || !feishu?.appSecret) return null;
  return {
    appId: feishu.appId as string,
    appSecret: feishu.appSecret as string,
    domain: (feishu.domain as string) === "lark" ? "lark" : "feishu",
  };
}

async function sendImageToFeishu(cfg: FeishuConfig, userId: string, filePath: string): Promise<boolean> {
  const baseUrl = cfg.domain === "lark" ? "https://open.larksuite.com" : "https://open.feishu.cn";
  try {
    // 1. Get tenant token
    const tokenResp = await fetch(`${baseUrl}/open-apis/auth/v3/tenant_access_token/internal`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ app_id: cfg.appId, app_secret: cfg.appSecret }),
    });
    const tokenData = (await tokenResp.json()) as { tenant_access_token: string };
    const token = tokenData.tenant_access_token;

    // 2. Upload image
    const imageData = readFileSync(filePath);
    const form = new FormData();
    form.append("image_type", "message");
    form.append("image", new Blob([imageData], { type: "image/jpeg" }), "screenshot.jpg");
    const uploadResp = await fetch(`${baseUrl}/open-apis/im/v1/images`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    });
    const uploadData = (await uploadResp.json()) as { data?: { image_key?: string } };
    const imageKey = uploadData.data?.image_key;
    if (!imageKey) return false;

    // 3. Send image message
    const msgResp = await fetch(`${baseUrl}/open-apis/im/v1/messages?receive_id_type=open_id`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        receive_id: userId,
        msg_type: "image",
        content: JSON.stringify({ image_key: imageKey }),
      }),
    });
    return msgResp.ok;
  } catch {
    return false;
  }
}

export default {
  id: "axon",
  name: "Axon",
  description: "macOS desktop automation via Accessibility API and AppleScript",

  register(api: PluginApi) {
    const cfg = (api.pluginConfig ?? {}) as {
      serverUrl?: string;
      authToken?: string;
      autoStart?: boolean;
    };

    const serverUrl = cfg.serverUrl ?? DEFAULT_URL;
    const authToken = cfg.authToken ?? readTokenFile();
    const client = new AxonClient(serverUrl, authToken);
    const store = new ConfirmationStore();
    const feishuCfg = resolveFeishuConfig(api.config as Record<string, unknown> | undefined);
    if (feishuCfg) {
      api.logger.info?.("[axon] Feishu screenshot delivery enabled");
    }

    api.registerTool((ctx: { requesterSenderId?: string } | undefined) =>
      buildComputerUseTool(client, store, feishuCfg, ctx?.requesterSenderId, api.logger),
    );
    api.logger.info?.("[axon] computer_use tool registered");

    api.on("before_prompt_build", () => ({
      appendSystemContext: `## 桌面控制能力（Axon）

你可以通过 computer_use 工具控制主人的 macOS 桌面。

### 授权机制（必须遵守）
改变桌面状态的操作（启动/退出应用、点击、输入、按键、脚本）需要用户授权：

1. 调用 computer_use(action="launch_app", bundleId="...") → 返回 6 位确认码（如 847291）
2. 告诉用户：「我要启动网易云音乐，请回复 847291 确认」
3. 用户回复 847291 → 你调用 computer_use(action="confirm", code="847291") 执行

确认码绑定原始参数，不可篡改，10分钟有效，一次性。
只读操作（list_apps, screenshot, get_ui_tree, find_element, wait_for_element, get_text）直接执行。

### 多步操作
每步都会生成独立的确认码。建议先向用户说明完整计划，一次性列出所有步骤的确认码，用户回复后逐个 confirm。

### 用户回复确认码时
当用户的消息就是一个 6 位数字，那就是在确认桌面操作，立即调用 computer_use(action="confirm", code="用户回复的数字")。

### 输入文字规则
- 中文必须用 action: "type"，不能用 AppleScript keystroke
- 快捷键用 action: "key"

### 截图
screenshot 的结果会自动发送图片给用户，你只需正常回复即可。

### 常用 bundle ID
网易云音乐 com.netease.163music，Safari com.apple.Safari，微信 com.tencent.xinWeChat，飞书 com.lark.Feishu`,
    }));

    let serverProcess: ChildProcess | null = null;

    api.registerService({
      id: "axon-server",
      start: async () => {
        if (await client.health()) {
          api.logger.info?.("[axon] Server already running");
          return;
        }
        if (!cfg.autoStart) {
          api.logger.info?.("[axon] Server not running. Set autoStart or run: swift run axon serve");
          return;
        }
        api.logger.info?.("[axon] Starting Axon server...");
        serverProcess = spawn("swift", ["run", "axon", "serve"], {
          cwd: AXON_PROJECT_DIR, stdio: "pipe", detached: false,
        });
        serverProcess.stderr?.on("data", (d: Buffer) => {
          const line = d.toString().trim();
          if (line) api.logger.debug?.(`[axon] ${line}`);
        });
        serverProcess.on("error", (err) => {
          api.logger.error?.(`[axon] Failed to start: ${err.message}`);
          serverProcess = null;
        });
        serverProcess.on("exit", (code) => {
          api.logger.info?.(`[axon] Server exited (code ${code})`);
          serverProcess = null;
        });
        const deadline = Date.now() + 30_000;
        while (Date.now() < deadline) {
          await new Promise((r) => setTimeout(r, 500));
          if (await client.health()) { api.logger.info?.("[axon] Server ready"); return; }
        }
        api.logger.error?.("[axon] Server failed to start within 30s");
      },
      stop: async () => {
        if (serverProcess) {
          api.logger.info?.("[axon] Stopping server...");
          serverProcess.kill("SIGTERM");
          serverProcess = null;
        }
      },
    });
  },
};
