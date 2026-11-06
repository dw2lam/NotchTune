// notchtune-plugin-revision: 2
// NotchTune plugin for OpenCode
// Bridges OpenCode events to the NotchTune app via Unix socket.
// Install: copy to ~/.config/opencode/plugins/open-island.js
//
// One file serves both plugin APIs, because V1 plugins don't run on OpenCode 2
// and users can be on either. V2 requires a default object with `id` and
// `setup` and rejects a function; V1 before 1.18.29 only accepts a function.
// V2 resolves `@opencode/plugin` for the plugins it loads and V1 doesn't, so
// the shape is chosen at load time. Keep the revision in a comment: older V1
// loaders call every named export.
import { connect } from "net";
import { homedir } from "os";

// The approval card shows this as what's being approved, and marks it when
// it's too long to show. So the command goes as itself and whole: cut here,
// the card would never know, and JSON around it reads as a broken command.
const PERMISSION_INPUT_LIMIT = 16384;
function permissionInputText(toolInput) {
  const text = typeof toolInput.command === "string"
    ? toolInput.command
    : JSON.stringify(toolInput);
  return text.slice(0, PERMISSION_INPUT_LIMIT);
}

const SOCKET_PATH =
  process.env.NOTCHTUNE_SOCKET_PATH ||
  `${process.env.HOME || homedir()}/Library/Application Support/NotchTune/bridge.sock`;

function encodeEnvelope(command) {
  return JSON.stringify({ type: "command", command }) + "\n";
}

function sendToSocket(json) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.end(encodeEnvelope(json));
      });
      let buf = "";
      sock.on("data", (chunk) => { buf += chunk.toString(); });
      sock.on("end", () => { resolve(true); });
      sock.on("error", () => resolve(false));
      sock.setTimeout(3000, () => { sock.destroy(); resolve(false); });
    } catch { resolve(false); }
  });
}

function sendAndWaitResponse(json, timeoutMs = 300000) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.write(encodeEnvelope(json));
      });
      let buf = "";
      sock.on("data", (chunk) => {
        buf += chunk.toString();
        // BridgeServer sends hello first, then response after processing
        const lines = buf.split("\n").filter(Boolean);
        if (lines.length >= 2) {
          sock.destroy();
          try { resolve(JSON.parse(lines[1])); } catch { resolve(null); }
        }
      });
      sock.on("end", () => {
        const lines = buf.split("\n").filter(Boolean);
        if (lines.length >= 2) {
          try { resolve(JSON.parse(lines[1])); } catch { resolve(null); }
        } else {
          resolve(null);
        }
      });
      sock.on("error", () => resolve(null));
      sock.setTimeout(timeoutMs, () => { sock.destroy(); resolve(null); });
    } catch { resolve(null); }
  });
}

// Terminal environment detection
let detectedTty = null;
try {
  const { execSync } = require("child_process");
  let walkPid = process.pid;
  for (let i = 0; i < 8; i++) {
    const info = execSync(`ps -o tty=,ppid= -p ${walkPid}`, { timeout: 1000 }).toString().trim();
    const parts = info.split(/\s+/);
    const tty = parts[0], ppid = parseInt(parts[1]);
    if (tty && tty !== "??" && tty !== "?") { detectedTty = `/dev/${tty}`; break; }
    if (!ppid || ppid <= 1) break;
    walkPid = ppid;
  }
} catch {}

const ENV_KEYS = [
  "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
  "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID",
  "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH",
  "ZELLIJ", "ZELLIJ_PANE_ID", "ZELLIJ_SESSION_NAME",
];

function collectEnv() {
  const env = {};
  for (const k of ENV_KEYS) { if (process.env[k]) env[k] = process.env[k]; }
  return env;
}

function terminalFields() {
  const env = process.env;
  const result = {};
  if (env.ITERM_SESSION_ID) {
    result.terminal_app = "iTerm";
    result.terminal_session_id = env.ITERM_SESSION_ID;
  } else if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) {
    result.terminal_app = "cmux";
    if (env.CMUX_SURFACE_ID) result.terminal_session_id = env.CMUX_SURFACE_ID;
  } else if (env.ZELLIJ != null) {
    result.terminal_app = "Zellij";
    const paneID = env.ZELLIJ_PANE_ID || "";
    const sessionName = env.ZELLIJ_SESSION_NAME || "";
    if (paneID) result.terminal_session_id = `${paneID}:${sessionName}`;
  } else if (env.GHOSTTY_RESOURCES_DIR || (env.TERM_PROGRAM || "").toLowerCase().includes("ghostty")) {
    result.terminal_app = "Ghostty";
  } else if (env.TERM_PROGRAM === "Apple_Terminal") {
    result.terminal_app = "Terminal";
  } else if (env.TERM_PROGRAM) {
    result.terminal_app = env.TERM_PROGRAM;
  }
  if (detectedTty) result.terminal_tty = detectedTty;
  return result;
}

function makePayload(hookEventName, sessionID, cwd, extra = {}) {
  return {
    type: "processOpenCodeHook",
    openCodeHook: {
      hook_event_name: hookEventName,
      session_id: `opencode-${sessionID}`,
      cwd: cwd || ".",
      ...terminalFields(),
      ...extra,
    },
  };
}

function normalizeQuestionOption(option) {
  if (typeof option === "string") {
    return { label: option };
  }
  if (!option || typeof option !== "object") {
    return null;
  }

  const label = option.label || option.text || option.value || option.name;
  if (!label) return null;

  return {
    label: String(label),
    description: option.description || option.hint || option.detail || "",
    allows_freeform: Boolean(option.allowsFreeform || option.allows_freeform),
  };
}

function normalizeQuestion(question, index) {
  if (!question || typeof question !== "object") {
    return null;
  }

  const questionText = question.question || question.title || question.prompt;
  if (!questionText) return null;

  const options = Array.isArray(question.options)
    ? question.options.map(normalizeQuestionOption).filter(Boolean)
    : [];
  if (options.length === 0) return null;

  return {
    question: String(questionText),
    header: question.header || question.label || `Question ${index + 1}`,
    options,
    multi_select: Boolean(question.multiSelect || question.multi_select),
  };
}

async function serverV1({ client, serverUrl }) {
  const serverPort = serverUrl ? parseInt(serverUrl.port) || 4096 : 4096;
  const internalFetch = client?._client?.getConfig?.()?.fetch || null;
  const msgRoles = new Map();
  const sessionCwd = new Map();
  const sessions = new Map();

  function getSession(sid) {
    if (!sessions.has(sid)) sessions.set(sid, { lastAssistantText: "" });
    return sessions.get(sid);
  }

  function mapEvent(ev) {
    const t = ev.type;
    const p = ev.properties || {};

    // session.created
    if (t === "session.created" && p.info) {
      const cwd = p.info.directory || "";
      sessionCwd.set(p.info.id, cwd);
      return makePayload("SessionStart", p.info.id, cwd);
    }

    // session.deleted
    if (t === "session.deleted" && p.info) {
      sessions.delete(p.info.id);
      sessionCwd.delete(p.info.id);
      return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
    }

    // session.updated (archived)
    if (t === "session.updated" && p.info) {
      if (p.info.directory) sessionCwd.set(p.info.id, p.info.directory);
      if (p.info.time?.archived) {
        sessions.delete(p.info.id);
        sessionCwd.delete(p.info.id);
        return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
      }
      return null;
    }

    // session.status → idle = Stop (busy is ignored; session creation
    // comes from session.created or ensureOpenCodeSessionExists on first event)
    if (t === "session.status" && p.sessionID) {
      if (p.status?.type === "idle") {
        const s = getSession(p.sessionID);
        return makePayload("Stop", p.sessionID, sessionCwd.get(p.sessionID), {
          last_assistant_message: s.lastAssistantText || undefined,
        });
      }
      return null;
    }

    // message.updated — track role for message parts
    if (t === "message.updated" && p.info?.id && p.info?.sessionID) {
      msgRoles.set(p.info.id, { role: p.info.role, sessionID: p.info.sessionID });
      if (msgRoles.size > 200) { msgRoles.delete(msgRoles.keys().next().value); }
      return null;
    }

    // message.part.updated — text
    if (t === "message.part.updated" && p.part?.type === "text" && p.part?.messageID) {
      const meta = msgRoles.get(p.part.messageID);
      if (!meta) return null;
      const text = p.part.text || "";
      if (meta.role === "user" && text) {
        return makePayload("UserPromptSubmit", meta.sessionID, sessionCwd.get(meta.sessionID), {
          prompt: text,
        });
      }
      if (meta.role === "assistant" && text) {
        getSession(meta.sessionID).lastAssistantText = text;
      }
      return null;
    }

    // message.part.updated — tool
    if (t === "message.part.updated" && p.part?.type === "tool" && p.part?.sessionID) {
      const st = p.part.state?.status;
      const cwd = sessionCwd.get(p.part.sessionID);
      const toolName = (p.part.tool || "").charAt(0).toUpperCase() + (p.part.tool || "").slice(1);
      if (st === "running" || st === "pending") {
        return makePayload("PreToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
          tool_input: typeof p.part.state?.input === "string"
            ? p.part.state.input
            : JSON.stringify(p.part.state?.input || {}).slice(0, 200),
        });
      }
      if (st === "completed" || st === "error") {
        return makePayload("PostToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
        });
      }
      return null;
    }

    // permission.asked
    if (t === "permission.asked" && p.id && p.sessionID) {
      const toolName = (p.permission || "").charAt(0).toUpperCase() + (p.permission || "").slice(1);
      const patterns = p.patterns || [];
      const toolInput = { patterns, metadata: p.metadata };
      if (p.permission === "bash" && patterns.length > 0) {
        toolInput.command = patterns.join(" && ");
      }
      if ((p.permission === "edit" || p.permission === "write") && patterns.length > 0) {
        toolInput.file_path = patterns[0];
      }
      return makePayload("PermissionRequest", p.sessionID, sessionCwd.get(p.sessionID), {
        tool_name: toolName,
        tool_input: permissionInputText(toolInput),
        permission_id: p.id,
        permission_title: `Allow ${toolName}`,
        permission_description: patterns.length > 0
          ? `OpenCode wants to run ${toolName}: ${patterns[0]}`
          : `OpenCode wants to run ${toolName}`,
        _opencode_request_id: p.id,
      });
    }

    // permission.replied
    if (t === "permission.replied" && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    // question.asked
    if (t === "question.asked" && p.id && p.sessionID) {
      const questions = Array.isArray(p.questions)
        ? p.questions.map(normalizeQuestion).filter(Boolean)
        : [];
      return makePayload("QuestionAsked", p.sessionID, sessionCwd.get(p.sessionID), {
        question_id: p.id,
        question_text: (p.questions || []).map(q => q.question).join("; ") || "OpenCode has a question",
        questions,
        _opencode_request_id: p.id,
      });
    }

    // question.replied / question.rejected
    if ((t === "question.replied" || t === "question.rejected") && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    return null;
  }

  return {
    "event": async ({ event }) => {
      try {
        const mapped = mapEvent(event);
        if (!mapped) return;

        // Permission request — hold connection for approval
        if (mapped.openCodeHook.hook_event_name === "PermissionRequest" && internalFetch) {
          const requestId = mapped.openCodeHook._opencode_request_id;
          sendAndWaitResponse(mapped).then(async (response) => {
            if (!response) return;
            const directive = response?.response?.directive;
            if (!directive) return;
            const reply = directive.type === "allow" ? "once" : "reject";
            const message = directive.type === "deny" ? directive.reason : undefined;
            try {
              await internalFetch(new Request(`http://localhost:${serverPort}/permission/${requestId}/reply`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ reply, message }),
              }));
            } catch {}
          });
          return;
        }

        // Question — hold connection for answer
        if (mapped.openCodeHook.hook_event_name === "QuestionAsked" && internalFetch) {
          const requestId = mapped.openCodeHook._opencode_request_id;
          sendAndWaitResponse(mapped).then(async (response) => {
            if (!response) return;
            const directive = response?.response?.directive;
            if (!directive) return;
            if (directive.type === "answer") {
              try {
                await internalFetch(new Request(`http://localhost:${serverPort}/question/${requestId}/reply`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ answers: [[directive.text]] }),
                }));
              } catch {}
            }
          });
          return;
        }

        // Regular events — fire and forget
        await sendToSocket(mapped);
      } catch {
        // Fail open: if NotchTune is unavailable, don't block OpenCode
      }
    },

    "shell.env": async (input, output) => {
      output.env.NOTCHTUNE_ACTIVE = "1";
      for (const v of ENV_KEYS) {
        if (process.env[v]) output.env["_OI_" + v] = process.env[v];
      }
    },
  };
}

function capitalized(name) {
  return (name || "").charAt(0).toUpperCase() + (name || "").slice(1);
}

function preview(value) {
  return typeof value === "string" ? value : JSON.stringify(value || {}).slice(0, 200);
}

// V2 forms are field lists; a question card can show the ones with options.
function questionFromField(field, index) {
  const options = Array.isArray(field?.options)
    ? field.options.map(normalizeQuestionOption).filter(Boolean)
    : [];
  if (options.length === 0) return null;

  return {
    question: String(field.title || field.label || field.key || `Question ${index + 1}`),
    header: field.key || `Question ${index + 1}`,
    options,
    multi_select: field.type === "multiselect" || Boolean(field.multiple),
  };
}

async function setupV2(ctx) {
  const defaultCwd = ctx.location?.directory || "";
  const sessionCwd = new Map();
  const lastText = new Map();
  const running = new Set();
  const toolNames = new Map();
  let stopped = false;

  const cwdFor = (event, sessionID) => {
    const directory = event.location?.directory || sessionCwd.get(sessionID) || defaultCwd;
    if (directory) sessionCwd.set(sessionID, directory);
    return directory;
  };

  function forget(sessionID) {
    sessionCwd.delete(sessionID);
    lastText.delete(sessionID);
    running.delete(sessionID);
  }

  function mapEvent(event) {
    const d = event.data || {};
    const sid = d.sessionID;

    switch (event.type) {
      case "session.created":
        // Subagents get child sessions; they aren't sessions the user started.
        if (d.parentID) return null;
        return makePayload("SessionStart", sid, d.location?.directory || cwdFor(event, sid));

      case "session.deleted":
      case "session.archived": {
        const payload = makePayload("SessionEnd", sid, cwdFor(event, sid));
        forget(sid);
        return payload;
      }

      case "session.inbox.enqueued": {
        if (d.item?.type !== "user") return null;
        return makePayload("UserPromptSubmit", sid, cwdFor(event, sid), {
          prompt: d.item.payload?.text || "",
        });
      }

      case "session.execution.started":
        running.add(sid);
        return null;

      case "session.text.ended":
        if (d.text) lastText.set(sid, d.text);
        return null;

      case "session.tool.input.started":
        toolNames.set(d.id, d.name);
        if (toolNames.size > 200) toolNames.delete(toolNames.keys().next().value);
        return null;

      case "session.tool.called":
        return makePayload("PreToolUse", sid, cwdFor(event, sid), {
          tool_name: capitalized(toolNames.get(d.id)),
          tool_input: preview(d.input),
        });

      case "session.tool.success":
      case "session.tool.failed":
        return makePayload("PostToolUse", sid, cwdFor(event, sid), {
          tool_name: capitalized(toolNames.get(d.id)),
        });

      case "session.execution.succeeded":
      case "session.execution.failed":
      case "session.execution.interrupted":
      case "session.idle":
        // A turn can end in more than one of these; report it once.
        if (!running.delete(sid)) return null;
        return makePayload("Stop", sid, cwdFor(event, sid), {
          last_assistant_message: lastText.get(sid) || undefined,
        });

      case "permission.asked": {
        const resources = d.resources || [];
        const toolName = capitalized(d.action);
        const toolInput = { patterns: resources, metadata: d.metadata };
        if (d.action === "bash" && resources.length > 0) {
          toolInput.command = resources.join(" && ");
        }
        if ((d.action === "edit" || d.action === "write") && resources.length > 0) {
          toolInput.file_path = resources[0];
        }
        return makePayload("PermissionRequest", sid, cwdFor(event, sid), {
          tool_name: toolName,
          tool_input: permissionInputText(toolInput),
          permission_id: d.id,
          permission_title: `Allow ${toolName}`,
          permission_description: d.message || (resources.length > 0
            ? `OpenCode wants to run ${toolName}: ${resources[0]}`
            : `OpenCode wants to run ${toolName}`),
          _opencode_request_id: d.id,
        });
      }

      case "permission.replied":
        return makePayload("PostToolUse", sid, cwdFor(event, sid));

      case "form.created": {
        const form = d.form;
        if (!form?.id || !form.sessionID) return null;
        const fields = Array.isArray(form.fields) ? form.fields : [];
        const questions = fields.map(questionFromField).filter(Boolean);
        if (questions.length === 0) return null;
        return makePayload("QuestionAsked", form.sessionID, cwdFor(event, form.sessionID), {
          question_id: form.id,
          question_text: form.title || questions.map((q) => q.question).join("; "),
          questions,
          _opencode_request_id: form.id,
          _opencode_field_key: fields.find((f) => questionFromField(f, 0))?.key,
        });
      }

      case "form.replied":
      case "form.cancelled":
        return makePayload("PostToolUse", sid, cwdFor(event, sid));

      default:
        return null;
    }
  }

  async function forward(mapped) {
    const hook = mapped.openCodeHook;
    const sessionID = hook.session_id.replace(/^opencode-/, "");

    if (hook.hook_event_name === "PermissionRequest") {
      const response = await sendAndWaitResponse(mapped);
      const directive = response?.response?.directive;
      if (!directive) return;
      await ctx.permission.reply({
        sessionID,
        requestID: hook._opencode_request_id,
        decision: directive.type === "allow" ? "once" : "reject",
        message: directive.type === "deny" ? directive.reason : undefined,
      });
      return;
    }

    if (hook.hook_event_name === "QuestionAsked") {
      const response = await sendAndWaitResponse(mapped);
      const directive = response?.response?.directive;
      if (directive?.type !== "answer" || !hook._opencode_field_key) return;
      await ctx.session.form?.reply?.({
        sessionID,
        formID: hook._opencode_request_id,
        answer: { [hook._opencode_field_key]: directive.text },
      });
      return;
    }

    await sendToSocket(mapped);
  }

  const events = ctx.event.subscribe();
  const iterator = events[Symbol.asyncIterator]();

  // `setup` has to return: the stream never ends on its own.
  (async () => {
    while (!stopped) {
      const { value, done } = await iterator.next();
      if (done) return;
      try {
        const mapped = mapEvent(value);
        // Unawaited: a held approval mustn't stop the events behind it.
        if (mapped) forward(mapped).catch(() => {});
      } catch {
        // Fail open: if NotchTune is unavailable, don't block OpenCode
      }
    }
  })().catch(() => {});

  return async () => {
    stopped = true;
    await iterator.return?.();
  };
}

const runsOnV2 = await import("@opencode/plugin").then(() => true, () => false);

export default runsOnV2 ? { id: "notchtune", setup: setupV2 } : serverV1;
