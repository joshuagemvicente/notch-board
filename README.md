# NotchBoard

A macOS notch app for your boards — **Trello**, **GitHub Projects**, **Linear**, **Jira**, and **Azure DevOps**.

Boards you care about float up first (pins, your overdue work, recent activity, and the repo you’re in). Expand the island → open a board → list or kanban, move cards, focus a task, track time.

Requires **macOS 14+**.

---

## Download (no build)

1. Grab the latest zip from **[Releases](https://github.com/joshuagemvicente/NotchBoard/releases/latest)**
2. Unzip → drag `NotchBoard.app` to `/Applications`
3. First launch (unsigned builds): right-click → **Open**, or:

```bash
xattr -cr /Applications/NotchBoard.app
open /Applications/NotchBoard.app
```

---

## Develop with SweetPad (recommended)

Best path if you use **Cursor** or **VS Code**.

### 1. Install tools

| Need | How |
|------|-----|
| **Xcode** | Mac App Store (full app — not just CLI tools) |
| **XcodeGen** | `brew install xcodegen` |
| **SweetPad** | VSCode Extensions → search **SweetPad** → Install |

### 2. Generate the Xcode project

```bash
cd NotchBoard
xcodegen generate
```

Re-run `xcodegen generate` whenever you change `project.yml` or add/remove source folders.

### 3. Build & run

1. Open this folder in Cursor / VS Code  
2. Command Palette (`⌘⇧P`) → **SweetPad: Build & Run** (or use the SweetPad sidebar)  
3. Pick scheme **NotchBoard** → destination **My Mac**

The app is a menu-bar / notch UI (`LSUIElement`) — look at the **top of the screen**, not the Dock.

### SweetPad tips

- **Build** — compile without launching  
- **Build & Run** — launch the Debug app  
- **Test** — run `NotchBoardTests`  
- If indexing feels stuck: regenerate (`xcodegen generate`), then SweetPad → select the `NotchBoard` scheme again  

This repo already points SweetPad at `NotchBoard.xcodeproj` (see `.vscode/settings.json`).

---

## Or use Xcode

```bash
xcodegen generate
open NotchBoard.xcodeproj
```

Select scheme **NotchBoard** → **My Mac** → `⌘R`.

---

## Or use the CLI

```bash
xcodegen generate
xcodebuild -scheme NotchBoard -destination 'platform=macOS' build
# then open the built .app from DerivedData, or:
xcodebuild -scheme NotchBoard -destination 'platform=macOS' \
  -derivedDataPath build build
open build/Build/Products/Debug/NotchBoard.app
```

**Package a zip for sharing:**

```bash
./scripts/package.sh
# → dist/NotchBoard-<version>.zip
```

---

## Connect accounts

Open **Settings** from the island / menu and add a service. Personal tokens work out of the box.

| Service | What you need |
|---------|----------------|
| **Trello** | API key + token ([Power-Ups admin](https://trello.com/power-ups/admin)) — use **write** scope for moves |
| **GitHub** | PAT with `project` + `repo` (Projects **Write** to move cards) |
| **Linear** | API key with write access |
| **Jira** | Site + email + API token |
| **Azure DevOps** | Org + PAT (Work Items Read & Write) |

Optional OAuth: set `OAuth*` keys in `project.yml` / Info.plist and register redirect `notchboard://oauth/callback`. **Don’t commit real secrets.**

**Permissions that help:** Accessibility (VS Code repo detection), Calendar (meeting countdown). Missing ones just skip those features.

---

## Test

**SweetPad:** Command Palette → **SweetPad: Test**

**CLI:**

```bash
xcodegen generate
xcodebuild test -scheme NotchBoard -destination 'platform=macOS'
```

---

## Website (landing page)

```bash
cd website
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). More in [`website/README.md`](website/README.md).

---

## Project map

```
NotchBoard/     App, notch UI, providers, focus engine
NotchBoardTests Unit tests
project.yml     XcodeGen project definition
skills/         Local agent / design skills
website/        Next.js marketing site
```

---

## Contributing & license

See [CONTRIBUTING.md](CONTRIBUTING.md) for PRs and releases.  
License: [MIT](LICENSE)
