# Cursor Operator — Design Language

Goal: make Cursor Operator (a native macOS SwiftUI app) look and feel like the
**Cursor desktop app** (the Agents / Composer redesign). This document is the
single source of truth for the visual system: color, typography, spacing,
radii, and component recipes.

## How this was derived

- **Authoritative source (color + font):** extracted directly from the installed
  Cursor app, so these are real values, not guesses:
  - Colors: `Cursor.app/Contents/Resources/app/extensions/theme-cursor/themes/cursor-dark-color-theme.json`
    (theme name: **"Cursor Dark Anysphere"**, the default dark theme).
  - Fonts: the workbench CSS font stacks in
    `Cursor.app/.../out/vs/workbench/workbench.desktop.main.css` plus the bundled
    font files under `.../out/media/`.
- **Reference for layout/feel:** screenshots of the actual Cursor desktop app
  (Agents home, an agent chat/composer view, the General settings page).
- **Not used for color:** `https://cursor.com/agents` is behind auth and the
  public marketing site (`cursor.com`) is a light-themed Tailwind site, so it
  does **not** represent the app chrome.
- Spacing/radius/padding values are still **eyeball-calibrated from the
  screenshots** (the theme JSON does not define layout); tune those by eye.

---

## 1. Foundations

### 1.1 Mood / principles

- **Flat, dark, neutral.** Near-black greys, no blur/vibrancy in content areas,
  almost no pure black and no pure white. Color is used sparingly and only as a
  signal (green = on/active, orange = command, blue = code/links).
- **Quiet chrome, loud content.** Borders are barely-there (low-alpha white),
  surfaces are separated by tiny luminance steps rather than hard lines.
- **Dense but breathable.** Small type (12–14px), tight rows, generous padding
  inside cards and inputs, soft medium corner radii.
- **Force dark mode.** The whole app is dark regardless of system appearance.

### 1.2 Color tokens

**The core idea (this is how Cursor actually does it):** there are only a few
opaque near-black backgrounds, and almost everything else — every text shade,
border, hover, and selection — is the **single base color `#E4E4E4` painted at a
low alpha** over those backgrounds. Don't author a ladder of opaque greys; layer
translucent `#E4E4E4` instead. This is what gives Cursor its cohesive look.

Opaque backgrounds:

| Token         | Hex       | Usage                                                  |
| ------------- | --------- | ------------------------------------------------------ |
| `bg.content`  | `#181818` | Main content / detail canvas (`editor.background`)     |
| `bg.chrome`   | `#141414` | Sidebar, panels, popovers, widgets (`sideBar/panel`)   |
| `bg.dropdown` | `#181818` | Dropdown / menu surface                                |

> Note the direction: **the sidebar/chrome (`#141414`) is darker than the main
> canvas (`#181818`)** — the opposite of a typical "elevated sidebar". Recessed,
> not raised.

Base overlay color: **`#E4E4E4`** (a near-white). All values below are this color
at the given alpha (hex alpha shown for parity with the theme file):

| Token             | Value (alpha)        | Usage                                              |
| ----------------- | -------------------- | -------------------------------------------------- |
| `text.primary`    | `#E4E4E4` @ 92% (EB) | Primary labels, titles, active rows                |
| `text.secondary`  | `#E4E4E4` @ 55% (8D) | Descriptions, inactive sidebar rows, group text    |
| `text.placeholder`| `#E4E4E4` @ 37% (5E) | Input placeholders, timestamps, faint hints        |
| `surface.wash`    | `#E4E4E4` @ 4% (0A)  | Input / field fill over the dark bg                |
| `border.subtle`   | `#E4E4E4` @ 7% (13)  | Card / input / panel borders, dividers             |
| `select.hover`    | `#E4E4E4` @ 7% (11)  | Hovered list/sidebar row                           |
| `select.active`   | `#E4E4E4` @ 12% (1E) | Selected list/sidebar row                          |
| `border.focus`    | `#E4E4E4` @ 15% (26) | Focus ring / focused control border                |

Accents (use sparingly, as signals — these are Cursor's actual "Anysphere" hues):

| Token             | Hex       | Usage                                                  |
| ----------------- | --------- | ------------------------------------------------------ |
| `accent.blue`     | `#81A1C1` | Primary button fill, links, file paths (`textLink`)    |
| `accent.blue.hover`| `#87A6C4`| Primary button hover                                   |
| `on.accent`       | `#191C22` | Text/icon on top of `accent.blue` (near-black)         |
| `accent.cyan`     | `#88C0D0` | Badges / counts (text on it = `#141414`)               |
| `accent.green`    | `#3FA266` | Toggle ON, success / ready status                      |
| `accent.orange`   | `#F1B467` | Warnings, slash commands (`/commit`) — foreground tone |
| `accent.orange.deep`| `#D2943E`| Warning border / stronger orange accent              |
| `accent.danger`   | `#E34671` | Errors, destructive emphasis (pink-red)                |
| `btn.secondary`   | `#626262` | Secondary/neutral button fill (hover `#818181`)        |

> The orange for slash commands is inferred from the theme's warning hues
> (`editorWarning.foreground #F1B467`, `inputValidation.warningBorder #D2943E`);
> tune against the real chat UI if needed.

Optional — syntax palette for rendering code in chat (from the theme's
`tokenColors`, "Anysphere" set):

| Role            | Hex       | | Role          | Hex       |
| --------------- | --------- |-| ------------- | --------- |
| String          | `#A8CC7C` | | Type / cyan   | `#82D2CE` |
| Function        | `#EBC88D` | | Constant/var  | `#AAA0FA` |
| Parameter       | `#EFB080` | | Keyword punct | `#D6D6DD` |
| Number/storage  | `#F8C762` | | String alt    | `#E394DC` |

> The app currently uses `.thickMaterial` window background and `.quaternary`
> card fills (system defaults). Replace those with the opaque `bg.*` colors +
> translucent `#E4E4E4` overlays above to kill the macOS vibrancy and get the
> flat Cursor look.

### 1.3 Typography

Confirmed from Cursor's workbench CSS: the UI font stack is literally
`font-family: SF Pro, -apple-system, BlinkMacSystemFont, sans-serif` — i.e. the
**macOS system font**. Cursor bundles **no** custom UI sans (no Inter/Geist), so
on a native SwiftUI app `Font.system` is an exact match, for free. The only
bundled programming font is **JetBrains Mono**.

- **UI sans:** system / SF Pro → `Font.system(...)` (default design). Do not
  bundle a webfont; the system font *is* what Cursor uses.
- **Monospace:** **JetBrains Mono** for file paths, commit SHAs, branch names,
  inline code. Bundle `JetBrainsMono-Regular.ttf` (register via
  `CTFontManager`/Info.plist `ATSApplicationFontsPath`) and fall back to
  `Font.system(design: .monospaced)` if absent.

Type scale (sizes in pt, since this is a native app):

| Role                     | Size | Weight             | Color            |
| ------------------------ | ---- | ------------------ | ---------------- |
| Page title (e.g. "General") | 20 | semibold (600)     | `text.primary`   |
| Section / group header   | 12   | medium (500)       | `text.placeholder`  |
| Row / card title         | 13   | medium (500)       | `text.primary`   |
| Body / list item         | 13   | regular (400)      | `text.primary`   |
| Description / subtitle   | 12   | regular (400)      | `text.secondary` |
| Caption / timestamp / kbd hint | 11 | regular (400)  | `text.placeholder`  |
| Code / path / SHA        | 12   | regular (400) mono | `accent.blue`    |

- Line height: comfortable, ≈1.4× for body/descriptions.
- Active sidebar item: bump weight to medium and color to `text.primary`;
  inactive items stay `text.secondary`.
- Group/section labels ("Workspaces", "PR Preferences", "Notifications",
  "Privacy") are **sentence case** (not uppercase), small, `text.placeholder`.

### 1.4 Spacing & radii

- **Spacing scale:** 4, 6, 8, 10, 12, 16, 20, 24 pt. Default gap between
  unrelated blocks is 16; intra-card stack is 6–8; row padding is 8–10.
- **Borders:** hairline (1px / 0.5pt @2x) using `border.subtle` (`border.focus` when focused).
- **Shadows:** essentially none in content. Depth comes from luminance steps.

### 1.4.1 Border radius

Four-step radius scale. Bias toward soft, medium rounding — nothing sharp,
nothing fully circular except true pills.

| Token        | Value | Shape                                                         |
| ------------ | ----- | ------------------------------------------------------------- |
| `radius.sm`  | 6     | Chips, badges, kbd hints, inline code, small dropdowns       |
| `radius.md`  | 8     | Buttons, single-line inputs, sidebar selection, menus        |
| `radius.lg`  | 10    | Settings cards / rows, panels                                |
| `radius.xl`  | 12    | Prompt / composer box, large containers, sheets              |
| `radius.full`| `∞`   | Capsule pills ("Ask"), toggles, avatars                      |

Per-component reference (from the screenshots):

| Component                              | Radius        |
| -------------------------------------- | ------------- |
| Prompt / composer input box           | `xl` (12)     |
| Settings card / row                    | `lg` (10)     |
| Secondary / ghost button              | `md` (8)      |
| Dropdown / picker ("GitHub", "Share Data") | `md` (8) |
| Single-line text field / search       | `md` (8)      |
| Sidebar selected/hover row            | `md` (8)      |
| Mode/model pill in composer footer    | `sm` (6)      |
| "Ask" pill, status chips              | `full` (capsule) |
| Inline code / file-path chip          | `sm` (6)      |
| kbd hint (`⌘N`, `⇧Tab`)               | `sm` (6)      |
| Toggle / switch                       | `full` (capsule) |

Notes:
- Apply the **same** radius to the fill and its 1px border stroke so the edge
  stays crisp (in SwiftUI, stroke the same `RoundedRectangle`/`Capsule` shape
  used for the fill, or use `.clipShape`).
- Nested radius rule: when a control sits inside a padded container, the inner
  radius should be ≤ the outer minus the padding so corners stay concentric
  (e.g. a `sm` pill inside an `xl` composer box).
- True pills/toggles use `Capsule()` (= `radius.full`), not a fixed large value.

### 1.5 Iconography

- SF Symbols, monochrome line style, ~14–16pt.
- Default tint `text.secondary`; active/selected `text.primary`; status icons
  use the matching accent (green check, orange warning, red error).

---

## 2. Component recipes

### 2.1 Sidebar

- Background `bg.chrome` (`#141414`, darker than the content canvas); no visible
  scrollbar track.
- Top action row ("New Agent") with leading icon + trailing `⌘N` kbd hint in
  `text.placeholder`.
- Group header ("Workspaces") in section-label style.
- Workspace rows: leading icon (folder/cloud) + name (`text.secondary`, 13);
  nested task rows indented, with a trailing timestamp (`text.placeholder`, 11) and
  optional small branch glyph.
- **Selected row:** fill `select.active`, `radius.md`, text → `text.primary` medium.
- Hover row: fill `select.hover`.
- Pinned footer (account / "Refer friends") separated by a `border.subtle`
  divider.

### 2.2 Settings cards (rows)

- Container: fill `surface.wash`, `radius.lg`, 1px `border.subtle`, padding 16.
- Layout: leading `VStack` (title `text.primary` 13 medium + description
  `text.secondary` 12) on the left, control (dropdown / toggle / button) pinned
  right.
- Group these under a section label with ~20pt of space above the label.

### 2.3 Buttons

**Secondary / ghost** (the default, e.g. "Plan New Idea", "Run in Cloud",
"Checkout…", "Continue in Cloud", "Log Out"):

- Fill `surface.wash` (or transparent), 1px `border.subtle`, `radius.md`,
  padding 6 v / 12 h, label `text.primary` 13. (A heavier neutral fill of
  `btn.secondary` `#626262` is also used for solid secondary buttons.)
- Hover: fill `select.hover`, border `border.focus`.
- Optional inline kbd hint (e.g. `⇧Tab`) rendered in `text.placeholder`.

**Primary** (used sparingly for the main CTA / confirm):

- Fill `accent.blue` `#81A1C1`, label/icon `on.accent` `#191C22` (dark),
  `radius.md`, same padding; hover `accent.blue.hover` `#87A6C4`.
- Reserve for one action per surface; everything else is ghost.

**Destructive:** ghost button with `accent.danger` label.

### 2.4 Inputs (prompt / composer / search / text fields)

- Fill `surface.wash`, 1px `border.subtle`, `radius.xl` (prompt) / `radius.md`
  (single-line), padding 12–16.
- Placeholder `text.placeholder`.
- Composer footer holds inline pills (mode chip, model dropdown) and a trailing
  mic/send affordance; pills use `select.active` + `radius.sm`.
- Focus: brighten border to `border.focus` (no heavy glow).

### 2.5 Pills / chips / badges

- `radius.sm` (or capsule for status pills), padding 2 v / 8 h, 11–12px.
- Neutral chip: `select.active` fill + `text.secondary`.
- Count badge: `accent.cyan` `#88C0D0` fill + `#141414` text.
- "Ask"/success chip: `accent.green` @ ~15% fill + `accent.green` text.
- Inline code / path chip: `select.active` fill + `accent.blue` mono text.

### 2.6 Toggles

- macOS switch styled to accent: ON track `accent.green` `#3FA266`, OFF track
  `surface.wash`/`select.active`, white knob.

### 2.7 Status & inline tokens in chat

- Slash commands (`/commit`): `accent.orange` `#F1B467`.
- File paths / SHAs / branches: monospace (JetBrains Mono), `accent.blue`, often
  on a `select.active` chip.
- Status lines: green check (done/ready) `accent.green`, orange triangle
  (warning) `accent.orange`, pink-red triangle (error) `accent.danger`.

---

## 3. SwiftUI mapping

Define tokens once and reuse. Suggested shape:

```swift
import SwiftUI

// Hex helper
extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// Cursor theme tokens (values from "Cursor Dark Anysphere")
enum CursorTheme {
    // Base overlay color — almost everything is this at low alpha
    static let base = Color(hex: 0xE4E4E4)

    // Opaque backgrounds (note: chrome is DARKER than content)
    static let bgContent  = Color(hex: 0x181818)   // main canvas
    static let bgChrome   = Color(hex: 0x141414)   // sidebar / panels / popovers

    // base @ alpha
    static let textPrimary    = base.opacity(0.92)
    static let textSecondary  = base.opacity(0.55)
    static let textPlaceholder = base.opacity(0.37)
    static let surfaceWash    = base.opacity(0.04) // input / card fill
    static let borderSubtle   = base.opacity(0.07)
    static let selectHover    = base.opacity(0.07)
    static let selectActive   = base.opacity(0.12)
    static let borderFocus    = base.opacity(0.15)

    // Accents
    static let blue       = Color(hex: 0x81A1C1)   // primary button, links, paths
    static let blueHover  = Color(hex: 0x87A6C4)
    static let onAccent   = Color(hex: 0x191C22)   // text on blue
    static let cyan       = Color(hex: 0x88C0D0)   // badges
    static let green      = Color(hex: 0x3FA266)   // toggle on / success
    static let orange     = Color(hex: 0xF1B467)   // warnings / slash commands
    static let orangeDeep = Color(hex: 0xD2943E)
    static let danger     = Color(hex: 0xE34671)   // errors (pink-red)
    static let btnSecondary = Color(hex: 0x626262) // solid neutral button

    // Radii (use Capsule() for `full` — pills, toggles)
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 10
    static let radiusXL: CGFloat = 12
}

// Type roles — system font (= SF Pro) for UI, JetBrains Mono for code
extension Font {
    static let pageTitle    = Font.system(size: 20, weight: .semibold)
    static let sectionLabel = Font.system(size: 12, weight: .medium)
    static let rowTitle     = Font.system(size: 13, weight: .medium)
    static let body13       = Font.system(size: 13, weight: .regular)
    static let description  = Font.system(size: 12, weight: .regular)
    static let caption11    = Font.system(size: 11, weight: .regular)
    // Falls back to system monospaced if JetBrains Mono isn't bundled
    static let codeInline   = Font.custom("JetBrains Mono", size: 12)
}
```

### Migration notes (current → target)

The current views rely on SwiftUI/macOS defaults; to adopt this system:

- Force dark: apply `.preferredColorScheme(.dark)` at the app root.
- Replace `.containerBackground(.thickMaterial, for: .window)` with solid
  `CursorTheme.bgContent` (canvas) / `bgChrome` (sidebar) backgrounds — this
  kills the macOS vibrancy that breaks the flat look.
- Replace `.background(.quaternary, in: RoundedRectangle(cornerRadius: 8))` on
  cards with `surfaceWash` fill + `borderSubtle` stroke + `radius.lg`.
- Replace ad-hoc `.foregroundStyle(.secondary/.tertiary)` with `textSecondary`/
  `textPlaceholder` for consistent contrast.
- Map `.green`/`.yellow`/`.orange`/`.red` status colors to
  `green`/`orange`/`danger` tokens.
- Apply the type roles above instead of `.callout`/`.caption`/`.headline`
  defaults so sizes/weights match Cursor.
- Style `List(.sidebar)` selection to `selectActive` + `radius.md` rather than
  the default accent-tinted selection.

---

## 4. Quick reference

- Backgrounds: content `#181818`, chrome/sidebar `#141414` (chrome is *darker*).
- Everything else = base `#E4E4E4` at alpha: text 92% / 55% / 37%, fill 4%,
  border 7%, hover 7%, selection 12%, focus 15%.
- Signals: blue `#81A1C1` (primary btn/links), cyan `#88C0D0` (badges),
  green `#3FA266`, orange `#F1B467`, danger `#E34671` (pink-red);
  text on blue = `#191C22`.
- Radii: 6 (chip/kbd) / 8 (button/input/dropdown/row) / 10 (card) / 12 (composer);
  capsule for pills & toggles. Match stroke radius to fill; keep nested corners concentric.
- Type: system font (= SF Pro) for UI, JetBrains Mono for code; 11/12/13/20pt;
  weights 400 / 500 / 600.
- No shadows; depth comes from luminance + translucent overlays, not vibrancy.
