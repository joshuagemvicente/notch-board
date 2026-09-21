# NotchBoard

A macOS menu bar app that puts your kanban boards one click away from the notch.
Connects to **Trello**, **GitHub Projects (v2)**, **Linear**, **Jira Cloud**, and
**Azure DevOps**, and surfaces the boards most relevant to what you're working
on *right now* — the **focus/context** twist:

1. **Pinned** boards (explicit override, always on top)
2. Boards with **your overdue / due-soon / stale assigned cards**
3. **Recently active** boards
4. The GitHub project of the **repo you're actively working in** (detected from
   the frontmost app: Terminal, iTerm2, or VS Code)

Click a board → it opens in your browser. No inline kanban in v1, but the data
model keeps cards/columns so it can be added without a migration.

## Download

Prebuilt builds ship on **GitHub Releases** (once the repo is published and a
`v*` tag is pushed):

**[Download latest release](https://github.com/joshuagemvicente/NotchBoard/releases/latest)**

1. Download `NotchBoard-*.zip`
2. Unzip and drag `NotchBoard.app` into `/Applications`
3. First launch (unsigned builds): right-click the app → **Open**, or clear
   quarantine:

```bash
xattr -cr /Applications/NotchBoard.app
open /Applications/NotchBoard.app
```

Requires **macOS 14+**.

> **Gatekeeper:** CI builds are ad-hoc signed (no Apple Developer ID / notarization
> yet). That is normal for early open-source macOS apps. Notarized releases can
> be added later with a Developer ID certificate.

## Build from source

### Prerequisites

- **Xcode** (Mac App Store — SwiftData `@Model` macros need the full toolchain)
- **XcodeGen** (`brew install xcodegen`)

### Run (Debug)

```bash
xcodegen generate
xcodebuild -project NotchBoard.xcodeproj -scheme NotchBoard \
  -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/NotchBoard.app
```

### Package a distributable zip

```bash
./scripts/package.sh
# → dist/NotchBoard-<version>.zip
```

## Credentials

- **Trello:** create a Power-Up at <https://trello.com/power-ups/admin> to get
  an API key, tap **Get token in browser**, approve NotchBoard, then paste the
  token (Trello does not support custom URL-scheme callbacks).
- **GitHub:** classic PAT with `project` + `repo`, or OAuth via
  `OAuthGitHubClientID` (+ optional `OAuthGitHubClientSecret`) in Info.plist.
  Card moves need Projects **Write**.
- **Linear:** personal API key, or `OAuthLinearClientID` / secret.
- **Jira Cloud:** site + email + API token, or Atlassian OAuth
  (`OAuthJiraClientID`). Account must be able to transition issues.
- **Azure DevOps:** org + PAT with Work Items (Read & Write), or Entra OAuth
  (`OAuthAzureClientID`).

For GitHub / Linear / Jira / Azure OAuth, register the redirect URI as
`notchboard://oauth/callback`. Personal tokens remain available as a fallback.
Do not commit real OAuth secrets — leave the plist keys empty for public builds.

## Tests

```bash
xcodebuild test -project NotchBoard.xcodeproj -scheme NotchBoard \
  -destination 'platform=macOS'
```

## Architecture

```
App/         NotchBoardApp (MenuBarExtra + Settings scenes), BoardStore (orchestrator)
Models/      SwiftData: Account, Board, Card, Column + API DTOs
Providers/   BoardProvider protocol → TrelloProvider (REST), GitHubProvider (GraphQL),
             GraphQLClient, KeychainService (tokens never touch SwiftData)
Focus/       FocusEngine (pure ranking, unit-tested), RankInputBuilder, FocusSettings
ActiveRepo/  ActiveRepoDetector (NSWorkspace + AppleScript), GitRemoteParser
Views/       PopoverView (focus shortlist + all boards), BoardRowView, SettingsView
```

Notes:
- Unsandboxed on purpose: Apple Events automation for frontmost-app detection.
- VS Code detection needs Accessibility permission (System Settings →
  Privacy & Security → Accessibility). Missing permission degrades silently.
- iTerm2 detection needs Shell Integration (`session.path`).
- OAuth Connect uses `notchboard://oauth/callback` (configure client IDs in Info.plist).

## Website

Marketing site (Next.js + shadcn + Manrope) lives in [`website/`](website/):

```bash
cd website && npm install && npm run dev
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, PR expectations, and how
maintainers cut a release (`git tag v0.1.0` → GitHub Actions attaches the zip).

## License

[MIT](LICENSE)
