"use strict";
// web-dash server.js
// Single-file Node 24 HTTP dashboard + command deck. Zero npm deps: http, fs, path, os, crypto, child_process only.
// Env overrides:
//   CLAUDE_DIR               - defaults to os.homedir()/.claude
//   WEBDASH_PORT             - defaults to 7777
//   WEBDASH_BIND             - defaults to 127.0.0.1
//   WEBDASH_CLAUDE_EXE       - path to claude binary (default: C:\Users\qq\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe)
//   WEBDASH_CLAUDE_ARGS_PRE  - JSON array of args to prepend before [-p, prompt, --output-format, text]; for test stubs only

const http   = require("http");
const fs     = require("fs");
const path   = require("path");
const os     = require("os");
const crypto = require("crypto");
const cp     = require("child_process");

const CLAUDE_DIR = process.env.CLAUDE_DIR || path.join(os.homedir(), ".claude");
const PORT  = parseInt(process.env.WEBDASH_PORT || "7777", 10);
const BIND  = process.env.WEBDASH_BIND || "127.0.0.1";
const CLAUDE_EXE = process.env.WEBDASH_CLAUDE_EXE ||
  "C:\\Users\\qq\\AppData\\Roaming\\npm\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe";

// Optional args prepended before [-p, prompt, ...]; used only for test stubs.
// E.g. set WEBDASH_CLAUDE_ARGS_PRE='["C:\\stub.js"]' and WEBDASH_CLAUDE_EXE='node'
var CLAUDE_ARGS_PRE = [];
(function() {
  var pre = process.env.WEBDASH_CLAUDE_ARGS_PRE;
  if (pre) {
    try { CLAUDE_ARGS_PRE = JSON.parse(pre); } catch (e) {}
  }
  if (!Array.isArray(CLAUDE_ARGS_PRE)) CLAUDE_ARGS_PRE = [];
})();

const JOBS_LOG   = path.join(CLAUDE_DIR, "webdash-jobs.log");
const TOKEN_FILE = path.join(CLAUDE_DIR, "webdash-token");
const MAX_OUTPUT = 16 * 1024;  // 16 KB rolling cap per job
const MAX_JOBS   = 50;

// USD per million tokens: in, out, cache_write, cache_read
const PRICING = {
  opus:   { in: 15.0,  out: 75.0,  cw: 18.75, cr: 1.50 },
  sonnet: { in: 3.0,   out: 15.0,  cw: 3.75,  cr: 0.30 },
  haiku:  { in: 1.0,   out: 5.0,   cw: 1.25,  cr: 0.10 }
};

function modelFamily(modelId) {
  if (!modelId) return "sonnet";
  const m = String(modelId).toLowerCase();
  if (m.indexOf("opus")  !== -1) return "opus";
  if (m.indexOf("haiku") !== -1) return "haiku";
  return "sonnet";
}

function tokenCost(usage, modelId) {
  const p = PRICING[modelFamily(modelId)];
  const inTok  = (usage.input_tokens || 0);
  const outTok = (usage.output_tokens || 0);
  const cwTok  = (usage.cache_creation_input_tokens || 0);
  const crTok  = (usage.cache_read_input_tokens || 0);
  return (inTok * p.in + outTok * p.out + cwTok * p.cw + crTok * p.cr) / 1e6;
}

// Read a text file as UTF-8 and strip the BOM if present. PowerShell 5.1
// Set-Content -Encoding UTF8 writes a BOM, which JSON.parse rejects.
function readText(filePath) {
  let s = fs.readFileSync(filePath, "utf8");
  if (s.charCodeAt(0) === 0xFEFF) s = s.slice(1);
  return s;
}

// Parse a .jsonl file line by line without loading all into memory.
// Returns array of parsed objects, skipping bad lines silently.
function readJsonl(filePath) {
  let content;
  try {
    content = readText(filePath);
  } catch (e) {
    return [];
  }
  const results = [];
  const lines = content.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    try {
      results.push(JSON.parse(line));
    } catch (e) {
      // skip unparseable lines
    }
  }
  return results;
}

// Recursively list .jsonl files under a directory with optional mtime filter.
function listJsonlFiles(dir, mtimeAfter) {
  const results = [];
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (e) {
    return results;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const sub = listJsonlFiles(full, mtimeAfter);
      for (const f of sub) results.push(f);
    } else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
      try {
        const stat = fs.statSync(full);
        if (!mtimeAfter || stat.mtimeMs >= mtimeAfter) {
          results.push({ filePath: full, mtimeMs: stat.mtimeMs });
        }
      } catch (e) {
        // skip
      }
    }
  }
  return results;
}

// ---- State file reading ----
// State files live in CLAUDE_DIR/state/<session-id>.json
function readSessions() {
  const stateDir = path.join(CLAUDE_DIR, "state");
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
  let files;
  try {
    files = fs.readdirSync(stateDir, { withFileTypes: true });
  } catch (e) {
    return [];
  }
  const sessions = [];
  for (const entry of files) {
    if (!entry.isFile() || !entry.name.endsWith(".json")) continue;
    const full = path.join(stateDir, entry.name);
    let stat;
    try {
      stat = fs.statSync(full);
    } catch (e) {
      continue;
    }
    if (stat.mtimeMs < cutoff) continue;
    let data;
    try {
      data = JSON.parse(readText(full));
    } catch (e) {
      continue;
    }
    const sessionId = entry.name.replace(/\.json$/, "");
    const cwdVal = data.cwd || "";
    const cwdLeaf = cwdVal ? path.basename(cwdVal) || cwdVal : sessionId;
    const updatedAt = data.updated_at || new Date(stat.mtimeMs).toISOString();
    const updatedMs = (function() {
      try { return new Date(updatedAt).getTime(); } catch (e) { return stat.mtimeMs; }
    })();
    sessions.push({
      id: sessionId,
      title: cwdLeaf,
      state: data.state || "idle",
      summary: data.summary || "",
      cwd: cwdVal,
      ageSeconds: Math.max(0, Math.round((Date.now() - updatedMs) / 1000)),
      updatedAt: updatedAt,
      transcriptPath: data.transcript_path || "",
      _updatedMs: updatedMs
    });
  }
  // newest first
  sessions.sort(function(a, b) { return b._updatedMs - a._updatedMs; });
  return sessions;
}

// ---- Context % from transcript ----
function readContextFromTranscript(transcriptPath) {
  if (!transcriptPath) return null;
  let events;
  try {
    events = readJsonl(transcriptPath);
  } catch (e) {
    return null;
  }
  // Find last non-sidechain assistant message with usage
  for (let i = events.length - 1; i >= 0; i--) {
    const evt = events[i];
    if (evt.isSidechain === true) continue;
    if (evt.type !== "assistant") continue;
    if (!evt.message || !evt.message.usage) continue;
    const usage = evt.message.usage;
    if (usage.input_tokens == null) continue;
    const total = (usage.input_tokens || 0)
      + (usage.cache_read_input_tokens || 0)
      + (usage.cache_creation_input_tokens || 0)
      + (usage.output_tokens || 0);
    const limit = 200000;
    return {
      pct: Math.min(100, Math.round(100 * total / limit)),
      usedTokens: total,
      limit: limit
    };
  }
  return null;
}

// ---- 7-day spend with 30s cache ----
var spendCache = null;
var spendCacheAt = 0;
const SPEND_CACHE_TTL = 30000;

function computeSpend() {
  const now = Date.now();
  if (spendCache && (now - spendCacheAt) < SPEND_CACHE_TTL) {
    return spendCache;
  }
  const projectsDir = path.join(CLAUDE_DIR, "projects");
  const days = 7;
  const cutoffMs = Date.now() - days * 24 * 60 * 60 * 1000;
  const cutoffDay = new Date(cutoffMs).toISOString().slice(0, 10);

  const files = listJsonlFiles(projectsDir, cutoffMs);
  const byDay = {};
  for (const fileInfo of files) {
    const events = readJsonl(fileInfo.filePath);
    for (const evt of events) {
      if (evt.type !== "assistant") continue;
      if (!evt.message || !evt.message.usage) continue;
      const usage = evt.message.usage;
      if (usage.input_tokens == null) continue;

      let day;
      try {
        day = evt.timestamp
          ? new Date(evt.timestamp).toISOString().slice(0, 10)
          : new Date(fileInfo.mtimeMs).toISOString().slice(0, 10);
      } catch (e) {
        day = new Date(fileInfo.mtimeMs).toISOString().slice(0, 10);
      }
      if (day < cutoffDay) continue;

      const modelId = (evt.message && evt.message.model) ? evt.message.model : "";
      const cost = tokenCost(usage, modelId);
      const outTok = usage.output_tokens || 0;
      if (!byDay[day]) byDay[day] = { usd: 0, outTokens: 0 };
      byDay[day].usd += cost;
      byDay[day].outTokens += outTok;
    }
  }

  // Build last 7 calendar days
  const dayList = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(Date.now() - i * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    dayList.push({
      date: d,
      usd: byDay[d] ? byDay[d].usd : 0,
      outTokens: byDay[d] ? byDay[d].outTokens : 0
    });
  }

  const today = new Date().toISOString().slice(0, 10);
  const todayUsd = byDay[today] ? byDay[today].usd : 0;

  spendCache = { todayUsd: todayUsd, days: dayList };
  spendCacheAt = now;
  return spendCache;
}

// ---- Prompt deck ----
function readPrompts() {
  const promptsFile = path.join(CLAUDE_DIR, "webdash-prompts.json");
  try {
    return JSON.parse(readText(promptsFile));
  } catch (e) {
    return [];
  }
}

// ---- Project allowlist ----
function readProjects() {
  const projectsFile = path.join(CLAUDE_DIR, "webdash-projects.json");
  try {
    const arr = JSON.parse(readText(projectsFile));
    if (!Array.isArray(arr)) return [];
    return arr;
  } catch (e) {
    return [];
  }
}

// ---- Token auth helpers ----
function readToken() {
  try {
    let t = readText(TOKEN_FILE).trim();
    return t || null;
  } catch (e) {
    return null;
  }
}

function isLoopback(addr) {
  if (!addr) return false;
  return addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1";
}

// Constant-time token comparison. Returns true if equal.
function safeTokenEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const ba = Buffer.from(a, "utf8");
  const bb = Buffer.from(b, "utf8");
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

// Returns true if the request is authorized for POST actions.
function isAuthorized(req) {
  const remote = (req.socket && req.socket.remoteAddress) || "";
  if (isLoopback(remote)) return true;  // loopback: token optional
  const stored = readToken();
  if (!stored) return false;  // token file missing => reject non-loopback
  const qParts = (req.url || "").split("?");
  const qs = qParts.length > 1 ? qParts[1] : "";
  const params = {};
  qs.split("&").forEach(function(part) {
    const kv = part.split("=");
    if (kv.length === 2) params[decodeURIComponent(kv[0])] = decodeURIComponent(kv[1]);
  });
  const provided = req.headers["x-webdash-token"] || params["token"] || "";
  return safeTokenEqual(stored, provided);
}

// ---- Job store ----
var jobs = [];  // array of job objects, newest first

function makeId() {
  return crypto.randomBytes(8).toString("hex");
}

function appendJobLog(job) {
  const line = JSON.stringify({
    id:        job.id,
    prompt:    job.prompt,
    project:   job.project,
    status:    job.status,
    startedAt: job.startedAt,
    endedAt:   job.endedAt,
    exitCode:  job.exitCode
  }) + "\n";
  try {
    fs.appendFileSync(JOBS_LOG, line, "utf8");
  } catch (e) {
    // non-fatal: log write failure should not break the server
  }
}

function capOutput(existing, chunk) {
  const combined = existing + chunk;
  if (combined.length <= MAX_OUTPUT) return combined;
  return combined.slice(combined.length - MAX_OUTPUT);
}

function pruneJobs() {
  if (jobs.length > MAX_JOBS) {
    const dropped = jobs.slice(MAX_JOBS);
    jobs = jobs.slice(0, MAX_JOBS);
    for (const job of dropped) {
      if (job.status === "running" && job._proc && job._proc.pid) {
        try {
          const tk = cp.spawn("taskkill", ["/PID", String(job._proc.pid), "/T", "/F"], { windowsHide: true, shell: false });
          tk.on("error", function() {});
        } catch (e) {}
      }
    }
  }
}

// ---- /api/state handler ----
function handleApiState(res) {
  const sessions = readSessions();
  const newestSession = sessions.length > 0 ? sessions[0] : null;
  const contextRaw = newestSession ? readContextFromTranscript(newestSession.transcriptPath) : null;
  const context = contextRaw || { pct: 0, usedTokens: 0, limit: 200000 };
  const spend   = computeSpend();
  const prompts = readPrompts();
  const rawProjects = readProjects();
  const projects = rawProjects.map(function(p, i) {
    return { index: i, label: p.label || "", path: p.path || "" };
  });

  const payload = {
    sessions: sessions.slice(0, 20).map(function(s) {
      return {
        id:         s.id,
        title:      s.title,
        state:      s.state,
        summary:    s.summary,
        cwd:        s.cwd,
        ageSeconds: s.ageSeconds,
        updatedAt:  s.updatedAt
      };
    }),
    context:  context,
    spend:    spend,
    prompts:  prompts,
    projects: projects
  };

  const body = JSON.stringify(payload);
  res.writeHead(200, {
    "Content-Type":   "application/json",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control":  "no-cache"
  });
  res.end(body);
}

// ---- /api/dispatch handler ----
function handleDispatch(req, res) {
  if (!isAuthorized(req)) {
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Unauthorized" }));
    return;
  }

  let body = "";
  let tooLarge = false;
  req.on("data", function(chunk) {
    if (tooLarge) return;
    body += chunk;
    if (body.length > 8192) {
      tooLarge = true;
      res.writeHead(413, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Request too large" }));
      req.destroy();
    }
  });
  req.on("end", function() {
    if (tooLarge) return;
    let parsed;
    try {
      parsed = JSON.parse(body);
    } catch (e) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Invalid JSON body" }));
      return;
    }

    const prompt = parsed.prompt;
    const projectIndex = parsed.projectIndex;
    // Optional model override. Allowlist only -- never pass an arbitrary string to the CLI.
    const MODEL_ALLOW = ["sonnet", "opus", "haiku", "fable"];
    let model = "";
    if (typeof parsed.model === "string" && MODEL_ALLOW.indexOf(parsed.model) !== -1) {
      model = parsed.model;
    }

    if (typeof prompt !== "string" || prompt.trim() === "") {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "prompt must be a non-empty string" }));
      return;
    }
    if (prompt.length > 4000) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "prompt must be <= 4000 characters" }));
      return;
    }
    if (typeof projectIndex !== "number" || !Number.isInteger(projectIndex)) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "projectIndex must be an integer" }));
      return;
    }

    const allProjects = readProjects();
    if (projectIndex < 0 || projectIndex >= allProjects.length) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "projectIndex out of range" }));
      return;
    }

    const project = allProjects[projectIndex];
    const cwd     = project.path;

    const id = makeId();
    const job = {
      id:        id,
      prompt:    prompt.slice(0, 200),
      project:   { label: project.label, path: project.path },
      model:     model || "default",
      status:    "running",
      startedAt: new Date().toISOString(),
      endedAt:   null,
      exitCode:  null,
      output:    "",
      _proc:     null
    };
    jobs.unshift(job);
    pruneJobs();

    let baseArgs = ["-p", prompt, "--output-format", "text"];
    if (model) baseArgs = baseArgs.concat(["--model", model]);
    const args = CLAUDE_ARGS_PRE.concat(baseArgs);
    let child;
    try {
      child = cp.spawn(CLAUDE_EXE, args, {
        cwd:         cwd,
        windowsHide: true,
        shell:       false
      });
    } catch (spawnErr) {
      job.status   = "error";
      job.endedAt  = new Date().toISOString();
      job.exitCode = -1;
      job.output   = "Failed to spawn: " + String(spawnErr);
      appendJobLog(job);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ id: id }));
      return;
    }

    job._proc = child;

    child.stdout.on("data", function(chunk) {
      job.output = capOutput(job.output, chunk.toString("utf8"));
    });
    child.stderr.on("data", function(chunk) {
      job.output = capOutput(job.output, chunk.toString("utf8"));
    });
    child.on("error", function(err) {
      job.status   = "error";
      job.endedAt  = new Date().toISOString();
      job.exitCode = -1;
      job.output   = capOutput(job.output, "\n[spawn error] " + String(err));
      job._proc    = null;
      appendJobLog(job);
    });
    child.on("close", function(code) {
      if (job.status === "killed") {
        // already marked by kill handler
        job._proc = null;
        return;
      }
      job.status   = (code === 0) ? "done" : "error";
      job.endedAt  = new Date().toISOString();
      job.exitCode = code;
      job._proc    = null;
      appendJobLog(job);
    });

    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ id: id }));
  });
}

// ---- /api/jobs handler ----
function handleGetJobs(res) {
  const out = jobs.map(function(j) {
    return {
      id:        j.id,
      prompt:    j.prompt,
      project:   j.project,
      status:    j.status,
      startedAt: j.startedAt,
      endedAt:   j.endedAt,
      exitCode:  j.exitCode,
      output:    j.output
    };
  });
  const body = JSON.stringify({ jobs: out });
  res.writeHead(200, {
    "Content-Type":   "application/json",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control":  "no-cache"
  });
  res.end(body);
}

// ---- /api/jobs/<id>/kill handler ----
function handleKillJob(req, res, jobId) {
  if (!isAuthorized(req)) {
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Unauthorized" }));
    return;
  }

  const job = jobs.find(function(j) { return j.id === jobId; });
  if (!job) {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Job not found" }));
    return;
  }
  if (job.status !== "running") {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Job is not running" }));
    return;
  }

  job.status  = "killed";
  job.endedAt = new Date().toISOString();
  appendJobLog(job);

  if (job._proc) {
    const pid = job._proc.pid;
    job._proc = null;
    // Kill process tree on Windows
    var tk = cp.spawn("taskkill", ["/PID", String(pid), "/T", "/F"], {
      windowsHide: true,
      shell:       false
    });
    tk.on("error", function() {});
  }

  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true }));
}

// ---- Inline HTML page ----
const HTML_PAGE = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Claude Code - web-dash</title>
<style>
  :root {
    --bg: #0d1117;
    --surface: #161b22;
    --border: #30363d;
    --text: #c9d1d9;
    --muted: #8b949e;
    --accent: #58a6ff;
    --green: #3fb950;
    --yellow: #d29922;
    --red: #f85149;
    --working-dot: #3fb950;
    --idle-dot: #8b949e;
    --amber: #e3a22b;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", monospace; font-size: 14px; line-height: 1.5; }
  header { background: var(--surface); border-bottom: 1px solid var(--border); padding: 12px 20px; display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
  header h1 { font-size: 16px; font-weight: 600; color: var(--accent); }
  .ctx-bar-wrap { display: flex; align-items: center; gap: 8px; flex: 1; min-width: 200px; }
  .ctx-bar-bg { background: var(--border); border-radius: 4px; height: 10px; flex: 1; overflow: hidden; }
  .ctx-bar-fill { height: 10px; border-radius: 4px; transition: width 0.4s, background 0.4s; background: var(--green); }
  .ctx-label { font-size: 12px; color: var(--muted); white-space: nowrap; }
  .spend-label { font-size: 13px; color: var(--text); white-space: nowrap; }
  .main { padding: 20px; max-width: 960px; }
  section { margin-bottom: 28px; }
  section h2 { font-size: 13px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 10px; }
  .session-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px; margin-bottom: 8px; display: flex; gap: 12px; align-items: flex-start; }
  .state-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; margin-top: 5px; }
  .state-dot.working { background: var(--working-dot); box-shadow: 0 0 6px var(--working-dot); }
  .state-dot.idle { background: var(--idle-dot); }
  .session-info { flex: 1; min-width: 0; }
  .session-title { font-weight: 600; color: var(--accent); font-size: 13px; }
  .session-meta { font-size: 11px; color: var(--muted); margin-top: 2px; }
  .session-summary { font-size: 12px; color: var(--text); margin-top: 6px; white-space: pre-wrap; word-break: break-word; max-height: 80px; overflow: hidden; }
  .chart-wrap { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 16px; }
  /* Prompt deck */
  .prompt-grid { display: flex; flex-wrap: wrap; gap: 8px; }
  .prompt-pair { display: flex; gap: 4px; }
  .prompt-btn { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); cursor: pointer; padding: 8px 14px; font-size: 13px; transition: background 0.15s, border-color 0.15s; }
  .prompt-btn:hover { background: var(--border); border-color: var(--accent); }
  .prompt-btn.copied { background: var(--green); color: #000; border-color: var(--green); }
  .prompt-btn.run-btn { background: #1c2432; border-color: var(--accent); color: var(--accent); }
  .prompt-btn.run-btn:hover { background: #243347; }
  /* Dispatch controls */
  .dispatch-row { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 10px; align-items: center; }
  .dispatch-row select { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); padding: 7px 10px; font-size: 13px; cursor: pointer; min-width: 180px; }
  .dispatch-row select:focus { outline: none; border-color: var(--accent); }
  .dispatch-textarea { width: 100%; background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); padding: 8px 12px; font-size: 13px; font-family: inherit; resize: vertical; min-height: 60px; margin-bottom: 8px; }
  .dispatch-textarea:focus { outline: none; border-color: var(--accent); }
  .run-dispatch-btn { background: var(--accent); border: 1px solid var(--accent); border-radius: 6px; color: #0d1117; cursor: pointer; padding: 8px 18px; font-size: 13px; font-weight: 600; transition: background 0.15s; }
  .run-dispatch-btn:hover { background: #79b8ff; }
  .run-dispatch-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  /* Job panel */
  .job-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 10px 14px; margin-bottom: 8px; }
  .job-header { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
  .job-chip { font-size: 11px; font-weight: 700; border-radius: 4px; padding: 2px 8px; letter-spacing: 0.04em; }
  .job-chip.running { background: var(--amber); color: #000; animation: pulse 1.2s infinite; }
  .job-chip.done    { background: var(--green); color: #000; }
  .job-chip.error   { background: var(--red);   color: #fff; }
  .job-chip.killed  { background: var(--red);   color: #fff; }
  @keyframes pulse { 0%,100% { opacity:1; } 50% { opacity:0.55; } }
  .job-prompt  { font-size: 12px; color: var(--text); flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .job-project { font-size: 11px; color: var(--muted); }
  .job-age     { font-size: 11px; color: var(--muted); white-space: nowrap; }
  .job-kill-btn { background: var(--surface); border: 1px solid var(--red); border-radius: 4px; color: var(--red); cursor: pointer; padding: 2px 10px; font-size: 11px; }
  .job-kill-btn:hover { background: var(--red); color: #fff; }
  .job-expand-btn { background: none; border: none; color: var(--muted); cursor: pointer; font-size: 11px; padding: 2px 6px; }
  .job-output { display: none; background: #0d1117; border: 1px solid var(--border); border-radius: 4px; padding: 8px; margin-top: 8px; font-family: monospace; font-size: 11px; white-space: pre-wrap; word-break: break-all; max-height: 300px; overflow-y: auto; color: var(--text); }
  .job-output.visible { display: block; }
  .banner { display: none; position: fixed; top: 0; left: 0; right: 0; background: var(--red); color: #fff; text-align: center; padding: 8px; font-size: 13px; font-weight: 600; z-index: 10; }
  .banner.visible { display: block; }
  .no-sessions { color: var(--muted); font-size: 13px; padding: 12px 0; }
</style>
</head>
<body>
<div class="banner" id="disconnBanner">Disconnected - retrying...</div>
<header>
  <h1>Claude Code</h1>
  <div class="ctx-bar-wrap">
    <div class="ctx-bar-bg"><div class="ctx-bar-fill" id="ctxFill" style="width:0%"></div></div>
    <span class="ctx-label" id="ctxLabel">ctx --</span>
  </div>
  <span class="spend-label" id="spendLabel">today --</span>
</header>
<div class="main">
  <section>
    <h2>Sessions</h2>
    <div id="sessionList"><div class="no-sessions">Loading...</div></div>
  </section>
  <section>
    <h2>7-Day Burn</h2>
    <div class="chart-wrap">
      <svg id="burnChart" width="100%" height="80" viewBox="0 0 600 80" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
        <text x="300" y="44" fill="#8b949e" text-anchor="middle" font-size="12">Loading...</text>
      </svg>
    </div>
  </section>
  <section>
    <h2>Command Deck</h2>
    <div class="dispatch-row">
      <select id="projectSelect"><option value="">-- no projects --</option></select>
      <select id="modelSelect" title="Model for dispatched runs">
        <option value="">model: default</option>
        <option value="haiku">haiku</option>
        <option value="sonnet">sonnet</option>
        <option value="opus">opus</option>
        <option value="fable">fable</option>
      </select>
    </div>
    <textarea class="dispatch-textarea" id="freePrompt" placeholder="Type a prompt or click Run on a deck button..."></textarea>
    <button class="run-dispatch-btn" id="runFreeBtn" onclick="dispatchFree()">Run</button>
    <div style="margin-top:16px">
      <div class="prompt-grid" id="promptGrid"><span style="color:var(--muted);font-size:13px">No prompts configured.</span></div>
    </div>
  </section>
  <section id="jobsSection">
    <h2>Jobs</h2>
    <div id="jobList"><div class="no-sessions">No jobs yet.</div></div>
  </section>
</div>
<script>
  var state = null;
  var pollTimer = null;
  var jobPollTimer = null;
  var jobPollActive = false;
  var storedToken = localStorage.getItem("webdash_token") || "";
  var expandedJobs = {};

  function fmtAge(sec) {
    if (sec < 60) return sec + "s ago";
    if (sec < 3600) return Math.floor(sec / 60) + "m ago";
    if (sec < 86400) return Math.floor(sec / 3600) + "h ago";
    return Math.floor(sec / 86400) + "d ago";
  }

  function fmtAgeMs(isoStr) {
    if (!isoStr) return "";
    var ms = Date.now() - new Date(isoStr).getTime();
    return fmtAge(Math.max(0, Math.round(ms / 1000)));
  }

  function fmtUsd(v) {
    return "$" + (v || 0).toFixed(2);
  }

  function ctxColor(pct) {
    if (pct >= 80) return "#f85149";
    if (pct >= 60) return "#d29922";
    return "#3fb950";
  }

  function escHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function escAttr(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  // ---- project select ----
  var lastProjectCount = -1;
  function renderProjects(projects) {
    if (projects.length === lastProjectCount) return;
    lastProjectCount = projects.length;
    var sel = document.getElementById("projectSelect");
    var saved = localStorage.getItem("webdash_project");
    var html = projects.length === 0 ? "<option value=\\"\\" disabled>-- no projects configured --</option>" : "";
    for (var i = 0; i < projects.length; i++) {
      var p = projects[i];
      html += "<option value=\\"" + p.index + "\\">" + escHtml(p.label) + " (" + escHtml(p.path) + ")</option>";
    }
    sel.innerHTML = html;
    if (saved !== null) {
      for (var j = 0; j < sel.options.length; j++) {
        if (sel.options[j].value === saved) { sel.selectedIndex = j; break; }
      }
    }
    sel.onchange = function() { localStorage.setItem("webdash_project", sel.value); };

    var msel = document.getElementById("modelSelect");
    if (msel && !msel._wired) {
      var savedModel = localStorage.getItem("webdash_model");
      if (savedModel !== null) {
        for (var k = 0; k < msel.options.length; k++) {
          if (msel.options[k].value === savedModel) { msel.selectedIndex = k; break; }
        }
      }
      msel.onchange = function() { localStorage.setItem("webdash_model", msel.value); };
      msel._wired = true;
    }
  }

  function selectedProjectIndex() {
    var sel = document.getElementById("projectSelect");
    var v = sel.value;
    if (v === "" || v === null) return null;
    var n = parseInt(v, 10);
    return isNaN(n) ? null : n;
  }

  // ---- dispatch ----
  function postWithAuth(url, body, callback) {
    var headers = { "Content-Type": "application/json" };
    if (storedToken) headers["x-webdash-token"] = storedToken;
    fetch(url, { method: "POST", headers: headers, body: JSON.stringify(body) })
      .then(function(r) {
        if (r.status === 401) {
          var t = prompt("Enter webdash token (see ~/.claude/webdash-token):");
          if (t) {
            storedToken = t;
            localStorage.setItem("webdash_token", t);
            postWithAuth(url, body, callback);
          }
          return;
        }
        r.json().then(function(data) { callback(r.status, data); });
      })
      .catch(function(err) { callback(0, { error: String(err) }); });
  }

  function selectedModel() {
    var el = document.getElementById("modelSelect");
    return el ? el.value : "";
  }

  function dispatchPrompt(prompt) {
    var idx = selectedProjectIndex();
    if (idx === null) { alert("Select a project first."); return; }
    var body = { prompt: prompt, projectIndex: idx };
    var m = selectedModel();
    if (m) body.model = m;
    postWithAuth("/api/dispatch", body, function(status, data) {
      if (status === 200) {
        startJobPoll();
      } else {
        alert("Dispatch failed: " + (data.error || status));
      }
    });
  }

  function dispatchFree() {
    var prompt = document.getElementById("freePrompt").value.trim();
    if (!prompt) { alert("Enter a prompt."); return; }
    var btn = document.getElementById("runFreeBtn");
    btn.disabled = true;
    setTimeout(function() { btn.disabled = false; }, 2000);
    dispatchPrompt(prompt);
  }

  // ---- job polling ----
  function startJobPoll() {
    jobPollActive = true;
    if (!jobPollTimer) pollJobs();
  }

  function stopJobPoll() {
    jobPollActive = false;
    if (jobPollTimer) { clearTimeout(jobPollTimer); jobPollTimer = null; }
  }

  function pollJobs() {
    jobPollTimer = null;
    fetch("/api/jobs")
      .then(function(r) { return r.json(); })
      .then(function(data) {
        var jobList = data.jobs || [];
        renderJobs(jobList);
        var hasRunning = jobList.some(function(j) { return j.status === "running"; });
        if (hasRunning || jobPollActive) {
          jobPollTimer = setTimeout(pollJobs, 3000);
        } else {
          jobPollActive = false;
        }
      })
      .catch(function() {
        if (jobPollActive) jobPollTimer = setTimeout(pollJobs, 3000);
      });
  }

  function killJob(id) {
    postWithAuth("/api/jobs/" + id + "/kill", {}, function(status, data) {
      if (status !== 200) alert("Kill failed: " + (data.error || status));
      pollJobs();
    });
  }

  function toggleOutput(id) {
    expandedJobs[id] = !expandedJobs[id];
    pollJobs();
  }

  function renderJobs(jobList) {
    var el = document.getElementById("jobList");
    if (!jobList || jobList.length === 0) {
      el.innerHTML = "<div class=\\"no-sessions\\">No jobs yet.</div>";
      return;
    }
    var html = "";
    for (var i = 0; i < jobList.length; i++) {
      var j = jobList[i];
      var chipClass = j.status;
      html += "<div class=\\"job-card\\">";
      html += "<div class=\\"job-header\\">";
      html += "<span class=\\"job-chip " + chipClass + "\\">" + escHtml(j.status.toUpperCase()) + "</span>";
      html += "<span class=\\"job-prompt\\">" + escHtml(j.prompt) + "</span>";
      html += "<span class=\\"job-project\\">" + escHtml(j.project ? j.project.label : "") + (j.model && j.model !== "default" ? " &middot; " + escHtml(j.model) : "") + "</span>";
      html += "<span class=\\"job-age\\">" + fmtAgeMs(j.startedAt) + "</span>";
      if (j.status === "running") {
        html += "<button class=\\"job-kill-btn\\" onclick=\\"killJob('" + j.id + "')\\">Kill</button>";
      }
      if (j.output) {
        var expanded = expandedJobs[j.id] ? "visible" : "";
        var label = expandedJobs[j.id] ? "hide" : "output";
        html += "<button class=\\"job-expand-btn\\" onclick=\\"toggleOutput('" + j.id + "')\\">" + label + "</button>";
        html += "<pre class=\\"job-output " + expanded + "\\">" + escHtml(j.output) + "</pre>";
      }
      html += "</div>";
      html += "</div>";
    }
    el.innerHTML = html;
  }

  // ---- main state render ----
  function renderState(data) {
    // context gauge
    var ctx = data.context || {};
    var pct   = ctx.pct || 0;
    var used  = ctx.usedTokens || 0;
    var limit = ctx.limit || 200000;
    document.getElementById("ctxFill").style.width = Math.min(100, pct) + "%";
    document.getElementById("ctxFill").style.background = ctxColor(pct);
    var usedK = Math.round(used / 1000);
    var limitK = Math.round(limit / 1000);
    var ctxText = used > limit ? ("ctx " + pct + "% (" + usedK + "k, window " + limitK + "k)") : ("ctx " + pct + "% (" + usedK + "k/" + limitK + "k)");
    document.getElementById("ctxLabel").textContent = ctxText;

    // today spend
    var spend = data.spend || {};
    document.getElementById("spendLabel").textContent = "today " + fmtUsd(spend.todayUsd);

    // sessions
    var sessions = data.sessions || [];
    var listEl = document.getElementById("sessionList");
    if (sessions.length === 0) {
      listEl.innerHTML = "<div class=\\"no-sessions\\">No active sessions in the last 24h.</div>";
    } else {
      var html = "";
      for (var i = 0; i < sessions.length; i++) {
        var s = sessions[i];
        var dotClass = s.state === "working" ? "working" : "idle";
        var summary  = s.summary ? s.summary.substring(0, 300) : "";
        html += "<div class=\\"session-card\\">";
        html += "<div class=\\"state-dot " + dotClass + "\\"></div>";
        html += "<div class=\\"session-info\\">";
        html += "<div class=\\"session-title\\">" + escHtml(s.title) + "</div>";
        html += "<div class=\\"session-meta\\">" + escHtml(s.state) + " &middot; " + fmtAge(s.ageSeconds) + " &middot; " + escHtml(s.cwd) + "</div>";
        if (summary) {
          html += "<div class=\\"session-summary\\">" + escHtml(summary) + "</div>";
        }
        html += "</div></div>";
      }
      listEl.innerHTML = html;
    }

    // burn chart
    renderBurnChart(spend.days || []);

    // project select
    renderProjects(data.projects || []);

    // prompt deck
    renderPrompts(data.prompts || []);
  }

  var lastPromptCount = -1;
  function renderPrompts(prompts) {
    if (prompts.length === lastPromptCount) return;
    lastPromptCount = prompts.length;
    var el = document.getElementById("promptGrid");
    if (prompts.length === 0) {
      el.innerHTML = "<span style=\\"color:var(--muted);font-size:13px\\">No prompts configured.</span>";
      return;
    }
    var html = "";
    for (var i = 0; i < prompts.length; i++) {
      var p = prompts[i];
      html += "<div class=\\"prompt-pair\\">";
      html += "<button class=\\"prompt-btn\\" data-prompt=\\"" + escAttr(p.prompt) + "\\">" + escHtml(p.label) + "</button>";
      html += "<button class=\\"prompt-btn run-btn\\" data-run=\\"" + escAttr(p.prompt) + "\\">run</button>";
      html += "</div>";
    }
    el.innerHTML = html;
    // copy buttons
    var copyBtns = el.querySelectorAll(".prompt-btn:not(.run-btn)");
    for (var j = 0; j < copyBtns.length; j++) {
      (function(btn) {
        btn.addEventListener("click", function() {
          var text = btn.getAttribute("data-prompt");
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function() {
              flashCopied(btn);
            }).catch(function() {
              fallbackCopy(text, btn);
            });
          } else {
            fallbackCopy(text, btn);
          }
        });
      })(copyBtns[j]);
    }
    // run buttons
    var runBtns = el.querySelectorAll(".run-btn");
    for (var k = 0; k < runBtns.length; k++) {
      (function(btn) {
        btn.addEventListener("click", function() {
          var text = btn.getAttribute("data-run");
          dispatchPrompt(text);
        });
      })(runBtns[k]);
    }
  }

  function fallbackCopy(text, btn) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.left = "-9999px";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch(e) {}
    document.body.removeChild(ta);
    flashCopied(btn);
  }

  function flashCopied(btn) {
    btn.classList.add("copied");
    btn.textContent = "Copied!";
    setTimeout(function() {
      btn.classList.remove("copied");
      lastPromptCount = -1;
      if (state) renderPrompts(state.prompts || []);
    }, 1200);
  }

  function renderBurnChart(days) {
    var svg = document.getElementById("burnChart");
    if (!days || days.length === 0) {
      svg.innerHTML = "<text x=\\"300\\" y=\\"44\\" fill=\\"#8b949e\\" text-anchor=\\"middle\\" font-size=\\"12\\">No data</text>";
      return;
    }
    var maxUsd = 0;
    for (var i = 0; i < days.length; i++) {
      if (days[i].usd > maxUsd) maxUsd = days[i].usd;
    }
    if (maxUsd === 0) maxUsd = 0.01;
    var W = 600; var H = 80;
    var barH = 48; var labelY = H - 4;
    var n = days.length;
    var barW = Math.floor(W / n) - 4;
    var html = "";
    for (var i = 0; i < n; i++) {
      var d = days[i];
      var x = Math.round(i * (W / n) + 2);
      var fillH = Math.max(2, Math.round(barH * d.usd / maxUsd));
      var y = barH - fillH + 6;
      var dateShort = d.date.slice(5);
      var isToday = (i === n - 1);
      var barColor = isToday ? "#58a6ff" : "#30363d";
      html += "<rect x=\\"" + x + "\\" y=\\"" + y + "\\" width=\\"" + barW + "\\" height=\\"" + fillH + "\\" rx=\\"2\\" fill=\\"" + barColor + "\\" />";
      html += "<text x=\\"" + (x + barW / 2) + "\\" y=\\"" + labelY + "\\" fill=\\"#8b949e\\" text-anchor=\\"middle\\" font-size=\\"9\\">" + dateShort + "</text>";
      if (d.usd >= 0.01) {
        html += "<text x=\\"" + (x + barW / 2) + "\\" y=\\"" + (y - 2) + "\\" fill=\\"#c9d1d9\\" text-anchor=\\"middle\\" font-size=\\"9\\">" + fmtUsd(d.usd) + "</text>";
      }
    }
    svg.innerHTML = html;
  }

  function poll() {
    fetch("/api/state")
      .then(function(r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function(data) {
        state = data;
        document.getElementById("disconnBanner").classList.remove("visible");
        renderState(data);
      })
      .catch(function() {
        document.getElementById("disconnBanner").classList.add("visible");
      })
      .finally(function() {
        pollTimer = setTimeout(poll, 3000);
      });
  }

  poll();
  // start job poll so existing jobs show on load
  startJobPoll();
</script>
</body>
</html>`;

// ---- HTTP server ----
const server = http.createServer(function(req, res) {
  const urlPath  = req.url.split("?")[0];
  const method   = req.method || "GET";

  if (urlPath === "/api/state" && method === "GET") {
    try {
      handleApiState(res);
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }

  if (urlPath === "/api/dispatch" && method === "POST") {
    try {
      handleDispatch(req, res);
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }

  if (urlPath === "/api/jobs" && method === "GET") {
    try {
      handleGetJobs(res);
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }

  // /api/jobs/<id>/kill
  const killMatch = urlPath.match(/^\/api\/jobs\/([0-9a-f]+)\/kill$/);
  if (killMatch && method === "POST") {
    try {
      handleKillJob(req, res, killMatch[1]);
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }

  if ((urlPath === "/" || urlPath === "/index.html") && method === "GET") {
    const body = Buffer.from(HTML_PAGE, "utf8");
    res.writeHead(200, {
      "Content-Type":   "text/html; charset=utf-8",
      "Content-Length": body.length
    });
    res.end(body);
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("Not found");
});

server.on("error", function(e) {
  process.stderr.write("web-dash server error: " + e.message + "\n");
  process.exit(1);
});

server.listen(PORT, BIND, function() {
  process.stdout.write("web-dash listening on http://" + BIND + ":" + PORT + "\n");
});
