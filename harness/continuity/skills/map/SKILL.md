---
name: map
description: Generate or refresh the cached project map at .claude/project-map.md so future sessions skip re-scouting. Triggers on /map, "map the project", "refresh project map", "generate project map".
---

# Map

Survey the repo and write a concise project map to `.claude/project-map.md`.
The file is auto-injected at session start by the continuity hook (## Project map section),
so future sessions do not need to re-scout the codebase.

## Procedure

1. Survey the repo from the current working directory. Collect:
   - Top-level directory layout (key dirs and their purpose, 1 line each).
   - Entry points: main script, binary, server start command.
   - Build and test commands (from Makefile, package.json, pyproject.toml, etc.).
   - Key conventions: language/runtime version, module system, lint/format tool.
   - Where things live: config, assets, tests, generated output.
   - Any active TODO/FIXME clusters worth flagging (file path + rough count; do not list each item).

2. Write the map. Rules:
   - Plain markdown, no em-dashes, ASCII only.
   - Hard cap: 120 lines total. Be ruthless -- one line per fact, no prose padding.
   - Target: `<cwd>\.claude\project-map.md` (create `.claude\` if absent).
   - Overwrite any existing map.

3. Confirm with one line: "Project map written to <absolute-path> (N lines). Auto-injects at next session start."

## Anti-patterns

- Do not print the full map to chat -- the path and line count are enough.
- Do not create files outside `.claude\` in the project.
- Do not run the test suite or build; read config files only.
- If the repo is very large, focus on the top 2 levels of directories and the most-edited files; do not stall on exhaustive enumeration.
