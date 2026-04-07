# HiveRoom — Claude Code Guide

## Project Overview

HiveRoom is a web application built with plain HTML, CSS, and JavaScript (no framework, no build step).

**Files:**
- `index.html` — Main app (~776KB, single-file SPA with inline CSS/JS)
- `admin-avatar-update.html` — Admin avatar management page
- `help.html` — Help/documentation page
- `gemini-test.html` — Gemini AI integration test page
- `ads.txt` — Ad network verification file

## Critical: Token Efficiency Rules

### Never read large files in full

`index.html` is ~776KB. **Always use targeted reads:**

```bash
# Find a function/section — use Grep first
grep -n "functionName\|section-keyword" index.html

# Then read only the relevant lines
# Read tool: use offset + limit (e.g., offset=200, limit=50)
```

**Workflow for any index.html task:**
1. `Grep` for the relevant keyword/function name → get line numbers
2. `Read` only the surrounding block (offset + limit)
3. `Edit` precisely — never rewrite large sections

### Prefer targeted tools over broad reads

| Task | Do this | Not this |
|------|---------|---------|
| Find a function | `Grep pattern index.html` | Read whole file |
| Check a CSS class | `Grep "\.classname"` | Read style section |
| Find an event handler | `Grep "addEventListener\|onclick"` | Scan manually |

### Minimize back-and-forth

- Confirm the exact target (line range, function name) before editing
- If a task needs more than 3–4 searches without finding the target, stop and ask
- Don't explore speculatively — every tool call costs tokens

## Development Standards

### HTML/CSS/JS conventions

- Inline styles and scripts are acceptable (existing pattern in this project)
- Preserve existing code style — indentation, quotes, naming
- No framework imports; use vanilla JS
- No build tools — changes are direct file edits

### Editing safely

- For large files, always use `Edit` with precise `old_string` (include enough context to be unique)
- Never use `Write` to rewrite index.html — always `Edit`
- After editing, verify with a targeted `Grep` that the change landed correctly

### Before committing

```bash
# Quick sanity check — confirm no syntax errors in JS sections
node --input-type=module < <(grep -A9999 '<script' index.html | grep -B9999 '</script>' | sed 's/<[^>]*>//g') 2>&1 | head -20
```

## Common Patterns

### Finding a UI component
```
Grep: "id=\"component-name\"\|class=\"component-name\""  → get line number
Read: offset=<line-5>, limit=60
```

### Finding a JS function
```
Grep: "function functionName\|functionName ="  → get line number
Read: offset=<line-2>, limit=40
```

### Finding CSS for a class
```
Grep: "\.classname\s*{"  → get line number
Read: offset=<line>, limit=20
```

## Out of Scope

- Do not add build pipelines, bundlers, or package managers
- Do not split index.html into multiple files unless explicitly asked
- Do not add TypeScript or transpilation
