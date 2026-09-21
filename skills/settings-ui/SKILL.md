---
name: settings-ui
description: >
  Build a polished macOS settings window with NavigationSplitView sidebar, detail panes,
  back/forward history, and a dedicated NSWindowController (fullSizeContentView). Use when
  adding or redesigning Settings for a Mac app — especially menu-bar / accessory apps.
---

# macOS Settings UI

## Pattern

1. **`SettingsWindowController`** — singleton `NSWindowController` with `.fullSizeContentView`, frame autosave, and activation-policy hooks for accessory apps.
2. **`SettingsView` shell** — `NavigationSplitView` sidebar (fixed ~200pt) + detail; toolbar back/forward history; `SettingsNavigation` singleton for deep links (`show(tab:)`).
3. **Detail panes** — one file per tab; always `Form` + `.formStyle(.grouped)` + `.scrollContentBackground(.hidden)` + `.contentMargins(.top, 8, for: .scrollContent)`.

## Tabs

Define a `SettingsTab` enum with `title` + `systemImage`. Route in `SettingsDetailView`.

## Controls

- Toggles: title + caption in a `VStack`, `.toggleStyle(.switch)`
- Theme: segmented `Picker`
- About: app icon, version, links; put Quit here for accessory apps

## Opening Settings

```swift
SettingsWindowController.show(tab: .accounts)
```

Replace `@Environment(\.openSettings)` when using a custom window. Redirect Cmd+, with `CommandGroup(replacing: .appSettings)`.

## Reference files

- `SettingsWindowController.swift`
- `SettingsPane.swift` (shell)
- `ExampleDetailPane.swift` (control patterns)
