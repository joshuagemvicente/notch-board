# Island Design Contract

**Role A — Senior Apple Product Designer & Motion Specialist**  
Single source of truth for NotchBoard island + Settings. Role B implements against this document.

---

## 1. Tokens

### Typography — `IslandType`

| Token | Size / weight | Use |
|-------|---------------|-----|
| `timer` | 14pt semibold mono (digit) | Compact + expanded session time — **same size always** |
| `title` | 15pt semibold | Board/card titles in headers |
| `body` | 14pt medium | Card/board row primary text |
| `meta` | 13pt medium | Captions, reasons, chips, secondary labels |
| `micro` | 12pt medium | Rare secondary only (never primary labels) |

**Ban:** 8–9pt for readable UI. Icons may be 12–15pt for hit-target balance.

### Color roles — `IslandColor`

| Role | Token | Meaning |
|------|-------|---------|
| Focus (intent) | `focusAmber` | Scope / “what I’m aiming at” — outline treatment |
| Session (timing) | `sessionTeal` | Active timer / Track — filled + timer |
| Primary text | `textPrimary` | Titles, primary labels |
| Secondary | `textSecondary` | Captions (~0.55 dark / ~0.58 light) |
| Tertiary | `textTertiary` | De-emphasized meta (~0.38 / ~0.42) |
| Warning | `warning` | Errors inside the system (not raw `.orange`) |

**Focus vs Track (non-negotiable):** never both amber. Focus = amber outline/scope. Session/Track = teal fill + timer.

### Spacing — `IslandLayout`

| Step | Value | Use |
|------|-------|-----|
| `space1` | 4 | Tight icon gaps |
| `space2` | 6 | Row / chip gaps |
| `space3` | 8 | Control clusters |
| `space4` | 12 | Section breathing |
| `hitTarget` | ≥28 | Interactive controls min height/width |

Keep existing ear insets (`contentX`, `contentTopEars`, etc.).

---

## 2. Compact strip

Priority order (first match wins):

1. **Active session** — teal timer (`IslandType.timer`) + optional pause glyph + title (`meta`)
2. **Focus target (idle)** — amber scope glyph + title (`meta`)
3. **Meeting** — countdown label (`meta`)
4. **Ranked board** — service glyph + board name (`meta`)
5. **Empty** — quiet dual dots

Sprint progress capsule under strip only when **no** active session.

---

## 3. Expanded shell

```
┌─────────────────────────────────────────────┐
│ [Session bar — sticky when session.active]  │  ← always, all routes
├─────────────────────────────────────────────┤
│ Living caption (simplified) / route header  │
│ Content (list / board / card / create)      │
└─────────────────────────────────────────────┘
```

### Session bar (persistent)

When `session.isActive`:
- Phase caption (meta) · **timer (timer/teal)** · title (body, 1 line)
- Controls: Pause/Resume · Skip break (if break) · End
- Hit targets ≥28pt; VoiceOver labels required
- Present on **focus list, board detail, card detail, create board**

When idle but focus target set (focus list only): slim “NOW” + title + Start + Clear — amber, no teal.

Living caption **must not** duplicate session controls when the session bar is showing — keep create/refresh only on the right.

### Card row

- **Primary:** tap title → open card detail
- **Secondary cluster:** Focus (amber outline icon) · Track (teal when active; meta “Track” in list)
- **Overflow:** Move + Open in browser via context menu (Move icon optional if space; prefer menu on narrow lanes)

Row highlight: Focus → amber stroke/fill wash; Tracking → teal wash (prefer session over focus if both).

### Card detail header

Show **card title** (`IslandType.title`), never generic “Task”.

---

## 4. Settings IA

Sidebar order:

1. **General** — Launch at Login (`SMAppService`)
2. **Accounts** — OAuth-first; human copy; plist/scopes under Advanced
3. **Sessions** — Pomodoro / Deep Work / Stopwatch prefs, notifications, auto-focus
4. **Ranking** — shortlist count, signals, thresholds (no duplicate Active Repo master toggle)
5. **Schedule** — meeting countdown
6. **Active Repo** — detection toggle + **Open Accessibility Settings** button
7. **Appearance**
8. **About**

Deep links: `SettingsWindowController.show(tab:)` from empty/connect CTAs (`.accounts`, etc.).

Light tab transition ~200ms (`IslandMotion.viewSwitch`); connect success brief feedback.

---

## 5. Motion map

| Event | Token | Notes |
|-------|-------|-------|
| Island bloom / collapse | `morph` | Spring; only for shape hover |
| Route / content nav | `viewSwitch` | easeOut 200ms; **never** morph on route |
| Press / row hover | `press` | ~100ms; scale 0.97 |
| Settings tab change | `viewSwitch` | Same token |
| Refresh spinner | linear loop | **Off** when Reduce Motion |

### Reduce Motion

| Token | Fallback |
|-------|----------|
| `morph` | `reduced` (easeOut 100ms) |
| `viewSwitch` | `reduced` |
| `press` | linear 0 / scale 1 |
| Spinner | static icon |

No double `withAnimation` on the same route change. Shape animations bind to hover/size only — not `ui.route`.

---

## 6. Accessibility

- Session controls, rows, chips: labels + traits (not tooltips alone)
- Hit targets ≥28pt
- Expanded a11y hint is **route-aware** (focus list vs board vs card)
- Hover-gate limitation: island still expands primarily via pointer; keyboard path into expanded controls is a documented follow-up (Settings ⌘, remains available)

---

## 7. Annotated screens (Role A)

### Compact — session
`[ 12:34  Title… ]` — teal timer, primary title; no amber collision.

### Compact — focus (idle)
`[ ⌖ Title… ]` — amber scope; no timer.

### Expanded — focus list + session
Session bar (teal) sticky → simplified caption (create/refresh) → provider tabs → boards.

### Settings — Accounts
Connected hero (glyph + name + Connected) → Disconnect. Disconnected: prominent Continue with… → Advanced disclosure for tokens / plist notes.

---

## Success criteria (QA)

- Readable type (≥13pt body, ≥14pt timers) via one scale  
- Idle + expanded always make focusing vs timing obvious  
- Session pause/end available on every expanded route  
- Settings feel like a product, not a debug console  
- Motion intentional; Reduce Motion never left behind  
