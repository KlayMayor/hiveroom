# HiveRoom — Claude Code Guide

## Project Overview

HiveRoom is a web application built with plain HTML, CSS, and JavaScript (no framework, no build step).

**Files:**
- `index.html` — Main app (~830KB, single-file SPA with inline CSS/JS)
- `admin-avatar-update.html` — Admin avatar management page
- `help.html` — Help/documentation page
- `gemini-test.html` — AI image generation test page (ERNIE-Image-Turbo via proxy)
- `oauth-callback.html` — Google OAuth callback handler
- `ads.txt` — Ad network verification file
- `CHANGELOG.md` — Development history log
- `ONCHAIN_DESIGN.md` — On-chain architecture reference
- `contracts/` — Solidity contracts (HIVEToken, HiveRoomTile, HiveRoomMarket, HiveRoomPaymaster)
- `ernie-server/` — AI image proxy server (Python: server.py, ws_proxy.py, proxy.py)
- `supabase/functions/` — Supabase Edge Functions

## Critical: Token Efficiency Rules

### Never read large files in full

`index.html` is ~830KB (~6800+ lines). **Always use targeted reads:**

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

## Pushing to GitHub (main branch protection)

Direct `git push` to `main` returns 403 (branch protection). Use the MCP tool instead:

```
mcp__github__push_files
  owner: "klaymayor"
  repo:  "hiveroom"
  branch: "main"
  files: [{ path: "index.html", content: "<full UTF-8 text>" }]
  message: "commit message"
```

**Agent pattern for large file push:**
1. Read index.html in 4 chunks (offset=0/1700/3400/5100, limit=1700)
2. Concatenate — verify last lines are `</body>` + `</html>`
3. Call `mcp__github__push_files` with plain UTF-8 content (NOT base64)
4. After push: `git fetch origin main && git reset --hard origin/main`

## Key Architecture

### Edit Room (AI-only mode)
The Edit Room panel is **AI-only** — no item/asset selection tabs.

- **con-left**: `ai-room-canvas` (640×640, displayed ~300px) + Generate/Regenerate buttons
- **con-right**: AI option form — Room Type select, Mood select, Wall Deco checkboxes (max 2), Furniture checkboxes (max 5), custom prompt input
- **Hidden**: `<canvas id="room-cv" style="display:none;">` — kept for JS `RCV` reference (do not remove)

Key functions:
| Function | Description |
|----------|-------------|
| `startEditRoom(room)` | Opens console, loads existing room.jpg onto `ai-room-canvas` |
| `generateAIRoom()` | POST to AI proxy → `job_id` → `pollJobResult()` |
| `pollJobResult()` | Polls `/job/<id>` every 2.5s, calls `applyAICanvas()` on success |
| `checkPendingJob()` | Resumes polling on `visibilitychange` (phone lock recovery) |
| `applyAICanvas(src)` | Draws AI image onto `ai-room-canvas` with `detectHexVertices()` hex clip |
| `registerRoom()` | Reads `ai-room-canvas` → JPEG → uploads to Supabase Storage as `room.jpg` |

### AGW Wallet (Abstract Global Wallet)
Cross-app wallet via `@privy-io/cross-app-connect` ECDH protocol.

- **App ID**: `cm04asygd041fmry9zmcyn5o5`
- **Popup URL**: `https://privy.abs.xyz/cross-app/connect`
- **localStorage keys**: `agw_addr`, `agw_shared`, `agw_pub`, `agw_transact_url`
- **Chain**: Abstract Testnet (chain ID `11124`)

Key functions:
| Function | Description |
|----------|-------------|
| `walletBtnClick()` | Shows AGW / MetaMask selector overlay |
| `connectAbstractWallet()` | ECDH key exchange + popup + smart wallet derivation |
| `_agwRequest(method, params)` | Encrypted cross-app transaction request |
| `_tryRestoreAGWWallet()` | Restores AGW connection from localStorage on page load |
| `disconnectWallet()` | Clears all AGW localStorage keys |

### Tips Popup
- **First visit only**: `initTips()` checks `localStorage.getItem('tips_seen')`. Shows popup if not set.
- **Manual reopen**: 💡 Tips button in header calls `openTips()`
- **On close**: `closeTips()` sets `localStorage.setItem('tips_seen', '1')`

### AI Image Generation
- **Proxy**: `https://oval-trombone-obedience.ngrok-free.dev`
- **Endpoint**: `POST /sdapi/v1/txt2img` → returns `{ job_id }`
- **Poll**: `GET /job/<id>` every 2.5s
- **Pending job**: stored in `localStorage` key `hiveroom_pending_job` for recovery

### On-chain Constants
```javascript
const ONCHAIN = {
  HIVE:      '0xE46AfBa60F86D34F110d5ADC5Ea763dB883096dE',  // ERC-20
  TILE:      '0xe02F5144303956dAe6eB42836D9Fc26A0Ca3277a',  // ERC-721 UUPS
  MARKET:    '0x49386B0d73Ac64BfD302ADd525712E2c5C0801A4',
  PAYMASTER: '0x8BCa39d4413AacaF5aE1FCEF499a7dB7045b22cB',
};
```
Network: Abstract Testnet, Chain ID `11124`

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
- Do not re-add item selection tabs (Wall/Floor/Furniture/Decor/Item) to Edit Room — it is intentionally AI-only
