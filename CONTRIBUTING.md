# Contributing to NotchBoard

Thanks for helping. Keep changes focused and match the existing Swift / SwiftUI style.

## Setup

Prefer the **SweetPad** path in [README.md](README.md) (Cursor / VS Code). Short version:

1. Install [Xcode](https://apps.apple.com/app/xcode/id497799835) (full app) + `brew install xcodegen`
2. Install the **SweetPad** extension
3. `xcodegen generate` → **SweetPad: Build & Run** (scheme **NotchBoard**)

Or open `NotchBoard.xcodeproj` in Xcode / use the CLI (same README).

## Credentials

Do **not** commit real OAuth client IDs or secrets. Leave the `OAuth*` keys in `Info.plist` / `project.yml` empty, or use a local untracked override. Prefer personal API tokens for day-to-day development.

## Pull requests

- Run the unit tests before opening a PR:

```bash
xcodebuild test -project NotchBoard.xcodeproj -scheme NotchBoard \
  -destination 'platform=macOS'
```

- Prefer small PRs with a clear “why”.
- Update the README if you change build, install, or permission requirements.

## Cutting a release (maintainers)

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` if needed) in `project.yml`.
2. Commit, then tag and push:

```bash
git tag v0.1.0
git push origin v0.1.0
```

3. The [Release](../.github/workflows/release.yml) workflow builds `NotchBoard-<version>.zip` and attaches it to a GitHub Release.

Optional later: Apple Developer ID signing + notarization so Gatekeeper opens the app without `xattr` / right-click Open.
