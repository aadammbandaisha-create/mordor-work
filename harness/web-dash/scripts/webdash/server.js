"use strict";
// web-dash server.js
// Single-file Node 24 HTTP dashboard. Zero npm deps: http, fs, path, os only.
// Env overrides:
//   CLAUDE_DIR   - defaults to os.homedir()/.claude
//   WEBDASH_PORT - defaults to 7777
//   WEBDASH_BIND - defaults to 127.0.0.1

const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");

const CLAUDE_DIR = process.env.CLAUDE_DIR || path.join(os.homedir(), ".claude");
const PORT = parseInt(process.env.WEBDASH_PORT || "7777", 10);
const BIND = process.env.WEBDASH_BIND || "127.0.0.1";

// USD per million tokens: in, out, cache_write, cache_read
const PRICING = {
  opus:   { in: 15.0,  out: 75.0,  cw: 18.75, cr: 1.50 },
  sonnet: { in: 3.0,   out: 15.0,  cw: 3.75,  cr: 0.30 },
  haiku:  { in: 1.0,   out: 5.0,   cw: 1.25,  cr: 0.10 }
};

function modelFamily(modelId) {
  if (!modelId) return "sonnet";
  const m = String(modelId).toLowerCase();
  if (m.indexOf("opus") !== -1) return "opus";
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
    const updatedMs = (() => {
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
let spendCache = null;
let spendCacheAt = 0;
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

// ---- /api/state handler ----
function handleApiState(res) {
  const sessions = readSessions();
  const newestSession = sessions.length > 0 ? sessions[0] : null;
  const contextRaw = newestSession ? readContextFromTranscript(newestSession.transcriptPath) : null;
  const context = contextRaw || { pct: 0, usedTokens: 0, limit: 200000 };
  const spend = computeSpend();
  const prompts = readPrompts();

  const payload = {
    sessions: sessions.slice(0, 20).map(function(s) {
      return {
        id: s.id,
        title: s.title,
        state: s.state,
        summary: s.summary,
        cwd: s.cwd,
        ageSeconds: s.ageSeconds,
        updatedAt: s.updatedAt
      };
    }),
    context: context,
    spend: spend,
    prompts: prompts
  };

  const body = JSON.stringify(payload);
  res.writeHead(200, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-cache"
  });
  res.end(body);
}

// ---- HTML page ----
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
  .prompt-grid { display: flex; flex-wrap: wrap; gap: 8px; }
  .prompt-btn { background: var(--surface); border: 1px solid var(--border); border-radius: 6px; color: var(--text); cursor: pointer; padding: 8px 14px; font-size: 13px; transition: background 0.15s, border-color 0.15s; }
  .prompt-btn:hover { background: var(--border); border-color: var(--accent); }
  .prompt-btn.copied { background: var(--green); color: #000; border-color: var(--green); }
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
    <h2>Prompt Deck</h2>
    <div class="prompt-grid" id="promptGrid"><span style="color:var(--muted);font-size:13px">No prompts configured.</span></div>
  </section>
</div>
<script>
  var state = null;
  var pollTimer = null;

  function fmtAge(sec) {
    if (sec < 60) return sec + "s ago";
    if (sec < 3600) return Math.floor(sec / 60) + "m ago";
    if (sec < 86400) return Math.floor(sec / 3600) + "h ago";
    return Math.floor(sec / 86400) + "d ago";
  }

  function fmtUsd(v) {
    return "$" + (v || 0).toFixed(2);
  }

  function ctxColor(pct) {
    if (pct >= 80) return "#f85149";
    if (pct >= 60) return "#d29922";
    return "#3fb950";
  }

  function renderState(data) {
    // context gauge
    var ctx = data.context || {};
    var pct = ctx.pct || 0;
    var used = ctx.usedTokens || 0;
    var limit = ctx.limit || 200000;
    document.getElementById("ctxFill").style.width = Math.min(100, pct) + "%";
    document.getElementById("ctxFill").style.background = ctxColor(pct);
    document.getElementById("ctxLabel").textContent = "ctx " + pct + "% (" + Math.round(used / 1000) + "k/" + Math.round(limit / 1000) + "k)";

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
        var summary = s.summary ? s.summary.substring(0, 300) : "";
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

    // prompt deck (only if changed)
    var prompts = data.prompts || [];
    renderPrompts(prompts);
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
      html += "<button class=\\"prompt-btn\\" data-prompt=\\"" + escAttr(p.prompt) + "\\">" + escHtml(p.label) + "</button>";
    }
    el.innerHTML = html;
    var buttons = el.querySelectorAll(".prompt-btn");
    for (var j = 0; j < buttons.length; j++) {
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
      })(buttons[j]);
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
      // label is already embedded in data-prompt but we need the original label
      // re-fetch: just reload the deck
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
      var dateShort = d.date.slice(5); // MM-DD
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
</script>
</body>
</html>`;

// ---- HTTP server ----
const server = http.createServer(function(req, res) {
  const url = req.url.split("?")[0];
  if (url === "/api/state") {
    try {
      handleApiState(res);
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(e) }));
    }
    return;
  }
  if (url === "/" || url === "/index.html") {
    const body = Buffer.from(HTML_PAGE, "utf8");
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
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
