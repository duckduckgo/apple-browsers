# [iOS] On-site Permission Manager — Implementation Plan

**Status: fully unblocked — zero open gates. Implementation may start immediately.**

**Kick-off was held on 2026-08-28, and the DRI answered every remaining follow-up item the same
day.** The decisions in this plan are now **ratified** — the working defaults held, kick-off's
corrections have been folded into this document, and the last design/copy items proceed on
documented defaults, to be finalized later in a working build. §10 (Assumptions register) records
the per-item status; nothing requires re-architecture.

Specifically:

- **Feature Flags Registry entry exists** for `sitePermissions`:
  https://app.asana.com/1/137249556945/project/1211834678943996/task/1217880888140745
  Link it from the flag's doc comment in Phase 1.
- **The privacy decisions are ratified**: Fire exempts fireproofed sites; Fire and "Remove All"
  clear per-site records only and preserve global defaults; the permission key is host-only.
  The privacy ping (OQ-7/OQ-21) is assumed fine and blocks nothing; the for-the-record ping can
  still be sent.
- **The former design/copy gates are cleared (DRI answers, 2026-08-28) — defaults adopted,
  to be finalized later in a working build:**
  - combined dialog (OQ-2) — sites are assumed able to request camera-only or microphone-only
    (the `WKMediaCaptureType` verification is assumed yes); the combined-dialog copy default is
    adopted (§6.5.1), marked for later copy review;
  - copy (OQ-3/OQ-4) — Figma copy verbatim where it exists, the scaling "needs to access your X"
    footer form where two phrasings compete, and minimal sensible strings for the still-missing
    cases, every new string marked for later copy review;
  - per-site header (OQ-12), menu membership (OQ-17), sheet rows (OQ-18) — defaults adopted;
    finalize after a working build;
  - pixels (OQ-16) — **resolved**: the DRI approved the final pixel set on 2026-08-28. The
    phases carry the exact wire names (Phase 3 Step 6, Phase 4 Step 7, Phase 6 Step 3);
  - the grant animation is **cut from v1** (DRI decision 2026-08-28 — OQ-6 is moot), and the
    **Voice Search denied-permission prompt is in scope**: Phase 3 gains that step in its place.

**Do not stop to ask about a known OQ.** Stop only on a genuine contradiction with no recorded
or derivable default (§11 lists the five that exist), or when one of the two yield rules
applies (§2.12 UI, §2.13 Xcode project).

---

## 0. How to read this document

| You need | Go to |
|---|---|
| What we're building and the settled constraints | §1 |
| The rules you must follow while implementing | §2 |
| Branch setup before Phase 1 | §3 |
| The six phases, one per PR | §4–§9 (Phase 1 … Phase 6) |
| Which OQ default applies where | §10 |
| Genuine ambiguities (5) | §11 |

**Source documents — read both before Phase 1:**

- [`requirements.md`](requirements.md) — authoritative product requirements, compiled from Asana
  and Figma. **§5–§6 carry the full screen inventory and the exact copy.** You have no Figma
  access; those sections are your Figma.
- [`tech-design.md`](tech-design.md) — the reviewed architecture and the 6-PR delivery plan (§5).
  Phase contents in this plan come from its §5 and are not re-scoped.
- [`platform-precedents.md`](platform-precedents.md) — shipped macOS/Android behavior with code
  citations. **Tie-breaker for anything the docs don't settle:** Asana-derived requirements
  first, then macOS behavior unless it doesn't make sense on mobile, then Android.

Do **not** open asana.com or figma.com links. They are in this document only so you can paste
them into PR descriptions.

---

## 1. Overview

### What is being built

Per-site permission management for **camera, microphone, and geolocation** on iOS — the
follow-on to the macOS Permission Center (shipped Dec 2025). Today iOS has per-session
permissions only: WebKit shows its own 2-option prompt, the one-shot OS prompt fires before the
user has engaged, and a single "Don't Allow" locks the whole app out of that permission for
every site with no recovery path. That is the root of a measured breakage problem (id.me: 173
reports in 3 months, >60% iOS).

Seven deliverables, spread across six PRs:

1. **A 3-option site dialog** (`Allow Once` / `Allow While Using Site` / `Never Allow`)
   replacing WebKit's 2-option prompt, for all three types plus a DuckDuckGo-SERP location variant.
2. **Reversed dialog order** — DDG's site dialog first, the OS dialog only after (and only if)
   the user allows. This is what protects the one-shot OS prompt.
3. **An on-site manager** — a conditional `Site Permissions` browser-menu row opening a
   per-site bottom sheet.
4. **Settings › Site Permissions** — global per-type defaults, the site list, per-site editing,
   remove one / remove all.
5. **Recovery from OS-level denial** — a reminder dialog and System Settings deep links, plus
   the redesigned Voice Search denied-permission prompt (added to scope 2026-08-28).
6. **Visual feedback** — status iconography. (The grant animation was **cut from v1** — DRI
   decision 2026-08-28.)
7. **Fire Button / fireproofing integration** for stored permissions.

### Decided constraints (do not re-litigate)

| Constraint | Meaning for you |
|---|---|
| **iOS-standalone** | No macOS changes. No shared cross-platform Permissions package. macOS is a reference implementation you read, not code you move. Persisted raw values stay byte-identical to macOS's (`"camera"`, `"microphone"`, `"geolocation"`) so a later convergence is cheap. |
| **Single local package** | Everything model-and-UI lives in `iOS/LocalPackages/SitePermissions` — one production target, one test target. App-side code is thin glue only. |
| **Single feature flag** | `sitePermissions`. No geolocation subflag. Every phase must leave the app releasable with the flag **off**. |
| **Duck.ai is an explicit exception** | duck.ai origins never route through this model, in **either** flag state. Both existing call sites keep their current branches verbatim. `AIChatWebViewController` is not touched at all. Ratified at kick-off. |
| **Global "Never Allow" prevents asking only** | It is **not** absolute: a stored per-site Always Allow keeps working under it (FR-9, resolving OQ-8). The one absolute rule is that global Never never *prompts*. Ratified at kick-off. |
| **No macOS-style shared extraction, no Core Data** | The store is a `@MainActor` class over `KeyValueStoring` with a plain plist wire format. |

### Estimate

≈ 21–25 person-days across the six PRs (tech-design §5). PRs 1–4 form a coherent camera/mic
milestone; PRs 5–6 add geolocation.
---

## 2. Working rules for the implementing agent

Treat this as a checklist. It is not advice — it is how this project is delivered.

### 2.1 Branching

- **One phase = one branch = one PR.**
- Phase 1 → `bartosz/on-site-permissions-1`, created **off `main`**.
- Every later branch forks off the previous one — a **stacked train**:
  `-2` off `-1`, `-3` off `-2`, `-4` off `-3`, `-5` off `-4`, `-6` off `-5`.
- The documentation branch `bartosz/on-site-permissions` is **never** a base for an
  implementation branch.
- **Never push.** Never force-touch a branch you did not create.

### 2.2 Documentation stays on the documentation branch

- **Never commit anything under `docs/on-site-permission-manager/` to an implementation branch.**
  That includes this plan, the project log, lesson files, and PR-description files.
- All plan updates, logs, notes, and `pr<N>-description.md` files go to
  `bartosz/on-site-permissions`.
- Practical loop: finish the phase on the implementation branch → `git switch
  bartosz/on-site-permissions` → write the log entry and the PR description → commit → switch
  back and start the next phase branch off the one you just finished.

### 2.3 Project memory

Use the **`/keep-project-log` skill**. Maintain `docs/on-site-permission-manager/project_log.md`
and lesson files **on the documentation branch** (the log does not exist yet — Phase 1 creates it).

Log, at minimum:

- each phase completion, with what shipped and what was deferred;
- each review outcome — suggestions applied, suggestions skipped, and **why** for the skipped ones;
- any decision you made that this plan did not pre-decide;
- any assumption from §10 (the assumptions register) that turned out wrong once you saw the code.

### 2.4 Verification

- Use **XcodeBuildMCP** — load the **`xcodebuildmcp-cli` skill** first. Do not shell out to raw
  `xcodebuild`/`xcrun`/`simctl`.
- Run **only the tests relevant to the change**: the package test target plus the touched app
  suites. Not the full suite by default.
- **Never manually test in the simulator** — do not launch the app and drive its UI — unless the
  user gives explicit permission for that phase. Building and running unit tests is always allowed.

**Critical setup fact.** The repo's session-defaults profile
(`.xcodebuildmcp/config.yaml`, `activeSessionDefaultsProfile: ios`) sets `scheme: iOS Browser
Alpha`. **`iOS Browser Alpha.xcscheme` has no `<Testables>` block at all** — a test run against
it silently executes zero tests. **Always pass `--scheme "iOS Browser"` explicitly on every
test command.**

Any booted iOS 26 simulator works; the commands below use `iPhone 17`. Substitute whatever
`xcodebuildmcp simulator list` reports on your machine.

Build (compile-only, no launch):

```bash
xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"
```

Run one test target:

```bash
xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args -only-testing:SitePermissionsTests
```

Run several (repeat `-only-testing:`; adjust per phase):

```bash
xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args -only-testing:SitePermissionsTests -only-testing:UnitTests/FireExecutorTests
```

`--extra-args` takes an array. If your shell or the CLI's parser chokes on a value starting with a
dash, use the `=` form instead — `--extra-args="-only-testing:SitePermissionsTests"` — and repeat
the flag once per target. Confirm the tool surface with `xcodebuildmcp simulator test --help`
before assuming a syntax; the skill's rule is help-first discovery.

Package-manifest sanity. Two existing manifests already carry stale `.package(path:)` references
that resolve only because nothing exercises them — `iOS/LocalPackages/SetDefaultBrowser` points at
`../MetricBuilder` and `iOS/LocalPackages/VPNiOS` at `../VPN`, neither of which exists at that
path. Do not let the new package join them:

```bash
cd iOS/LocalPackages/SitePermissions && swift package resolve
```

`swift test` on the host will **not** work for this package — it imports UIKit/WebKit, so a host
build targets macOS and fails. Package tests run through the app scheme on an iOS simulator only.

Pixel definitions (Phases 3, 4, 6):

```bash
cd iOS && npm run validate-pixel-defs
```

### 2.5 Per-phase review loop

When a phase is code-complete, before declaring it done:

1. Spawn an **independent review agent** on the phase's diff to run **both**:
   (a) a normal correctness code review, and
   (b) a **Ponytail** over-engineering / simplification review.
2. When it returns: **apply no-brainer fixes automatically.** For suggestions with real
   trade-offs, use judgment — and **record the decision in the project log** either way.
3. **Re-run the targeted tests** after applying fixes.

### 2.6 Per-phase PR description

After the review loop, write `docs/on-site-permission-manager/pr<N>-description.md`
(e.g. `pr1-description.md`) with a suggested PR title and body. Follow
[`.github/PULL_REQUEST_TEMPLATE.md`](../../.github/PULL_REQUEST_TEMPLATE.md) — it exists, and it
wants: `Task/Issue URL`, `Tech Design URL`, `CC`, `Description` (plain English, no class names),
numbered `Testing Steps`, `Impact` (High/Medium/Low/None), `What could go wrong?`,
`Quality Considerations`.

Every PR body must state **the flag state** — that the feature is behind `sitePermissions`, off
by default — and, for Phase 1, that the Fire worker runs even with the flag off, deliberately.

Set `Tech Design URL` to the main Asana task:
`https://app.asana.com/1/137249556945/task/1213800892997347`

Set `Task/Issue URL` to the phase's own subtask:

| PR | Asana task |
|---|---|
| 1 | https://app.asana.com/1/137249556945/task/1217863452475658 |
| 2 | https://app.asana.com/1/137249556945/task/1217863452475659 |
| 3 | https://app.asana.com/1/137249556945/task/1217863452475660 |
| 4 | https://app.asana.com/1/137249556945/task/1217863452475661 |
| 5 | https://app.asana.com/1/137249556945/task/1217863452475662 |
| 6 | https://app.asana.com/1/137249556945/task/1217863452475663 |

Paste these URLs. **Do not try to open them** — you have no Asana access, and you do not need it.

**Commit these files on `bartosz/on-site-permissions`, never on the implementation branch.**

### 2.7 Sub-agents

Spawn and delegate freely — exploration, test writing, reviews. The review loop in §2.5 is
mandatory; everything else is your call.

### 2.8 Git

- Commit as you go. Clean, logical history.
- **Squash fixups before declaring a phase done.** Interactive rebase is unavailable in this
  environment — use non-interactive equivalents: `git reset --soft <base> && git commit`, or
  `git commit --amend`.
- End **every** commit message with the repo's co-author trailer:

  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  ```

- **Never push.**

### 2.9 Repo rules

Before writing code in an area, read the matching file in `.cursor/rules/`:

| Area | Rule file |
|---|---|
| Any Swift | `code-style.mdc` |
| Any Swift | `anti-patterns.mdc` |
| Store, settings persistence (Phase 1) | `user-defaults-storage.mdc` |
| Pixels (Phases 3, 4, 6) | `pixels.mdc` |
| New files/dirs, pbxproj (Phase 1) | `project-structure.mdc` |

Note: `project-structure.mdc` names the project as `iOS/DuckDuckGo-iOS.xcodeproj` — correct.
Some older docs say `iOS/DuckDuckGo.xcodeproj`; **that path does not exist.**

Pixels use **PixelKit** (not the legacy `Pixel`/`DailyPixel`) plus JSON5 definitions validated
with `npm run validate-pixel-defs` from `iOS/`. Never put a domain, host, or URL in a pixel name
or parameter (`pixels.mdc:18` — the governing clause is the PII/URL rule; there is no
domain-specific line to cite).

### 2.10 Flag safety — every phase, no exceptions

Every phase must leave the app releasable with `sitePermissions` **off**:

- both legacy WKUIDelegate matrices run **verbatim**;
- no shim registration;
- nil menu builders and nil Settings builders;
- **the Fire worker is the one deliberate flag-off exception** (Phase 1) — it must burn stored
  data even when the flag is off, so a rollback cannot strand user data.

Each phase below carries its own flag-off checklist. Work through it before you call the phase done.

### 2.11 When to stop and ask

Stop and ask the user on a genuine contradiction with no recorded or derivable default, and
whenever one of the two yield rules below applies (§2.12, §2.13). A known open question is not a
blocker — §10 tells you what to assume. §11 lists the five genuine ambiguities found while
writing this plan; everything else has a default.

### 2.12 UI yield rule — never guess a design

You have **no Figma access**. Never guess or improvise UI. Whenever you are unsure how a screen,
dialog, sheet, state, or animation should look — or an icon, asset, or copy string is missing —
**stop and ask the user** for a screenshot of the specific Figma element or for the specific
asset files. No second-guessing, no invented placeholder designs. The UI specifications in this
plan (§6.5, §7.5) plus requirements §5–§6 are the spec; where they run out, yield — do not fill
the gap yourself. This rule applies to every UI-bearing step: the dialogs (Phases 3 and 5), the
Voice Search reminder dialog (Phase 3), the sheet, Settings screens, and menu rows (Phase 4), and
the location management rows (Phase 6).

### 2.13 Xcode project yield rule — never fight the project file

If creating or registering the local Swift package — or **any** pbxproj/scheme edit: package
registration, the scheme `TestableReference`, the four entries for a new app-target file — fails
or you are not confident in the edit, **stop and ask the user to perform that step manually in
Xcode**, giving exact instructions for what to add (file, target, section, and the entry
contents). Do not retry variations against the project file until something parses. A broken
`project.pbxproj` costs far more than the hand-off.

---

## 3. Phase 0 — branch setup (≈10 minutes)

The registry and privacy gates are **already satisfied** (see the top of this document), so
Phase 0 is only branch setup.

```bash
git fetch origin main
git switch -c bartosz/on-site-permissions-1 origin/main
```

Confirm you are **not** branching off `bartosz/on-site-permissions`:

```bash
git log --oneline -1
git merge-base --is-ancestor origin/main HEAD && echo "based on main: OK"
```

Two facts about the starting point, verified 2026-08-27:

- The documentation branch is **5 commits ahead of and 39 commits behind `origin/main`**. That
  does not matter — you branch off `origin/main`, not off it.
- `iOS/LocalPackages/SitePermissions` does not exist, and `SitePermissions` appears in **zero**
  Swift files under `iOS/`. No name collision.

Nothing else happens in Phase 0. Do not create the other five branches yet — each forks off the
previous one **after** that one is complete.
---

## 4. Phase 1 — Foundations: flag, assets, package, model, store, Fire worker

**Branch:** `bartosz/on-site-permissions-1` — **base: `main`**
**Asana:** https://app.asana.com/1/137249556945/task/1217863452475658
**Estimate:** ~3 days, ~1.5k LOC
**Depends on:** nothing

### 4.1 Scope

**Ships:**

- The `sitePermissions` feature flag and its privacy-config subfeature case.
- The two missing icon accessors plus the one genuinely new icon asset.
- The `iOS/LocalPackages/SitePermissions` package — scaffold, pbxproj registration, scheme
  `TestableReference`.
- The permission model: type enum, tri-state decision, per-site record.
- `SitePermissionsStore` — `@MainActor` class, split storage keys, sparse-map `.ask`, snapshot Undo.
- Global per-type defaults.
- `PermissionsFireWorker`, registered and **ungated** (runs with the flag off — deliberate).

**Explicitly out of scope for this phase:**

- No coordinator, no system client (Phase 2).
- No UI of any kind — no dialogs, no sheet, no Settings screens, no menu rows.
- No `TabViewController` changes. No WKUIDelegate routing. No user scripts.
- No pixels. (The store and worker fire no pixels; the worker's wide event is not a pixel.)
- No geolocation anything.

### 4.2 Assumptions in effect

| OQ | Default applied here |
|---|---|
| OQ-7 | Fire exempts fireproofed sites; Fire and Remove All clear **per-site records only** and preserve global defaults. |
| OQ-21 | Host-only key: leading `www.` dropped, punycode for IDN, scheme and port collapsed. |
| OQ-9 | Allow-once grants are never persisted, so the store has no representation for them. |
| OQ-17 | An explicit user-reset `.ask` **is** persisted (it is what keeps the row listed). |

No blocking precondition. The registry task exists; the privacy decisions are ratified
(kick-off 2026-08-28). The privacy ping (OQ-7/OQ-21) is assumed fine and blocks nothing — the
for-the-record ping can still be sent.

### 4.3 Ordered implementation steps

#### Step 1 — Feature flag

**Modify** [`iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/iOSBrowserConfigSubfeature.swift`](iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/iOSBrowserConfigSubfeature.swift)
— add one case before the closing `}` at **line 148**. Follow the neighbours at 143–147: a `///`
Asana link, then the case. Raw values are implicit (no `= "..."` anywhere in this enum).

```swift
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1217880888140745
    case sitePermissions
```

**Modify** [`iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift`](iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift)
— two insertions:

1. The enum case, before the closing `}` at **line 553** (the enum body is 23–553):

```swift
    /// Per-site camera, microphone and location permissions.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1217880888140745
    case sitePermissions
```

2. The `Config` mapping, before the `}` closing the switch at **line 939** (the `private var
   config: Config` switch is 605–940):

```swift
        case .sitePermissions:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.sitePermissions))
```

Nothing else. `Config`'s defaults (**line 592–597**) already give `defaultValue: .disabled` and
`supportsLocalOverriding: true` — do **not** pass either. `FeatureFlagDescribing` is
`CaseIterable`, so the flag appears in the debug menu automatically; the `config` switch is
exhaustive, so forgetting insertion 2 is a compile error.

> **Verify the default is OFF.** `defaultValue: .disabled` + `.remoteReleasable` is what makes the
> flag off for everyone until the subfeature is enabled in privacy config. Do **not** write
> `defaultValue: .enabled` — with `.remoteReleasable` that turns the feature **on** for everyone
> whenever the subfeature is absent from the config.

Do **not** edit `iOS/Core/ios-config.json` — it is a vendored snapshot of the remote privacy
config, not a registration point.

#### Step 2 — Icons

Verified against the catalog at
`SharedPackages/Infrastructure/DesignResourcesKitIcons/Sources/DesignResourcesKitIcons/DesignSystemImages.xcassets`:

| Icon | Status | Action |
|---|---|---|
| `Location-24` / `-Blocked-24` / `-Solid-24` | asset + accessor exist | use `DesignSystemImages.Glyphs.Size24.location` / `.locationBlocked` / `.locationSolid` (`DesignSystemImages+Glyphs.swift:582-584`) |
| `Microphone-24`, `Microphone-Solid-24` | asset + accessor exist | `.microphone` / `.microphoneSolid` (`+Glyphs.swift:591-592`) |
| **`Microphone-Blocked-24`** | **asset exists, accessor missing** | **add** `microphoneBlocked` to `Glyphs.Size24` (a 16px `microphoneBlocked` exists at `+Glyphs.swift:303` — do not confuse them) |
| `Video-Solid-24` | asset + accessor exist | `.videoSolid` (`+Glyphs.swift:659`) |
| **`Video-Blocked-24`** | **asset exists, accessor missing** | **add** `videoBlocked` to `Glyphs.Size24` |
| `Video-24-1` | **does not exist and never did** | requirements.md §7 has a typo — use `Glyphs.Size24.video` (`Video-24`, `+Glyphs.swift:656`) |
| `Info-Recolorable-24` | exists twice | `Glyphs.Size24.infoRecolorable` (`+Glyphs.swift:575`) |
| **`Website-Permissions-Color-24`** | **fully absent** — no asset, no accessor | **create** the imageset under `Color/24px/` + accessor in `DesignSystemImages+Color.swift` (`Color.Size24`) |
| Menu-row icon | — | `Glyphs.Size24.options` (`Options-24`, `+Glyphs.swift:599`). The only options/sliders glyph at 24px; there is no Sliders/Tune/Filter asset at any size. |

Accessor pattern (`+Glyphs.swift:582`):

```swift
            public static var location: DesignSystemImage { .init(resource: .location24) }
```

`.init(resource:)` uses Xcode's generated `ImageResource` symbols, auto-camelCased from the asset
name — so `Microphone-Blocked-24` → `.microphoneBlocked24`. **Adding the accessor is enough for
the two existing assets; no catalog change needed.**

For `Website-Permissions-Color-24`, the repo has a dedicated skill: **`/ddg-drk-add-icon`**. It
handles imageset creation, `Contents.json` variants, and the camelCase accessor in one commit.
Use it if you have the SVG; otherwise create the imageset by hand mirroring
`Color/24px/Settings-Color-24.imageset`. Note that `Color` assets often carry a `-legacy` twin
and a rebrand branch (`+Color.swift:507-517`) — if you only have one artwork, add the plain
accessor without the `AppRebrand.isAppRebranded()` branch. If you do not have the artwork at
all, yield per §2.12: ask the user for the asset files — do not substitute another glyph or
invent a placeholder.

**No `Info.plist` work.** All three usage-description keys already exist:
`NSCameraUsageDescription` (`iOS/DuckDuckGo/Info.plist:169`),
`NSLocationWhenInUseUsageDescription` (`:173`), `NSMicrophoneUsageDescription` (`:175`).
See §11 for a copy observation about the camera string.

**Status-red colour.** iOS has **no** `statusRed` token — `statusRed` exists only on the macOS
`SharedDesignSystemColor` enum, and its values don't match the spec anyway. The one iOS token
that resolves to exactly Light `EB102D` / Dark `FF545A` is **`DesignSystemColor.buttonsDeleteGhostText`**
(`DefaultColorPalette.swift:192` → `alertRedOnLight`/`alertRedOnDark`, aliases at
`Colors/ColorSystem/Alerts.swift:37-38` for `alertRed50 = Color(0xEB102D)` (`:31`) and
`alertRed20 = Color(0xFF545A)` (`:28`)). It falls through unchanged under the rebranded
palette. **Reuse it** rather than adding a semantic case; note the reuse in the project log so a
later rename is findable. Precedent call sites: `iOS/DuckDuckGo/DownloadsList.swift:215`,
`iOS/DuckDuckGo/BookmarkFoldersTableViewController.swift:305`.

#### Step 3 — Package scaffold

**Create** `iOS/LocalPackages/SitePermissions/Package.swift`. Shape precedent:
`iOS/LocalPackages/AppRouting/Package.swift` (single product + single test target). Two
differences from AppRouting: add `defaultLocalization: "en"` (needed for `UserText` in later
phases), and skip AppRouting's dependencies unless you actually need them.

```swift
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SitePermissions",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SitePermissions",
            targets: ["SitePermissions"]
        )
    ],
    dependencies: [
        .package(path: "../../../SharedPackages/Persistence")
    ],
    targets: [
        .target(
            name: "SitePermissions",
            dependencies: [
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(
            name: "SitePermissionsTests",
            dependencies: [
                "SitePermissions"
            ]
        )
    ]
)
```

Dependency paths are `../../../SharedPackages/…` — three levels up from
`iOS/LocalPackages/<Pkg>/`. The `Persistence` package (path and product name both `Persistence`,
`SharedPackages/Persistence/Package.swift:24,30`) is what exports `KeyValueStoring` /
`KeyedStoring`; `iOS/LocalPackages/DataBrokerProtection-iOS/Package.swift:35` uses exactly this
path. Deployment floor is iOS 15, matching the app.

Create the source layout:

```
iOS/LocalPackages/SitePermissions/
├── Package.swift
├── Sources/SitePermissions/
│   ├── Model/
│   └── Store/
└── Tests/SitePermissionsTests/
```

Every new Swift file needs the standard Apache header — copy it verbatim from
`iOS/DuckDuckGo/Fire/FireWorkers/URLCacheFireWorker.swift:1-18`, changing the filename line.

#### Step 4 — pbxproj + scheme registration

The project is **`iOS/DuckDuckGo-iOS.xcodeproj`** (`iOS/DuckDuckGo.xcodeproj` does not exist).

Mirror how `SystemSettingsPiPTutorial` is registered — the simplest single-product iOS local
package. **Six edits**, all in `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj`. Generate fresh
24-hex-character UUIDs; reuse none. Grep `SystemSettingsPiPTutorial` in the pbxproj first — its
six lines (**1486, 4465, 5821, 6836, 12596, 19777**) are your worked example.

> **Two registration patterns exist in this project; pick the majority one.** Most iOS local
> packages — `SetDefaultBrowser`, `SyncUI-iOS`, `SystemSettingsPiPTutorial`, `FeatureFlags-iOS`,
> `VPNiOS`, `Waitlist-iOS`, `DataBrokerProtection-iOS` — are registered with a wrapper
> `PBXFileReference` in the `LocalPackages` group and nothing more. Only `LocalPackages/DuckUI`
> (**pbxproj:13056, 19234**) and `LocalPackages/AppRouting` (**:13061, 19222**) *additionally* carry
> an `XCLocalSwiftPackageReference` plus a `packageReferences` entry. Both work. Follow the
> majority — six edits, no `XCLocalSwiftPackageReference`. The workspace
> (`DuckDuckGo.xcworkspace/contents.xcworkspacedata`) lists only `SharedPackages/*` and the two
> `.xcodeproj` files, so the wrapper file reference is what makes Xcode discover an iOS local
> package.

| # | Section | What to add | Anchor |
|---|---|---|---|
| 1 | `PBXBuildFile` | `<uuidA> /* SitePermissions in Frameworks */ = {isa = PBXBuildFile; productRef = <uuidB> /* SitePermissions */; };` | near line 1486 (`SystemSettingsPiPTutorial in Frameworks`) |
| 2 | `PBXFileReference` | `<uuidC> /* SitePermissions */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = SitePermissions; sourceTree = "<group>"; };` | near line 4465 |
| 3 | `PBXFrameworksBuildPhase` `84E3418F1E2F7EFB00BDBA6F` | `<uuidA> /* SitePermissions in Frameworks */,` | phase opens **line 5806**; `SystemSettingsPiPTutorial` sits at **5821** |
| 4 | `PBXGroup` `31E69A60280F4BAD00478327 /* LocalPackages */` | `<uuidC> /* SitePermissions */,` | group opens **line 6814**; keep it alphabetical (after `SetDefaultBrowser` at 6833) |
| 5 | `packageProductDependencies` of `PBXNativeTarget 84E341911E2F7EFB00BDBA6F /* DuckDuckGo */` | `<uuidB> /* SitePermissions */,` | list opens **line 12572**; `SystemSettingsPiPTutorial` sits at **12596** |
| 6 | `XCSwiftPackageProductDependency` section | a 4-line entry — `<uuidB> /* SitePermissions */ = {isa = XCSwiftPackageProductDependency; productName = SitePermissions; };` | `SystemSettingsPiPTutorial`'s is at **19777-19780**; note it has **no** `package =` key |

**Link into the `DuckDuckGo` app target** (`84E341911E2F7EFB00BDBA6F`, Frameworks phase
`84E3418F1E2F7EFB00BDBA6F` at line 5806) — that is where `TabViewController`, the menus, and
Settings live, and where `SetDefaultBrowserUI` (line 5816) and `SystemSettingsPiPTutorial`
(line 5821) are linked. **Do not** copy AppRouting, which is linked into the `Core` framework
target instead.

Also link it into the **`UnitTests`** target (`84E341A51E2F7EFB00BDBA6F`, block starts
line 12617) only if an app-side test needs to `import SitePermissions` — Phase 1's app-side test
is the Fire worker, which does, so add it: one more `PBXBuildFile`, one more entry in the
UnitTests Frameworks phase, one more entry in its `packageProductDependencies` list (which closes
at **line 12653**).

**Then the scheme** — `iOS/DuckDuckGo-iOS.xcodeproj/xcshareddata/xcschemes/iOS Browser.xcscheme`.
`<Testables>` spans **lines 79–295** with 19 entries. Insert this 10-line block before line 295:

```xml
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "SitePermissionsTests"
               BuildableName = "SitePermissionsTests"
               BlueprintName = "SitePermissionsTests"
               ReferencedContainer = "container:LocalPackages/SitePermissions">
            </BuildableReference>
         </TestableReference>
```

For SPM test targets, `BlueprintIdentifier == BuildableName == BlueprintName == <TestTargetName>`
with no `.xctest` suffix, and `ReferencedContainer = "container:LocalPackages/<PackageDir>"`.
Copy `AppRoutingTests` (lines 265–274) or `FeatureFlagsTests` (285–294) exactly; do **not** copy
`PerformanceTests` (245–254), which is a native target and uses a hex identifier.

**Skipping this step means the tests silently never run.** Two packages already have this bug —
`DataBrokerProtection-iOSTests` and `WaitlistTests` both exist on disk and appear nowhere in the
scheme.

**Do not add the testable to `iOS Browser Alpha.xcscheme`** — it has no `<Testables>` block at
all, and adding one is out of scope. Just remember to pass `--scheme "iOS Browser"` when testing (§2.4).

**If any of these pbxproj or scheme edits fails — or you are not confident it is right — yield
per §2.13:** stop and hand the user exact instructions to perform the step manually in Xcode.

Checkpoint — the package must build and resolve before you write model code:

```bash
cd iOS/LocalPackages/SitePermissions && swift package resolve
```

```bash
xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"
```

#### Step 5 — Permission model

**Create** `Sources/SitePermissions/Model/` — the type enum, the tri-state decision, and the
per-site record.

- **Type:** camera / microphone / location. Raw values **must be byte-identical to macOS's**:
  `"camera"`, `"microphone"`, `"geolocation"`. (Note the mismatch: the user-facing label is
  "Location", the persisted raw value is `"geolocation"`.)
- **Decision:** `ask` / `allow` / `deny`, raw values `"ask"` / `"allow"` / `"deny"` (matching
  macOS's `PersistedPermissionDecision.pixelName` vocabulary).
- **Per-site record:** the sparse map is the whole mechanism. Do **not** invent a record struct
  with tombstones or marker sets.

Do **not** reuse BrowserServicesKit's dashboard DTOs (`AllowedPermission`,
`PermissionAuthorizationState`) — they are presentation types with `.grant` vocabulary. Do **not**
reuse `DomainsProtectionStore` — it is a boolean set and cannot express a tri-state per type.

**Permission-key contract** — implement it once, here, and make it the only way a key is produced:

- Host-only. Drop a leading `www.`. Punycode form for IDN. Scheme and port collapsed.
- The key derives from the **tab's committed main-frame URL**, never from the requesting frame and
  never from a JavaScript-supplied value. (Phase 2 owns the plumbing; Phase 1 owns the
  normalization function and its tests.)
- Internal (`duck://`), `file:`, and error-page origins produce **no key** — return nil and never
  store or match. macOS keys file origins to a synthetic `localhost`; **do not replicate that.**

#### Step 6 — `SitePermissionsStore`

**Create** `Sources/SitePermissions/Store/SitePermissionsStore.swift` — a
**`@MainActor final class`**. No actor (every consumer is already main-actor and `KeyedStoring` is
synchronous, so an actor buys `await`/Sendable ceremony and nothing else). **No store protocol** —
inject the `KeyedStoring` instead.

Follow the repo's mandatory storage pattern (`.cursor/rules/user-defaults-storage.mdc`, and the
in-code doc at `SharedPackages/Persistence/Sources/Persistence/KeyValueStoring.swift:19-113`).
The live pattern is a **two-declaration** pair — copy
`iOS/DuckDuckGo/AppLifecycle/AfterInactivitySettingStorage.swift:24-37` or
`iOS/DuckDuckGo/SyncPromoManager.swift:38-46`:

```swift
enum SitePermissionsStorageKeyNames: String, StorageKeyDescribing {
    case perSitePermissions = "site-permissions-per-site"
    case globalDefaults = "site-permissions-global-defaults"
}

struct SitePermissionsStoringKeys: StoringKeys {
    let perSitePermissions = StorageKey<[String: [String: String]]>(SitePermissionsStorageKeyNames.perSitePermissions)
    let globalDefaults = StorageKey<[String: String]>(SitePermissionsStorageKeyNames.globalDefaults)
}
```

The two protocols are `StorageKeyDescribing` (`KeyValueStoring.swift:173`) and `StoringKeys`
(`:165`, which requires only `init()` — synthesized for a struct whose stored properties all have
defaults). The `StorageKey` initializer you call is the public one at `:154-162`, which takes
`any StorageKeyDescribing`.

> **`.cursor/rules/user-defaults-storage.mdc` is stale on one point.** Its examples show dotted
> kebab keys like `"new-tab-page.omnibar.is-visible"`. `StorageKey.init` now **asserts** on dots
> (`KeyValueStoring.swift:126-144`, `#if DEBUG` only — so a dotted key passes CI release builds and
> trips every debug run). **Use kebab-case with no dots**, as above. Follow the rule file's
> seven numbered requirements; ignore its dotted key names.

**Two storage keys, deliberately.** The per-site map and the global defaults are separate so Fire
and "Remove All" can clear sites while **preserving global defaults**. This split is the whole
reason FR-8's "globals survive Fire" works — do not merge them.

**Wire format:** store the nested `[String: [String: String]]` map **directly**. `encodeValue`
takes the plist-native branch for it (`KeyValueStoring.swift:329-332`:
`PropertyListSerialization.propertyList(value, isValidFor: .binary)`), so it round-trips as a real
plist collection. **Do not wrap it in a Codable DTO** — the Codable branch (`:335-337`) would
turn it into opaque JSON `Data`. No versioned DTO, no schema field.

**Injection.** The store takes `any KeyedStoring<SitePermissionsStoringKeys>`. The package cannot
reach `UserDefaults.app` (that lives app-side at `iOS/Core/UserDefaultsExtension.swift:23`), so
the **app** passes `UserDefaults.app.keyedStoring()` at the construction site. Give the parameter
no default inside the package.

**Semantics — the sparse map is the mechanism:**

| State | Representation |
|---|---|
| Never chosen | **no entry** |
| Explicit Always Allow | `"allow"` |
| Explicit Never Allow | `"deny"` |
| User reset the row in the manager | `"ask"` — persisted **only** in this case; keeps the row listed (OQ-17) |
| Allow Once granted | **nothing persisted, ever** (OQ-9) |
| Merely prompted | **nothing persisted, ever** (privacy §4.3 — no passive records) |

`Remove Permissions` deletes the record entirely.

**Undo — snapshot semantics.** Undo restores **exactly** the deleted record(s), and **only if the
affected site still has no newer record** made while the toast was visible. Ephemeral grants are
never restored. A plain captured snapshot value is the whole implementation — no tombstones, no
second list, no journal.

**No at-rest encryption** — consistent with fireproofing and text zoom. Noted for privacy review.

**Global defaults** are per-type and **binary**: `ask` (default) or `deny`. There is **no global
Always Allow** — that is a hard privacy requirement (requirements §4.3). Do not add a third case
to the global picker's option set even though the per-site decision enum has three.

#### Step 7 — `PermissionsFireWorker`

**Create** `iOS/DuckDuckGo/Fire/FireWorkers/PermissionsFireWorker.swift` — app-side, not in the
package.

> **This folder is NOT a buildable folder — you must edit the pbxproj.** `project-structure.mdc`
> says to use buildable folders by default and to *determine how the destination is represented*
> before adding a file. Determined: `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` contains **zero**
> `PBXFileSystemSynchronizedRootGroup` entries, and `FireWorkers` is a plain `PBXGroup`
> (**pbxproj:7848-7865**) with all eleven worker files listed individually. **A new file dropped in
> the folder will compile nowhere and fail silently** — the worker just never runs.
>
> Four entries are required. `URLCacheFireWorker.swift` is the worked example:
>
> | Section | Its line | What to add |
> |---|---|---|
> | `PBXBuildFile` | **753** | `<uuidA> /* PermissionsFireWorker.swift in Sources */ = {isa = PBXBuildFile; fileRef = <uuidB> /* PermissionsFireWorker.swift */; };` |
> | `PBXFileReference` | **3638** | `<uuidB> /* PermissionsFireWorker.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PermissionsFireWorker.swift; sourceTree = "<group>"; };` |
> | `FireWorkers` `PBXGroup` children | **7860** | `<uuidB> /* PermissionsFireWorker.swift */,` (keep alphabetical) |
> | `DuckDuckGo` target `PBXSourcesBuildPhase` | **13726** | `<uuidA> /* PermissionsFireWorker.swift in Sources */,` |
>
> Same rule for **every** new app-side file in this project, in any phase. Grep the neighbouring
> file's name in the pbxproj first and mirror its entries. §2.13 applies here too — if the
> pbxproj edit fails or you are unsure, stop and hand it to the user.

Conform to `FireExecutorWorker`
(`iOS/DuckDuckGo/Fire/FireWorkers/FireExecutorWorker.swift:20-24`) — exactly three methods, all
`async`, each individually `@MainActor`, no throws, no return values:

```swift
protocol FireExecutorWorker {
    @MainActor func burnNormalModeData() async
    @MainActor func burnFireModeData() async
    @MainActor func burnTabData(tabViewModel: TabViewModel, domains: [String]) async
}
```

Template: `URLCacheFireWorker.swift` (the smallest, whole-file). Closest structural analogue — one injected dependency **plus** `fireproofing` — is
`TextZoomFireWorker.swift:22-61`: a `struct` holding `fireproofing: Fireproofing`, using it in
`burnNormalModeData` (`:39`) and `burnTabData` (`:56`), with `import Core` (`:20`) for
`Fireproofing`. Write yours as a `struct` too.

> **Copy its shape, not its fireproof lookup.** At `:39` and `:56` it reads
> `fireproofing.allowedDomains` — the raw array. **Do not do that here** (see the exemption rule
> below): use `isAllowed(fireproofDomain:)`, which is the only call that applies eTLD+1
> normalization *and* the implicit DuckDuckGo/Duck.ai exemptions.

Behavior:

- **`burnNormalModeData()`** — clear the **per-site map only**; leave the global-defaults key
  untouched. Exclude sites where `fireproofing.isAllowed(fireproofDomain:)` matches.
- **`burnFireModeData()`** — an explicit no-op with a one-line comment saying why (single store).
  Match the existing no-op style in `URLCacheFireWorker.swift`.
- **`burnTabData(tabViewModel:domains:)`** — clear the given domains, same fireproof exemption.
- **The worker runs even when the flag is off.** Do not gate it. A rollback must not strand data.

**Fireproof exemption — use `isAllowed(fireproofDomain:)` and nothing else.**
`iOS/Core/Fireproofing.swift:118-121`:

```swift
    public func isAllowed(fireproofDomain domain: String) -> Bool {
        guard let normalized = tld.eTLDplus1(domain) else { return false }
        return allowedDomainsIncludingDuckDuckGo.contains(normalized)
    }
```

It normalizes to eTLD+1 through the injected `TLD` (`:69,73`) **and** applies the implicit
DuckDuckGo / Duck.ai exemptions (`:85-90`). **Never compare raw `allowedDomains`** — you would
lose both. eTLD+1 is used **only** here, at the fireproof boundary; the storage key stays host-only.

**Wide-event instrumentation.** Workers fire **wide events, never pixels** (pixels are fired
centrally in `FireExecutor.burnData`). Pattern, three lines —
`PrivacyStatsFireWorker.swift:31-36`:

```swift
        dataClearingWideEventService?.start(.clearPrivacyStats)
        let result = await privacyStats?.clearPrivacyStats() ?? .success(())
        dataClearingWideEventService?.update(.clearPrivacyStats, result: result)
```

**A `clearPermissions` action already exists** — `.clearPermissions = "clear_permissions"` at
`SharedPackages/BrowserServicesKit/Sources/BrowserServicesKit/DataClearing/DataClearingWideEventData.swift:355`,
with backing fields at `:168-170` and keypath mappings at `:389,425,461`. It sits under a
`// macOS-only actions` comment (`:354`) and is currently used only by macOS
(`macOS/DuckDuckGo/Fire/Model/Fire.swift:480,482,619,621`). **Reuse it as-is** and update that
stale comment. Do not add a new action case.

If you change anything in `DataClearingWideEventData.swift`, run:

```bash
cd iOS && npm run check-wide-events
```

**Register the worker** — `iOS/DuckDuckGo/Fire/FireExecutor.swift`, the `fireWorkers` array
literal at **lines 206–229** (the property is declared at `:126`). Add one element in the same
style; every worker receives `dataClearingWideEventService: dataClearingWideEventService` (built
at `:201`). `fireproofing` is already an init parameter (`:157`) — no `FireExecutor` signature
change is needed:

```swift
            PermissionsFireWorker(store: /* the SitePermissionsStore */,
                                  fireproofing: fireproofing,
                                  dataClearingWideEventService: dataClearingWideEventService),
```

Workers run concurrently in a task group (`FireExecutor.swift:493-500`). Everything is
`@MainActor`, so the MainActor store serializes naturally — no locking. `.all` scope runs
`burnFireModeData` and `burnNormalModeData` via `async let`
(`FireExecutorWorker.swift:45-51`), which is why the fire-mode no-op must be a genuine no-op and
not a second clear. Auto-clear comes free through `FireRequest`.

### 4.4 Tests

**Package tests** — `Tests/SitePermissionsTests/`:

| Area | Cases |
|---|---|
| Key normalization | `www.` dropped; punycode IDN; scheme collapsed (`http` and `https` yield one key); port collapsed; subdomains stay distinct; `duck://`, `file:`, and error-page origins return **nil** |
| Plist round-trip | write → read back through a fresh store instance; assert the raw stored object is a **dictionary, not `Data`** (this is what catches an accidental Codable DTO) |
| Split-key isolation | clearing the per-site map leaves the global-defaults key intact, and vice versa |
| Sparse map | no entry ≠ `"ask"` entry; prompting writes nothing; only a user reset writes `"ask"` |
| Global defaults | default is `ask`; only `ask`/`deny` are representable |
| Undo | restores the exact deleted record; **refuses** to restore when a newer record exists for that site; never restores an ephemeral grant |

Use `MockKeyValueStore` (= `InMemoryKeyValueStore`, `@_spi(Testing)`, at
`SharedPackages/Persistence/Sources/Persistence/TestingSupport/InMemoryKeyValueStore.swift:24,73`).
Setup pattern — `iOS/DuckDuckGoTests/IdleReturnEligibilityManagerTests.swift:43-44`:

```swift
        let storage: any KeyedStoring<SitePermissionsStoringKeys> = MockKeyValueStore().keyedStoring()
```

**App-side worker tests** — add to `iOS/DuckDuckGoTests/Fire/FireExecutorTests.swift` (974 lines;
`makeFireExecutor` at `:190-223`, `makeFireRequest` at `:225-232`). No per-worker test file exists
today; the established pattern is to drive the whole `FireExecutor` and observe through a mocked
dependency. Model your tests on `:618-639`.

| Case | Assertion |
|---|---|
| Fireproof exemption | a fireproofed site's record survives `burnNormalModeData`; a non-fireproofed one does not |
| Subdomain exemption | fireproofing `amazon.com` protects a record stored for `mail.amazon.com` |
| Implicit exemption | `duckduckgo.com` / `duck.ai` records survive |
| Globals preserved | after a burn, the global-defaults key is byte-identical |
| Fire-mode no-op | `burnFireModeData` changes nothing |
| Burn while flag off | records are cleared with `sitePermissions` disabled |
| Tab scope | `burnTabData` clears only the passed domains, with the same exemption |

> **Mock gotcha.** `MockFireproofing.isAllowed(fireproofDomain:)`
> (`iOS/SharedTestUtils/Mocks/Core/Web/MockFireproofing.swift:51`) returns
> `isAllowedFireproofDomainHandler?(domain) ?? false` — **no eTLD+1 normalization and no
> DuckDuckGo/Duck.ai exemption.** So `MockFireproofing(domains: ["amazon.com"])` alone will **not**
> exercise the subdomain or implicit-exemption cases. Either set
> `isAllowedFireproofDomainHandler` explicitly, or use a real `UserDefaultsFireproofing` backed by
> a `MockKeyValueStore`. A test that passes only because the mock returns `false` for everything
> proves nothing.

### 4.5 Verification commands

```bash
xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"
```

```bash
xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args -only-testing:SitePermissionsTests -only-testing:UnitTests/FireExecutorTests
```

```bash
cd iOS/LocalPackages/SitePermissions && swift package resolve
```

**Prove the scheme wiring actually took.** The test run's output must name `SitePermissionsTests`
and report a non-zero test count. If it reports zero, the `TestableReference` is wrong or you
tested against `iOS Browser Alpha`. Do not proceed to Phase 2 until you have seen those tests run.

### 4.6 Flag-off safety checklist

- [ ] `sitePermissions` resolves to **disabled** by default — `Config(source: .remoteReleasable(...))`
      with no `defaultValue:` override.
- [ ] No `TabViewController` change, no WKUIDelegate change, no user-script registration. Both
      legacy capture matrices are untouched, byte for byte.
- [ ] No menu row, no Settings row, no UI of any kind.
- [ ] **`PermissionsFireWorker` is registered and ungated** — this is the deliberate exception.
      Confirm it clears data with the flag off, by test.
- [ ] The store is constructed but nothing writes to it yet — the flag-off app persists nothing.
- [ ] `swift package resolve` clean; scheme testable present and observed running.

### 4.7 Exit criteria

- [ ] Build green.
- [ ] `SitePermissionsTests` and `FireExecutorTests` green, and `SitePermissionsTests` **observed
      running** (non-zero count).
- [ ] Review loop completed (§2.5) — findings applied or logged.
- [ ] History clean, fixups squashed, co-author trailer on every commit.
- [ ] `project_log.md` created on the documentation branch with the Phase 1 entry.
- [ ] `pr1-description.md` written and committed on the documentation branch.
---

## 5. Phase 2 — Coordinator + system client

**Branch:** `bartosz/on-site-permissions-2` — **base: `bartosz/on-site-permissions-1`**
**Asana:** https://app.asana.com/1/137249556945/task/1217863452475659
**Estimate:** ~2.5 days, ~1.5k LOC
**Depends on:** Phase 1

### 5.1 Scope

**Ships:**

- `SitePermissionsCoordinator` — one concrete `@MainActor` class per tab: the precedence table,
  allow-once windows, its own prompt FIFO, navigation-generation validation.
- The system client — AV authorization status/request plus a **single shared `CLLocationManager`**
  driving both authorization and position delivery; `restricted` / `unavailable` states; refresh
  on app activation.
- **Regression tests freezing both legacy capture matrices verbatim** — written *before* Phase 3
  touches routing.

**Explicitly out of scope for this phase:**

- No `TabViewController` wiring. The coordinator is built and unit-tested but **not yet owned by a
  tab** and **not yet reachable from any delegate method**. Phase 3 wires it.
- No dialogs, no UI, no pixels.
- No geolocation shim (Phase 5). The system client's location half is built and tested here, but
  nothing calls it from the web yet.

### 5.2 Assumptions in effect

| OQ | Default applied here |
|---|---|
| OQ-8 | Stored per-site Always Allow overrides global Never. Global Never blocks *asking* only. Ratified at kick-off. |
| OQ-9 | Allow Once is in-memory and page-scoped; no TTL; never persisted or restored; backgrounding alone does not end a grant. Ratified at kick-off (provisional — validate by feel in an early build). |
| OQ-10 | Fire-mode tabs read stored decisions and globals, **never write**. Ratified at kick-off. |
| OQ-15 | Deferred at kick-off: v1 gives `restricted` / `unavailable` the standard denied handling. The client still models them as distinct states (cheap, and the later restricted-experience work needs them); Phase 2 represents them faithfully. |

### 5.3 Ordered implementation steps

#### Step 1 — Freeze the legacy matrices first

Do this **before** writing the coordinator, so Phase 3 cannot silently change shipped behavior.

Add tests to `iOS/DuckDuckGoTests/` covering both call sites exactly as they behave today.

**Call site 1 — `iOS/DuckDuckGo/TabViewController.swift:3938-3951`** (verified verbatim; the
enclosing `extension TabViewController: WKUIDelegate` opens at `:3926`):

```swift
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        guard origin.host.isDuckAIHost,
              type == .microphone || type == .cameraAndMicrophone else {
            decisionHandler(.prompt)
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        decisionHandler(status == .authorized ? .grant : .deny)
    }
```

| Host | Type | `.audio` status | Decision |
|---|---|---|---|
| any non-duck.ai | any (incl. `.camera`) | any | `.prompt` |
| duck.ai | `.camera` | any | `.prompt` |
| duck.ai | `.microphone` or `.cameraAndMicrophone` | `.authorized` | `.grant` |
| duck.ai | `.microphone` or `.cameraAndMicrophone` | `.notDetermined` / `.denied` / `.restricted` | `.deny` |

**Call site 2 — `SharedPackages/AIChat/Sources/AIChat/iOS/AIChatWebViewController.swift:267-280`.**
Identical logic, **one difference: the fallthrough is `.deny`, not `.prompt`.**

| Host | Type | `.audio` status | Decision |
|---|---|---|---|
| any non-duck.ai | any | any | `.deny` |
| duck.ai | `.camera` | any | `.deny` |
| duck.ai | `.microphone` or `.cameraAndMicrophone` | `.authorized` | `.grant` |
| duck.ai | `.microphone` or `.cameraAndMicrophone` | any other | `.deny` |

Two things the tests must cover that are easy to miss:

1. **Camera-only on duck.ai** falls through in both files. On `TabViewController` that means
   `.prompt`; on `AIChatWebViewController` it means `.deny`.
2. **`.cameraAndMicrophone` consults `.audio` only.** There is **no** `.video` status check. So
   audio-authorized + video-denied currently yields `.grant`. Freeze that as-is — it is shipped
   behavior, not a bug to fix in this project.

The duck.ai gate is `isDuckAIHost` —
`SharedPackages/AIChat/Sources/AIChat/Shared/URL+Extension.swift:176-181`:

```swift
    public var isDuckAIHost: Bool {
        self == URL.duckAIHost || self == URL.duckDuckGoHost || hasSuffix(".\(URL.duckDuckGoHost)")
    }
```

**It is host-based, not tab-based** — a plain SERP page in an ordinary tab matches it. That is
why the Duck.ai exception has to be evaluated on host, and why a duckduckgo.com SERP location
request needs its own dialog variant (FR-1) rather than falling into the exception.

**`AIChatWebViewController` is never modified by this project, in any phase.** Its matrix test is
a pure regression net.

#### Step 2 — System client

**Create** `Sources/SitePermissions/System/` — one small injected client. Not a service layer, not
a protocol-per-permission.

- **Camera / microphone:** `AVCaptureDevice.authorizationStatus(for:)` and
  `requestAccess(for:)`, evaluated **separately for `.video` and `.audio`**.
- **Location:** a **single shared `CLLocationManager`** used for both authorization and position
  delivery. Two managers can observe divergent state — do not create a second one.
- **States:** `notDetermined` / `authorized` / `denied` / **`restricted`** / **`unavailable`**.
  Keep the last two distinct from `denied` in the model — it is cheap, and the designer will demo
  the real restricted experience later. v1 UX gives them the standard denied handling; there is
  no dedicated restricted-state UI anywhere in the phases (OQ-15, deferred at kick-off).
- **Refresh on app activation** — OS state can change while the app is backgrounded, and FR-5's
  invariant depends on re-reading it.
- **Recovery deep link:** `UIApplication.openSettingsURLString`.

**No `Info.plist` work.** All three usage-description strings already exist
(`iOS/DuckDuckGo/Info.plist:169-176`). See §10 for a copy observation on the camera one.

**This is greenfield — verified.** There is no `CLLocationManager`, no `import CoreLocation`, and
no `requestWhenInUseAuthorization` anywhere in `iOS/` app code (the only hits are inside a fenced
code sample in `iOS/styleguide/STYLEGUIDE.md:687-697`). Deployment floor is iOS 15, and
`requestMediaCapturePermissionFor` plus the KVO-compliant `cameraCaptureState` /
`microphoneCaptureState` are all iOS 15 APIs — **no availability fallbacks needed.**

**Combined camera+microphone:** one WebKit decision spans **two** site decisions and **two** OS
decisions. Grant only when **all** allow; any partial denial → deny plus recovery. **Evaluate each
OS permission separately when classifying a combined denial.** Android checks only the first and
misclassifies camera-only permanent denials — do not copy that.

#### Step 3 — `SitePermissionsCoordinator`

**Create** `Sources/SitePermissions/Coordinator/SitePermissionsCoordinator.swift` — one
**concrete `@MainActor` class**, one instance per tab, owned by `TabViewController` (wired in
Phase 3). No coordinator protocol, no separate decision engine, no per-permission subcoordinators.
No app-type references — the package must not import anything app-side.

**Precedence, in order** (requirements FR-3):

1. **duck.ai exception** → bypass this model entirely, in **both** flag states.
2. **Stored per-site Never** → decline, no prompt.
3. **Stored per-site Allow** → grant **if the OS allows it**; if the OS denies, decline and
   surface recovery (Phase 3). **Applies even while the global default is Never.**
4. **Active allow-once grant** → grant, no re-prompt.
5. **Global default = Never** → silently decline. **No UI at all.**
6. Otherwise → prompt.

Three clarifications that are easy to get wrong:

- An explicit `.ask` entry is **not a decision at request time.** It falls through to steps 4–6.
  It affects Settings listing only.
- A one-time **Deny** suppresses re-asks **for the current page**. A completed one-time **Allow**
  may prompt again after capture ends (macOS model).
- **Combined stored state:** any deny wins; all-allow grants; a partial allow+ask prompts.

**Allow Once lifecycle (OQ-9, macOS model).** In-memory and page-scoped. It ends on:

- reload;
- any **non-same-document** navigation;
- tab close;
- web-content-process replacement;
- app termination.

It does **not** end on a same-document / SPA history update, and backgrounding alone does not
end it. It is **never** persisted and **never** restored — explicitly not Android's 24-hour TTL.
A restored tab starts with no grants. (Ratified at kick-off as provisional — the page-scoped
feel is to be validated in an early build.)

**Own prompt FIFO.** Do **not** route permission prompts through the existing `WebJSAlert` path.
That path **declines** rather than queues: `canDisplayJavaScriptAlert`
(`TabViewController.swift:536-540`) returns false when any view controller is presented, when the
tab isn't the presented one, or when `jsAlertView.isShown`, and each of the three JS panel methods
then calls its completion handler immediately with the negative answer (`:3989-4007`, `:4009-4027`,
`:4029-4049`). A declined permission request is a bug, not a fallback. Permission prompts get their
own small FIFO; only user-facing requests enter it.

**Navigation generation.** Before persisting or delivering **any** late AV or CoreLocation result,
re-verify that all five still match: tab, top-level key, requesting frame, web-content process,
and navigation generation. A stale callback must be dropped, not applied.

**Fire-mode tabs (OQ-10).** Read stored decisions and global defaults; **never write.** Grants made
in a fire-mode tab are memory-only. Put the read/write asymmetry in the coordinator, not at every
call site.

### 5.4 Tests

`Tests/SitePermissionsTests/` — this phase is where the behavior contract gets encoded. It is the
most test-dense phase relative to its size.

| Area | Cases |
|---|---|
| Precedence table | every row of FR-3, in order; stored Allow keeps working under global Never; global Never blocks new prompts; duck.ai bypasses everything; explicit `.ask` falls through; page-scoped one-time Deny suppression; one-time Allow may re-prompt |
| Combined matrices | deny-wins; all-allow grants; partial allow+ask prompts; each OS permission classified **separately** |
| Allow Once lifecycle | reload, same-document navigation (**survives**), cross-site navigation, tab close, process death, app termination, restored tab — **no grant survives except same-document** |
| FIFO | two concurrent requests both get answered in order; **neither is declined** |
| Navigation generation | a late callback arriving after navigation is dropped and persists nothing |
| Fire-mode tabs | stored decisions and globals are read; **nothing is ever written**; grants are memory-only |
| System client | all five states represented; `restricted`/`unavailable` never collapse into `denied` in the model (v1 UX maps them to the standard denied handling — OQ-15); activation refresh re-reads |
| **Legacy matrices (frozen)** | both call sites × {ordinary site, duck.ai} × {mic, camera-only, camera+mic} × all `.audio` states, **including audio-authorized/video-denied** |

**No snapshot tests in v1.** `SKIP_SNAPSHOT_TESTS=1` makes image assertions pass silently both
locally *and* in CI, so a snapshot test here is worse than no test. Write semantic and view-model
tests instead. This holds for every phase.

### 5.5 Verification commands

```bash
xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"
```

```bash
xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args -only-testing:SitePermissionsTests -only-testing:UnitTests
```

### 5.6 Flag-off safety checklist

- [ ] Zero changes to `TabViewController`'s WKUIDelegate extension (`:3926-4051`). Diff it to confirm.
- [ ] Zero changes to `AIChatWebViewController`.
- [ ] The coordinator and system client are **unreachable** from app code — nothing constructs them
      in a production path yet.
- [ ] No user-script registration, no menu row, no Settings row.
- [ ] Legacy matrix tests pass **against unmodified production code** — if they needed a production
      change to pass, you changed shipped behavior.

### 5.7 Exit criteria

- [ ] Build green; `SitePermissionsTests` + `UnitTests` green.
- [ ] Both legacy matrices frozen by passing tests, camera-only and audio-auth/video-denied included.
- [ ] Review loop completed; findings applied or logged.
- [ ] History clean; `project_log.md` and `pr2-description.md` on the documentation branch.
---

## 6. Phase 3 — Camera/mic flow: dialogs, routing, recovery, voice search prompt, pixels

**Branch:** `bartosz/on-site-permissions-3` — **base: `bartosz/on-site-permissions-2`**
**Asana:** https://app.asana.com/1/137249556945/task/1217863452475660
**Estimate:** ~4.5 days, ~1.8k LOC
**Depends on:** Phase 2

This is the first phase where a user can see the feature. It is also the first phase that touches
shipped behavior, so the flag-off checklist matters more here than anywhere else.

### 6.1 Scope

**Ships:**

- The 3-option dialog component — camera, microphone, and the **combined** camera+microphone
  variant — presented through the coordinator's own FIFO.
- `TabViewController` routing behind the flag: the legacy matrix runs **verbatim** when off; the
  Duck.ai branch is preserved in **both** states; `AIChatWebViewController` is untouched.
- Recovery: the **Case A** toast and the **Case B** reminder dialog.
- In-use tracking via KVO on `cameraCaptureState` / `microphoneCaptureState`.
- The redesigned Voice Search denied-permission dialog — `NoMicPermissionAlert` restyled behind
  the flag (in scope per DRI decision 2026-08-28).
- The flow pixels from the DRI-approved set (2026-08-28): dialog impression and click, OS prompt
  result, reminder-dialog interactions, system-settings taps, and the Voice Search prompt events.

**Explicitly out of scope for this phase:**

- No menu row, no bottom sheet, no Settings screens (Phase 4).
- No location anything (Phase 5) — but see §6.5 for the location copy, so the dialog component is
  designed to take it without restructuring.
- No Remove/Undo, no toasts other than Case A.
- No `PermissionStatus` / Permissions API work.
- No grant animation — **cut from v1** (DRI decision 2026-08-28).

### 6.2 Assumptions in effect

| OQ | Default applied here |
|---|---|
| **OQ-2** | **One combined camera+microphone dialog.** WebKit's single decision handler makes sequential independently-answered dialogs impossible. Sites are assumed able to request camera-only or microphone-only (`WKMediaCaptureType` verification assumed yes). Combined copy default adopted (DRI 2026-08-28): title `“<domain>” website wants to access your camera and microphone`, the standard three buttons, no body — marked for later copy review. |
| **OQ-4** | Figma copy verbatim per requirements §5–§6; prefer the multi-permission-scaling phrasing; minimal sensible strings for the still-missing cases. **Mark every new string for copy review; do not wait for it.** (Defaults adopted 2026-08-28; finalize in copy review.) |
| OQ-1 | The OS prompt is **never** shown without the site dialog first (ratified at kick-off). After a site-dialog allow: OS prompt when `notDetermined`; the designed reminder dialog when already `denied`. |
| OQ-5 | The site allow commits at choice time, so the menu entry becomes eligible immediately and the sheet would open in its reminder state. (The menu row itself lands in Phase 4.) |
| OQ-6 | Moot — the grant animation was **cut from v1** (DRI decision 2026-08-28). No animation ships, on grant or denial. |
| OQ-13 | The site decision commits at choice time; an OS denial **never** rewrites it. Ratified at kick-off (provisional) — copies macOS. |
| OQ-15 | Deferred at kick-off: `restricted` / `unavailable` get the **standard denied handling** — no dedicated restricted-state UI in v1. The states stay distinct in the system client. |
| OQ-19 | `.muted` is a distinct **paused** state — allowed, **not** shown as in-use (no red); the VoiceOver label reflects it (resolved at kick-off). |

### 6.3 Ordered implementation steps

#### Step 0 — What to reuse (read before writing any view)

There is **no reusable centered-modal container** in this codebase. Verified: `SharedPackages/UIComponents`
has 23 files and none is an Alert/Dialog/Modal; `iOS/LocalPackages/DuckUI` is button styles and
typography only; every other in-app prompt is a **bottom** sheet, not a centered modal. So the
container is genuinely new — but almost everything inside it already exists.

| Need | Reuse | Anchor |
|---|---|---|
| Dim + blur + centered card | copy the structure and constants from `JSAlertView` | `iOS/DuckDuckGo/JSAlertView.swift:236-238` (dim: `UIColor(white: 0, alpha: 0.2)`), `:252-254` (`UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))`), `:40-47` (card width 270, corner radius 16, button height 44, button corner radius 22) |
| Equally-weighted buttons | DuckUI button styles | `iOS/LocalPackages/DuckUI/Sources/DuckUI/Button.swift` |
| Title / body typography + spacing | read as a **visual reference** only | `iOS/DuckDuckGo/AutofillViews.swift:72` (`Headline`, `.daxTitle3`, centered), `:86` (`Description`, `.daxFootnoteRegular`, `textSecondary`, centered) |
| DuckDuckGo logo, 24px | `DesignSystemImages.Color.Size24.duckDuckGo` | `DesignSystemImages+Color.swift:420` |
| System-Settings deep link | `NoMicPermissionAlert` | `iOS/DuckDuckGo/NoMicPermissionAlert.swift:25-38` |

> **`AutofillViews` is app-side** (`iOS/DuckDuckGo/AutofillViews.swift`) and the dialog lives in the
> package, so you **cannot import it.** Read it for spacing and type scale, then build the three or
> four small pieces you need. Do not add an app dependency to the package to get them; do not move
> `AutofillViews` into a shared package for this. A title, an optional body, and three buttons in a
> `VStack` is a small amount of code — the reuse that matters here is the **chrome constants** and
> the **type scale**, not the view structs.
>
> The package may depend on `DesignResourcesKit`, `DesignResourcesKitIcons`, `SharedPackages/UIComponents`,
> and `iOS/LocalPackages/DuckUI`. It must **never** depend on the app target.

`iOS/DuckDuckGo/NoMicPermissionAlert.swift` is currently the **only** permission-named file in the
entire iOS target — a `UIAlertController` that deep-links to system settings for the voice-search
mic flow. It is the deep-link precedent — and, per the DRI decision (2026-08-28), it is now also
**in scope**: Step 5 restyles it behind the flag. With the flag off it must show **unchanged** —
that is how "no regressions to voice search" (requirements §8) is honored.

#### Step 1 — The dialog component

**Create** `Sources/SitePermissions/UI/` — a SwiftUI dialog plus its view model, in the package.
The app presents it; the package owns the structure and copy. Actions surface as **closures** so
the app can react (`ActionMessageView` is app-only and must not be referenced from the package).

If the design review later decides a custom icon is not essential, `UIAlertController(preferredStyle: .alert)`
with three actions gets the whole dialog — vertical stacking at 3+ actions, glass, dim, VoiceOver,
Dynamic Type, RTL — for free (`iOS/DuckDuckGo/UIAlertControllerExtension.swift:23`;
two-action call shape at `iOS/DuckDuckGo/AlertPlaygroundView.swift:56-64`, `showUIAlert()` — add a
third `addAction` for our case). The icon is the
only reason to hand-build. Note that trade-off in the PR description so the DRI can take the free
version if the icon turns out to be optional.

Presentation goes through **the coordinator's own FIFO**, never through `WebJSAlert` — see §5.3
Step 3 for why (that path declines rather than queues).

**Create** `Sources/SitePermissions/Copy/UserText.swift`. Structure — copy
`iOS/LocalPackages/SetDefaultBrowser/Sources/SetDefaultBrowserUI/Copy/UserText.swift`:
an **internal** `enum UserText` with nested per-screen `enum` namespaces and
`static let` entries of the form

```swift
        static let title = NSLocalizedString("sitePermissions.<screen>.<element>",
                                            bundle: Bundle.module,
                                            value: "…",
                                            comment: "…")
```

Keys are dotted lowercase prefixed with the feature name (dots are fine in **localization** keys —
the no-dots rule applies only to `StorageKey`). `defaultLocalization: "en"` is already in
`Package.swift` from Phase 1; `.lproj` resources are picked up implicitly by SPM and need **no**
`resources:` declaration (`SetDefaultBrowser`'s UI target declares none).

Strings that need a runtime domain use a `static func` with `String(format:)` — precedent
`iOS/LocalPackages/SyncUI-iOS/Sources/SyncUI-iOS/Views/Internal/UserText.swift:39-42`.

#### Step 2 — Route the WKUIDelegate method

**Modify** `iOS/DuckDuckGo/TabViewController.swift:3938-3951`. The new shape, in order:

1. **Duck.ai check first, unchanged.** `origin.host.isDuckAIHost` plus the
   `.microphone` / `.cameraAndMicrophone` type test, then the `.audio`-only status check, then
   `.grant`/`.deny`. **Byte-for-byte the current logic.** This branch runs identically whether the
   flag is on or off — it is an explicit exception to the whole model.
2. **Then the flag check.** Off → run the rest of today's matrix verbatim, i.e. `decisionHandler(.prompt)`.
3. On → hand off to the tab's `SitePermissionsCoordinator`.

`featureFlagger` is already a stored property on `TabViewController` (`:284`), injected via `init`
(`:767`) and `loadFromStoryboard` (`:569`), with `import FeatureFlags_iOS` at `:56`. The call shape
used throughout the file is `featureFlagger.isFeatureOn(.sitePermissions)` — e.g. `:4079`, `:2632`,
`:4106`. There is **no** feature-flag check anywhere in the WKUIDelegate extension today
(`:3926-4051`); yours will be the first.

**Own the coordinator from `TabViewController`** — one instance per tab, created alongside the
tab's other per-tab collaborators.

**Do not touch `SharedPackages/AIChat/Sources/AIChat/iOS/AIChatWebViewController.swift:267-280`.**
Not in this phase, not in any phase. Its regression test from Phase 2 must keep passing untouched.

#### Step 3 — Recovery

**Case A — the user allows the site, then denies the OS prompt.** Decline the
triggering request. Show the toast (no action button). The sheet gains the reminder state (visible
from Phase 4 on).

**Case B — the user allows a site's permission but the OS permission was already `denied`.** Show
the reminder dialog. `Change Permissions` deep-links via `UIApplication.openSettingsURLString`.

**`restricted` / `unavailable`:** no dedicated handling in v1 (OQ-15, deferred at kick-off) —
apply the **standard denied handling** above, even though System Settings may not be able to fix
these states. Keep the states distinct in the system client (Phase 2 already models them; that
is cheap); the designer will demo the real restricted experience later, and any special-cased UI
lands then.

**Our UI can never grant an OS permission.** The triggering request is always declined; the grant
takes effect from the **next** request onward (requirements §3.3). Say this in the PR's testing steps —
it looks like a bug to a reviewer who does not know.

**The FR-5 invariant:** the site-level decision commits at choice time, and an OS denial **never**
converts a stored site Allow into Never Allow. This is a deliberate divergence from Android. OS
state is re-checked on app activation (Phase 2's system client).

#### Step 4 — In-use tracking

**iOS uses none of these APIs today** — a repo-wide grep for `cameraCaptureState`,
`microphoneCaptureState`, `setCameraCaptureState`, `setMicrophoneCaptureState` finds hits in
`macOS/` only; **zero in `iOS/` and zero in `SharedPackages/`**. So port, don't invent:

- **Read-side wrapper** — `macOS/DuckDuckGo/Common/Extensions/WKWebViewExtension.swift:56-79`: a
  `CaptureState` enum (`.none` / `.active` / `.muted`) plus `var microphoneState` (`:73`) and
  `var cameraState` (`:77`).
- **KVO** — `macOS/DuckDuckGo/Permissions/Model/PermissionModel.swift:84-90`:

  ```swift
        webView.publisher(for: \.cameraCaptureState).sink { [weak self] _ in
            self?.updatePermissions()
        }.store(in: &cancellables)
  ```

- **Revocation** (Phase 4 uses it) — `WKWebViewExtension.swift:190-203` (`revokePermissions`,
  `setCameraCaptureState(.none, completionHandler: {})`). Its `.geolocation` case calls
  `configuration.processPool.geolocationProvider?.revoke()`, a **private macOS-only WebKit API** —
  explicitly out of scope (tech-design §8). Phase 6 stops watch delivery in our own provider instead.
- **Mute** — `WKWebViewExtension.swift:174-188`. Present only so you can recognise `.muted`; general
  mid-session muting is out of scope.

Port the read-side wrapper and the KVO into the package; leave the macOS files untouched. Both
properties are iOS 15+ and KVO-compliant, so no availability guard is needed. Feed the
coordinator's per-tab in-use state.

`.muted` maps to a **paused** state, distinct from active (OQ-19, resolved at kick-off as the
platform rule) — allowed, **not** shown as in-use (no red); the VoiceOver label reflects it.
macOS models this the same way (`PermissionState.swift:22-30`).

Phase 4 consumes this state for the sheet's icon states and the VoiceOver in-use announcements
(OQ-14 — no visible design change); Phase 4 also
owns the immediate-revocation writes (`setCameraCaptureState(.none)` /
`setMicrophoneCaptureState(.none)`). This phase only **observes**.

#### Step 5 — Voice Search denied-permission prompt

**In scope per the DRI decision (2026-08-28)** — it takes roughly the effort the cut grant
animation frees up. The existing voice-search mic alert gets the redesigned reminder treatment.

**Modify** `iOS/DuckDuckGo/NoMicPermissionAlert.swift` — today a plain `UIAlertController` that
deep-links to system settings. Its two call sites are
`iOS/DuckDuckGo/MainViewController.swift:3682` and
`iOS/DuckDuckGo/AIChat/InputBox/SwitchBar/OmniBarEditingStateViewController.swift:690`.

Restyle it to the redesigned reminder dialog:

| Element | Copy / behavior |
|---|---|
| Title | `DuckDuckGo needs to access your microphone` |
| Body | `Microphone permissions are needed if you want to use our Private Voice Search.` |
| Button 1 | `Change Permissions` — **primary**, deep-links `UIApplication.openSettingsURLString` |
| Button 2 | `Hide Voice Search` — flips the existing voice-search setting off |
| Button 3 | `Cancel` |

This is the **app-feature** reminder variant — blue-primary `Change Permissions` — deliberately
different from the site variants' all-gray buttons (§6.5.2).

- **Gate it behind the same `sitePermissions` flag.** Flag off → the current plain
  `NoMicPermissionAlert` shows unchanged, at both call sites.
- **The UI yield rule (§2.12) applies:** ask the user for the Figma screenshot of this dialog
  before building it.
- `Hide Voice Search` flips the **existing** voice-search setting off — do not invent a new
  preference.
- **Pixels:** the restyled prompt fires
  `voice_search_permission_prompt_<shown|settings|hide|cancel>` — one family from the approved
  set, defined with the rest in Step 6.

#### Step 6 — Pixels

**Create** `iOS/PixelDefinitions/pixels/definitions/site_permissions.json5`. iOS has **no**
permission pixel definitions today.

Swift side: a typed event enum in the **package**, mapped app-side through `EventMapping` to
**PixelKit**.

- Package event enum — precedent
  `iOS/LocalPackages/SetDefaultBrowser/Sources/SetDefaultBrowserCore/Coordinator/Model/DefaultBrowserPromptEvent.swift:20-30`
  (a plain `public enum … : Equatable`).
- App-side mapper — precedent
  `iOS/DuckDuckGo/DefaultBrowserPrompt/EventMappers/DefaultBrowserPromptPixelHandler.swift:26-64`
  for the **`EventMapping` subclass shape**.

> **Two precedents to follow only halfway.** Both `SetDefaultBrowser` mappers use the **legacy**
> `Pixel` / `DailyPixel` APIs (`DefaultBrowserPromptPixelHandler.swift:29` injects
> `PixelFiring.Type = Pixel.self`). `pixels.mdc:20` requires **PixelKit** for new production code.
> Copy the `EventMapping` structure, **not** the legacy firing calls.

For the PixelKit half, copy `iOS/DuckDuckGo/TabTerminationErrorPage.swift:53-74` — the current iOS
convention:

```swift
enum TabTerminationErrorPagePixel: PixelKit.Event, PixelKitEventWithCustomPrefix {
    …
    var namePrefix: String { "" }
}
```

with firing at `:34-50` via an injected `(any PixelFiring)?` defaulting to `PixelKit.shared`.
`namePrefix: ""` is what makes PixelKit append `_ios_phone` / `_ios_tablet`. (There is no
`PixelKitEventV2` in this repo — the protocols are `PixelKit.Event` and
`PixelKitEventWithCustomPrefix`.)

**Names — the final set, approved by the DRI 2026-08-28** (no longer a candidate list). Phase 3
fires these six families; Phase 4 adds the management families (its Step 7) and Phase 6 starts
firing the `geolocation` type:

| Family | Fired when |
|---|---|
| `permission_dialog_impression_<type>` | the 3-option dialog shows |
| `permission_dialog_click_<type>_<allow_once\|allow_always\|never>` | a site-dialog selection — user intent, **fired at tap time**, separate from the OS outcome |
| `permission_system_prompt_result_<type>_<granted\|denied>` | the OS prompt outcome after a site allow |
| `permission_reminder_dialog_<type>_<shown\|settings\|cancel>` | the denied-OS recovery (Case B) dialog interactions |
| `permission_system_settings_opened_<type>` | any `Go to System Settings` / `Change Permissions` tap — in this phase, the reminder dialog's; Phase 4 adds the sheet/Settings links to the same family |
| `voice_search_permission_prompt_<shown\|settings\|hide\|cancel>` | the restyled Voice Search denied-mic prompt (Step 5) |

Token vocabularies — define all four type tokens in the JSON5 up front, even though Phase 3 fires
only the first three:

- **type:** `camera`, `microphone`, `camera_and_microphone` (the combined dialog), `geolocation`
  (fired from Phase 6 on — note `geolocation`, not `location`, matching macOS and the persisted
  raw value)
- **dialog selection:** `allow_once`, `allow_always`, `never` — matching the dialog's three buttons

These names are deliberately **not** a mirror of macOS's four families
(`macOS/DuckDuckGo/Statistics/PermissionPixel.swift:69-83`); the one shape kept for cross-platform
analysis is `permission_center_changed` (Phase 4 Step 7). The impression family has no macOS
counterpart at all — requirements §9 asks for "prompt shown", and macOS simply doesn't measure it.

JSON5 structure: multi-segment **inline suffix enums**, like
`macOS/PixelDefinitions/pixels/definitions/permission_pixels.json5:8-18`, **plus** the shared
`platform` and `form_factor` suffix keys that iOS definitions carry and macOS's do not. Structural
template for an iOS file:
`iOS/PixelDefinitions/pixels/definitions/webkit_termination_error_page.json5`. Required fields per
`pixels.mdc:292-297`: `description`, `owners`, `triggers`, `suffixes`, `parameters`.

**Never include a domain, host, URL, or origin** in a name or parameter (`pixels.mdc:18`). macOS's
permission pixels carry exactly one custom parameter — `from` on the change event
(`PermissionPixel.swift:85-93`) — and no domain at any of its six firing sites. Hold that line.
Bucket any numeric parameter rather than sending it verbatim (`pixels.mdc:17`; precedent
`DefaultBrowserPromptPixelHandler.swift:60`).

```bash
cd iOS && npm run validate-pixel-defs
```

### 6.4 Tests

| Area | Cases |
|---|---|
| Routing, flag **off** | both legacy matrices still exact — the Phase 2 tests must pass unchanged |
| Routing, flag **on** | non-duck.ai camera / mic / combined reach the coordinator; duck.ai requests **do not**, in either flag state |
| Duck.ai in both states | identical decisions with the flag on and off, for all three types and all `.audio` states |
| Dialog view model | correct variant per type; combined variant lists both permissions; three buttons in order, none primary |
| FIFO presentation | two queued requests both presented and both answered; **neither declined** |
| Case A | OS denial after a site allow → decline, toast, stored decision **unchanged** |
| Case B | stored/chosen allow + OS already `denied` → reminder dialog; `Change Permissions` opens Settings; the request is declined |
| `restricted` / `unavailable` | treated as `denied` — the standard denied handling applies (OQ-15 deferred at kick-off); the states stay distinct in the system client |
| FR-5 invariant | an OS denial never rewrites a stored site Allow |
| In-use KVO | active → in-use; `.muted` → paused, **not** in-use; `.none` → inactive |
| Voice Search prompt | flag **off** → the legacy `NoMicPermissionAlert` shows unchanged; flag **on** → the redesigned dialog; `Hide Voice Search` turns the voice-search setting off; `Change Permissions` opens System Settings |
| Pixels | one impression per dialog shown; one click per selection, **fired at tap time** (not at the OS outcome); correct type and selection tokens; **no domain in any parameter** |

No snapshot tests (§5.4).

### 6.5 UI specification

You have no Figma access. **This section plus requirements §5–§6 is the spec.** Structural and copy
correctness is the bar; the DRI runs a separate design-fidelity pass with Figma afterwards. Where
this spec runs out — or you are unsure how anything should look — apply the UI yield rule (§2.12):
stop and ask for a screenshot of the specific Figma element. Never improvise a design.

#### 6.5.1 The 3-option site permission dialog

A custom modal over a **dimmed page** — the page stays visible behind it. Requirements §7 notes the
design is iOS 26 / Liquid Glass styled, SF Pro; **dark mode is fully designed**, so every colour
must come from a `DesignSystemColor` token, never a literal.

**Anatomy, top to bottom:** icon · title · optional body · three buttons stacked vertically.

**Buttons — identical in every variant, in this order:**

| Order | Label |
|---|---|
| 1 | `Allow Once` |
| 2 | `Allow While Using Site` |
| 3 | `Never Allow` |

**All three are equally weighted — no visual primary.** `Allow While Using Site` deliberately
mirrors Apple's "Allow While Using App"; the picker/settings wording for the same concept is
`Always Allow`, and the global default's wording is `Ask Each Time`. These are **not**
interchangeable strings — keep three separate `UserText` entries.

**Variants** (Figma component set 372:7918). Phase 3 ships the first two plus Combined; Phase 5
adds the last two.

| Variant | Icon accessor | Title | Body | Phase |
|---|---|---|---|---|
| Camera | `Glyphs.Size24.video` | `“<domain>” website wants to access your camera` | — | 3 |
| Microphone | `Glyphs.Size24.microphone` | `“<domain>” website wants to access the microphone` | — | 3 |
| **Combined camera+microphone** | `Glyphs.Size24.video` (see below) | `“<domain>” website wants to access your camera and microphone` | — | **3** |
| Location | `Glyphs.Size24.location` | `“<domain>” website wants to access your location` | — | 5 |
| Location on DuckDuckGo SERP | DuckDuckGo logo | `“duckduckgo.com” wants to access your location` | `We’ll anonymize your location and use it to deliver better results, closer to you.` | 5 |

Note the curly quotes `“ ”` — they are in the Figma copy and must be preserved. Note also two
inconsistencies flagged under OQ-4 but shipping as-is: microphone says **"the** microphone" where
camera and location say **"your**", and the SERP variant drops the word "website".

**Combined camera+microphone (OQ-2 — default adopted 2026-08-28; no Figma design exists).** One
dialog, because WebKit passes a single decision handler for the pair. Title:
`“<domain>” website wants to access your camera and microphone` — the standard three buttons
(Allow Once / Allow While Using Site / Never Allow), no body. Icon: the camera glyph
(`Glyphs.Size24.video`) — one slot, and camera is the more visually specific of the pair. **The
string and the icon choice are marked for later copy/design review**; proceed on them now and
finalize in a working build.

Sites are assumed able to request camera-only or microphone-only as well — the
`WKMediaCaptureType` verification is assumed **yes** (the enum has `.camera` and `.microphone`
cases) — so the combined variant appears only for `.cameraAndMicrophone` requests.

Decision semantics:

- `Allow Once` → ephemeral in-memory grant for the current page. Ends on reload or any
  non-same-document navigation. **Never persisted** (OQ-9).
- `Allow While Using Site` → persistent per-site allow (shown as `Always Allow` in pickers).
- `Never Allow` → persistent per-site deny.

For a combined request, one tap resolves **both** permissions the same way.

**Ordering (FR-2):** DDG's dialog first. The OS dialog only if the user chose Allow Once or Allow
While Using Site **and** the OS permission is `notDetermined`. If the OS permission is already
granted, **skip** the OS step. If the user declines DDG's dialog, the OS prompt is **never**
triggered — that is the entire point: it protects the one-shot OS prompt for later.

**Accessibility:** every button needs a VoiceOver label; the dialog needs a title trait so
VoiceOver announces it on presentation; the icon is decorative and must be hidden from VoiceOver
(the title already carries the meaning). Support Dynamic Type — the three button labels are long,
and `Allow While Using Site` will wrap at larger sizes. Do not truncate button labels; let them wrap.

House conventions, both from recent code:

- **Identifiers** are dotted `Area.Feature.Element`, e.g.
  `.accessibilityIdentifier("Settings.AIFeatures.SearchAssistPicker")`
  (`iOS/DuckDuckGo/SettingsAIFeaturesView.swift:109`, and `:149` on a button). Where a visible
  label already carries the meaning, the convention is **identifier only, no explicit
  `.accessibilityLabel`**.
- **Composed elements** get collapsed first, then labelled and valued —
  `iOS/DuckDuckGo/Subscription/Onboarding/Views/SubscriptionOnboardingProgressView.swift:147-149`:

  ```swift
            .accessibilityElement()
            .accessibilityLabel(UserText.…)
            .accessibilityValue(String(format: UserText.…, percentage))
  ```

  Static text from `UserText`; dynamic state in the **value**.

**Long domains** truncate with an ellipsis. This must hold across locales (requirements §8).

#### 6.5.2 The Case B reminder dialog

Figma set 380:46545. Same modal treatment as the permission dialog.

| Element | Copy |
|---|---|
| Title | `DuckDuckGo needs to access your <type>` |
| Body | `<Type> permissions are needed if you want to use <type> features on this site.` |
| Button 1 | `Change Permissions` |
| Button 2 | `Cancel` |

**Both buttons are gray for the site variants** — no primary. This matters: Figma also contains
**app-feature** reminder variants (Voice Search, Duck.ai Voice Chat) with a **blue-primary**
`Change Permissions`. The **Voice Search** variant is now in scope — Step 5 builds it (DRI
decision 2026-08-28). The Duck.ai Voice Chat variant belongs to another project — **do not touch
it and do not regress it** (requirements §6).

Note the body's capitalization shift: `<Type>` sentence-initial, `<type>` mid-sentence. Three
type-specific strings, not one format string with a naive interpolation — the two cases differ per
locale.

`Change Permissions` → `UIApplication.openSettingsURLString`, which lands on
Settings → Apps → DuckDuckGo.

#### 6.5.3 The Case A toasts

Presented by the **app**, through `ActionMessageView`
(`iOS/DuckDuckGo/ActionMessageView.swift:146-161`). **No action button** — pass no `actionTitle`,
which hides the button (`:174-181`).

| Type | Copy |
|---|---|
| Location | `DuckDuckGo couldn’t share location with this site` |
| Camera | `DuckDuckGo couldn’t give camera access to this site` |
| Microphone | `DuckDuckGo couldn’t give microphone access to this site` |

Note the inconsistent verb — "share location with" vs "give camera access to". Figma copy; ships as-is
(OQ-4). Note the curly apostrophe in `couldn’t`.

Presentation location follows the app's convention:
`presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom)`
— precedent `TabViewControllerMenuBuilderExtension.swift:726`.

#### 6.5.4 Icon states (shared with Phase 4)

Figma sets 443:36250 / 442:113096. Defined here because the dialog and the sheet must agree.

| State | Icon | Accessor (camera / mic / location) |
|---|---|---|
| Ask Each Time | outline | `.video` / `.microphone` / `.location` |
| Never Allow | outline + blocked badge | `.videoBlocked` / `.microphoneBlocked` / `.locationBlocked` |
| Always Allow, not in use | solid | `.videoSolid` / `.microphoneSolid` / `.locationSolid` |
| **Currently in use** | **solid, red** | the solid accessor tinted `buttonsDeleteGhostText` |

All under `DesignSystemImages.Glyphs.Size24`. `videoBlocked` and `microphoneBlocked` accessors are
**added in Phase 1** (assets already exist; accessors did not). See §11.2 on the red token.

**Red applies to both Always-Allow and Ask-Each-Time grants while in use.** Kick-off (2026-08-28)
resolved OQ-14 as **no visible design change** for the in-use state: the non-color affordance
(requirements §4.1) is **VoiceOver only**, specified in §7.5.1 of the Phase 4 spec.

`.muted` renders as the **paused** state: solid, **not** red — never shown as in-use; the
VoiceOver label reflects it (OQ-19, resolved at kick-off as the platform rule). No design change.

### 6.6 Flag-off safety checklist

This is the highest-risk phase for flag-off regressions. Do all six.

- [ ] With the flag off, `TabViewController`'s capture matrix produces **byte-identical** decisions
      to `main`. The Phase 2 frozen tests pass **without modification** — if you had to change a
      frozen test, you changed shipped behavior.
- [ ] The Duck.ai branch is evaluated **before** the flag check and is identical in both states.
- [ ] `AIChatWebViewController` diff is **empty**.
- [ ] No dialog and no toast can be reached with the flag off — and the Voice Search flow shows
      the unmodified legacy `NoMicPermissionAlert` at both call sites.
- [ ] No user-script registration in this phase at all.
- [ ] No menu row and no Settings row exist yet, in either flag state.

### 6.7 Exit criteria

- [ ] Build green; `SitePermissionsTests` + `UnitTests` green, frozen matrices unmodified.
- [ ] `npm run validate-pixel-defs` clean.
- [ ] Every new string in the package `UserText` with a real `comment:` — and a note in the PR
      description that the copy is pending review.
- [ ] Review loop completed; findings applied or logged.
- [ ] History clean; `project_log.md` and `pr3-description.md` on the documentation branch.
---

## 7. Phase 4 — Management surfaces: Settings, sheet, menus

**Branch:** `bartosz/on-site-permissions-4` — **base: `bartosz/on-site-permissions-3`**
**Asana:** https://app.asana.com/1/137249556945/task/1217863452475661
**Estimate:** ~4.5 days, ~2k LOC
**Depends on:** Phase 3

This phase completes the camera/mic milestone. After it, the feature is coherent and shippable for
two of the three permission types.

### 7.1 Scope

**Ships:**

- Settings › Site Permissions: locale-sorted entry, global pickers, prevent-asking enforcement
  (per-site overrides preserved), Manage Sites, per-site page.
- The on-site bottom sheet, all three states.
- **Both** menu entries — the legacy list menu and the sheet menu — plus a **dynamic** preferred
  detent and present/absent tests.
- Remove one / Remove all + Undo (snapshot semantics) + toasts.
- **Immediate revocation** on deny/remove.
- Management pixels.

**Explicitly out of scope for this phase:**

- No location rows anywhere (Phase 6 adds the third type to both surfaces built here).
- No address-bar indicator, no Privacy Dashboard wiring, no per-session live toggles.

### 7.2 Assumptions in effect

| OQ | Default applied here |
|---|---|
| OQ-3 | Mixed running-plus-denied state = sheet **state 2**; multi-permission footer uses the bracketed dynamic list. Still-missing strings (multi-denied, mixed granted+reminder) get minimal sensible copy, marked for later copy review. |
| OQ-4 | Figma copy verbatim; prefer multi-scaling phrasing; mark for copy review. |
| OQ-11 | Changes apply on reload / next request — hence the caption. Exception: OQ-20. |
| **OQ-12** | The literal `Permissions for site.com` header is a Figma placeholder for the real domain: **the per-site page header reads `Permissions for <domain>`**, with the real domain substituted. (Default adopted 2026-08-28; finalize later in a working build.) |
| **OQ-14** | **Resolved at kick-off: no visible design change** for the in-use state — the state text keeps showing the stored decision. VoiceOver reads `<Type>, <stored state>, in use`. |
| **OQ-16** | **Resolved — the DRI approved the final pixel set 2026-08-28.** Phase 4 fires: `permission_center_opened`, `permission_center_changed_<type>_to_<ask\|allow\|deny>` (+ `from` parameter), `permission_center_dismissed_dirty` (the parent-KPI friction signal), `permission_remove_site` / `permission_remove_all` / `permission_remove_undo`, `permission_system_settings_opened_<type>`, `settings_site_permissions_open`, and `settings_site_permissions_global_changed_<type>_to_<ask\|deny>`. All domain-free — exact wire names in Step 7. |
| **OQ-17** | Any stored record — **including an explicit Ask Each Time** — or active session state shows the menu entry. (Default adopted 2026-08-28; finalize after a working build.) |
| **OQ-18** | Sheet rows = `stored ∪ active ∪ requested-this-visit`. **Not** added merely because a global default is Never. (Default adopted 2026-08-28; finalize after a working build.) |
| OQ-19 | `.muted` = paused — **not** shown as in-use (no red); the VoiceOver label reflects it (resolved at kick-off). |
| OQ-20 | Explicit deny or Remove **immediately** revokes active capture; grants wait for reload. |

### 7.3 Ordered implementation steps

#### Step 0 — What to reuse (read before writing any view)

| Need | Reuse | Anchor |
|---|---|---|
| Sheet presentation with a content-fitting detent, iOS 15 fallback, and an iPad branch | `FireConfirmationPresenter` | `iOS/DuckDuckGo/Fire/FireConfirmationPresenter.swift:154-172` (detents), `:118-135` (iPad popover + `adaptiveSheetPresentationController`) |
| Sheet metrics — don't hardcode | `SheetMetrics` | `SharedPackages/Infrastructure/MetricBuilder/Sources/MetricBuilder/SheetMetrics.swift:23-44` |
| **Permission rows** | `CardItem` / `CardItemList` | `SharedPackages/UIComponents/Sources/UIComponents/iOS/CardItem.swift:160`, init at `:176-195`; `CardItemList.swift:28,59` |
| Row accessibility value | `CardItem`'s own `accessibilityValue:` init parameter | `CardItem.swift:176-195`; applied internally at `:243` |
| Settings picker page | `SettingsAutoplayView` + `ListBasedPicker` | see Step 3 |
| Per-domain favicon rows | `FaviconView` / `FaviconViewModel` | see Step 3 |
| Toasts with Undo | `ActionMessageView` | see Step 6 |

**`CardItem` is the row.** It already takes an `icon` (`CardItemIcon`, `.size24`), a `title`,
`titleDetails`, a `trailing:` accessory including `.checkmark(...)`, and an `accessibilityValue` —
which is, element for element, the permission row in §7.5.1. It lives in `SharedPackages/UIComponents`,
so the package may depend on it. **Use it rather than building a row.** If it turns out not to fit,
say so in the project log with the specific reason; don't quietly hand-roll a parallel row.

**Prefer the UIKit `UISheetPresentationController` path over SwiftUI `.presentationDetents`.** There
are only four `.presentationDetents` usages repo-wide, all wrapped for iOS 15 back-compat
(e.g. `iOS/DuckDuckGo/HomeMessageView.swift:217-224`), and none has an iPad story. The recent house
pattern is the UIKit one, and `FireConfirmationPresenter` is the most complete example of it.

#### Step 1 — The bottom sheet

**Create** the view and view model in the package. Three states (§7.5.1). Actions surface as
**closures** — the app presents the toasts, because `ActionMessageView` is app-only.

#### Step 2 — Immediate revocation (OQ-20)

An explicit per-site **deny** or **Remove Permissions** must revoke active use **now**:

- `webView.setCameraCaptureState(.none)` / `setMicrophoneCaptureState(.none)`;
- geolocation watch delivery stopped (Phase 6 wires the location half).

Precedent — `macOS/DuckDuckGo/Common/Extensions/WKWebViewExtension.swift:190-203`:

```swift
    func revokePermissions(_ permissions: [PermissionType], completionHandler: (() -> Void)? = nil) {
        for permission in permissions {
            switch permission {
            case .camera:
                setCameraCaptureState(.none, completionHandler: {})
            case .microphone:
                setMicrophoneCaptureState(.none, completionHandler: {})
```

Its `.geolocation` case uses `configuration.processPool.geolocationProvider?.revoke()` — a
**private macOS-only WebKit API**, explicitly out of scope (tech-design §8). Phase 6 stops delivery
in our own provider instead. Phase 3 already ported the read-side `CaptureState` wrapper
(`WKWebViewExtension.swift:56-79`); reuse it here rather than calling the raw APIs from two places.

**Every other change — including any grant — applies on reload or the next request.** That is what
the `Reload the page for changes to take effect.` caption means, and it is deliberately narrower
than macOS: macOS marks reload-needed in the banner *and* revokes immediately on deny/remove.
We match the revocation half and nothing more.

The store write and the revocation are two separate effects. Do the store write first, then revoke —
so a revocation failure cannot leave the stored decision unwritten.

#### Step 3 — Settings screens

**Modify** `iOS/DuckDuckGo/SettingsMainSettingsView.swift` (**not** `Settings/Views/…` — that
directory does not exist). Two edits:

1. Add an entry to the `settingsArrangement` array (**lines 45–53**):

```swift
        SettingsEntry(label: UserText.sitePermissions, build: Self.viewBuilder.buildSitePermissions),
```

2. Add the builder method inside `struct SettingsViewBuilder` (**lines 72–130**). Copy
   `buildDuckPlayer` (**:102-109**) — the conditional-row precedent, returning `AnyView?`:

```swift
        @ViewBuilder func buildSitePermissions(viewModel: SettingsViewModel) -> AnyView? {
            if viewModel.state.sitePermissionsEnabled {
                AnyView(NavigationLink(destination: SettingsSitePermissionsView().environmentObject(viewModel)) {
                    SettingsCellView(label: UserText.sitePermissions,
                                     image: Image(uiImage: DesignSystemImages.Color.Size24.websitePermissions))
                })
            }
        }
```

**A nil return hides the row** — the type is `(SettingsViewModel) -> AnyView?` (**:37**) and
`ForEach` (**:64-66**) renders nothing for a nil. That is the flag-off mechanism: gate on the flag
via `viewModel.state`.

**Rows are locale-sorted** (**:53**,
`.sorted(by: { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending })`), so the
Figma placement "after Sync & Backup" is **indicative only** and varies by language. Do not try to
force a position. Note that the label is used for sorting even when the row is hidden — harmless.

**Create** the new Settings views following `iOS/DuckDuckGo/SettingsAutoplayView.swift` (103 lines)
with `ListBasedPicker` (`iOS/DuckDuckGo/ListBasedPicker.swift:25-85`). `SettingsAutoplayView` is
`ListBasedPicker`'s **only** current caller, so read both together. Two details from that file:

- pass `.applySettingsListModifiers(title: "", displayMode: .inline, viewModel: viewModel)` with an
  **empty** title (`:62`) — `ListBasedPicker` sets `.navigationTitle` itself (`ListBasedPicker.swift:83`);
- the footer-with-link pattern (an `AttributedString` plus an `action://` scheme intercepted by
  `OpenURLAction`) is at `:36-45` and `:69-103`. Reuse it for the "System Settings." link.

`ListBasedPicker` already takes an optional `iconProvider: ((T) -> Image?)?` (**:31,39**) that no
caller uses — use it for the per-site picker's icons rather than writing a second picker.

**`SettingsViewModel`** (`iOS/DuckDuckGo/SettingsViewModel.swift`) — follow the autoplay pattern
exactly. Binding at **:385-397**:

```swift
    var autoplayBlockingModeBinding: Binding<AutoplayBlockingMode> {
        Binding<AutoplayBlockingMode>(
            get: { self.state.autoplayBlockingMode },
            set: {
                self.autoplaySettings.currentAutoplayBlockingMode = $0
                self.state.autoplayBlockingMode = $0
                Pixel.fire(pixel: .settingsAutoplayChanged, …)
            }
        )
    }
```

Order matters: **write the store first, then mirror into `state`, then fire the pixel.** `state` is
`@Published private(set)` (**:175**), so only the view model's own bindings may mutate it.
Dependency injection precedent: **:83** (property), **:1058** (init param with a default), **:1066**
(assignment), **:1190** (seeding `state`). Use PixelKit for the new pixels, not the legacy `Pixel`
this binding uses.

Navigation to a sub-page is a plain SwiftUI `NavigationLink` with the environment object forwarded
explicitly — precedent `iOS/DuckDuckGo/SettingsGeneralView.swift:151-158`, which also shows the
current-value summary via `accessory: .rightDetail(...)` and the required
`.listRowBackground(Color(singleUseColor: .groupedListContentBackground))`.

**Manage Sites** — a per-domain list with favicons. The existing per-domain settings list is
**Fireproof Sites**, and it is **UIKit + storyboard**
(`iOS/DuckDuckGo/FireproofingSettingsViewController.swift`, row construction at **:204-213**,
favicon via `UIImageView.loadFavicon(forDomain:usingCache:)` at
`iOS/DuckDuckGo/UIImageViewExtension.swift:27`). **Do not copy the UIKit route.** Build the new list
in SwiftUI and use `FaviconView` (`iOS/DuckDuckGo/FaviconView.swift:22-30`) with `FaviconViewModel`
(`iOS/DuckDuckGo/FaviconViewModel.swift:24-53`,
`init(domain:useFakeFavicon:cacheType:preferredFakeFaviconLetters:)`). Note
`FireproofingSettingsViewController.swift:210` uses `droppingWwwPrefix()` for display — our storage
key already drops `www.`, so no second normalization is needed for display.

#### Step 4 — Menu entries (two independent paths)

Read §11.3 first — this is the one place the tech design's shape and the code's shape differ.

Write **one** shared entry-building function, then call it from both paths:

- **Legacy list menu:** `iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift`,
  `buildLinkEntries` at **:328-360**. Insert before **:334**
  (`entries.append(bookmarkEntries.bookmark)`) to sit above Add Bookmark.
- **Sheet menu:** `BrowsingMenuBuilder.buildWebsiteMenu` — insert before
  `.init(bookmarkEntries.bookmark)` at
  `iOS/DuckDuckGo/BrowsingMenu/SheetPresentationMenu/BrowsingMenuBuilder.swift:148` (merged layout)
  and **:161** (non-merged layout). This path pulls entries through
  `protocol BrowsingMenuEntryBuilding`
  (`iOS/DuckDuckGo/BrowsingMenu/SheetPresentationMenu/BrowsingMenuBuilding.swift:32-64`), so it
  needs a **new protocol requirement** — returning an optional, like its neighbours
  (`makeFindInPageEntry`, `makeZoomEntry`, `makeDesktopSiteEntry` all return
  `BrowsingMenuEntry?`, **:54-56**). Implement it in the `TabViewController` extension next to
  `makeBookmarkEntries` (**:1148-1151**).

  **This breaks the test target until you update `MockBrowsingMenuEntryBuilder`**
  (`iOS/DuckDuckGoTests/BrowsingMenu/BrowsingMenuBuilderTests.swift:131-160`). Expected, not optional.

**An entry added only to `buildLinkEntries` will not appear in the sheet menu.** Verify both.

Entry construction — `BrowsingMenuEntry.regular` is an enum case with defaulted associated values
(`iOS/DuckDuckGo/BrowsingMenu/BrowsingMenuViewController.swift:33`); **`image` is a non-optional
`UIImage`**. Precedent, including the mandatory `[weak self]`:
`TabViewControllerMenuBuilderExtension.swift:523-542` (the Add Bookmark entry itself).

Icon: `DesignSystemImages.Glyphs.Size24.options` (`Options-24`) for the 24px sheet-menu path, and
the 16px equivalent for the legacy list menu if one exists — the bookmark entry switches on
`useSmallIcon` (**:530,537**); follow that. `Options-24` is the only options/sliders glyph in the catalog
at 24px, and `Options-16` (`Glyphs.Size16.options`, `+Glyphs.swift:307`) is its 16px twin — use
that for the legacy list menu. There is no Sliders/Tune/Filter asset at any size. `Settings-24`
exists but is the gear, which already means app settings in this menu.

**Visibility (FR-4 / OQ-17):** show the row **only** when the current site has a stored record —
including an explicit Ask Each Time — or active session state. Hidden otherwise, and hidden when
the flag is off. It is a "temporary" row: it comes and goes with the site's state. (Default
adopted 2026-08-28 — finalize after a working build. If the row's look is unclear, yield per
§2.12.)

#### Step 5 — Dynamic detent

`BrowsingMenuBuilder.swift:223` currently reads `let preferredDetentItemCount = 7`, with a comment
at **:220-222** explaining that "Open Bookmarks" is the 7th item. **That is already stale** — see
§11.4. Adding a row above Add Bookmark makes it worse.

Make it dynamic, tag-based. The model already supports it: `BrowsingMenuModel.Entry` is a struct at
`iOS/DuckDuckGo/BrowsingMenu/SheetPresentationMenu/BrowsingMenuSheetView.swift:231` with
`let tag: Tag?` at **:240**, and `enum Tag { case favorite; case fire }` at **:250-253**. It is
already used at `BrowsingMenuBuilder.swift:149` (`tag: .favorite`) and **:200** (`tag: .fire`).

(Do not confuse this with the legacy `BrowsingMenuEntry.regular` case at
`iOS/DuckDuckGo/BrowsingMenu/BrowsingMenuViewController.swift:33`, which also has a `tag:`
associated value. Two different types; the sheet model is the one the detent reads.)

1. Add an `openBookmarks` case to `BrowsingMenuModel.Entry.Tag` — `BrowsingMenuSheetView.swift:250-253`.
2. Tag the Open Bookmarks entry at `BrowsingMenuBuilder.swift:184`.
3. Replace the literal at **:223** with the flattened index of that tag, computed **after** all
   sections are appended (i.e. after **:218**, which is where line 223 already sits):

```swift
        let preferredDetentItemCount = sections.flatMap(\.items)
            .firstIndex { $0.tag == .openBookmarks }
            .map { $0 + 1 }
```

4. **Nothing else changes.** `BrowsingMenuModel+ContentHeight.swift:40-66` already treats the count
   as data and returns nil when it is absent (**:44**), and `MainViewController.swift:5255` already
   handles the nil case. Delete the now-wrong comment at **:220-222** rather than updating it.

Note `buildNewTabPageMenu` (**:78-119**) intentionally sets no `preferredDetentItemCount` — leave it.

#### Step 6 — Remove, Undo, toasts

Undo uses the Phase 1 snapshot semantics: restore **exactly** the deleted record(s), **only if** the
site has no newer record made while the toast was visible, **never** an ephemeral grant.

Toasts through `ActionMessageView.present(message:actionTitle:presentationLocation:duration:onAction:onDidDismiss:)`
(`iOS/DuckDuckGo/ActionMessageView.swift:146-161`). Use `UserText.actionGenericUndo` for the action
title and the standard presentation location. Precedent, including the paired-undo idiom:
`TabViewControllerMenuBuilderExtension.swift:717-744`.

Two behaviors worth knowing: `ActionMessageView.present` calls `dismissAllMessages()` first
(**:172**), so a second toast replaces the first; and the action button is hidden entirely when
`actionTitle` is nil (**:174-181**), which is how the Case A toasts get no button.

**`Remove Permissions` / `Remove All Site Permissions` bypass the fireproof exemption** — they
remove everything, fireproofed sites included (FR-8). **They still preserve the global defaults.**
Only Fire applies the fireproof exemption.

#### Step 7 — Management pixels

The event set below is **the final list, approved by the DRI 2026-08-28** (OQ-16 resolved) — no
adjustment pass is pending. Same names, no extras.

Extend Phase 3's `site_permissions.json5` and the package event enum with the management families:

| Family | Fired when |
|---|---|
| `permission_center_opened` | the on-site sheet opened from the browser menu |
| `permission_center_changed_<type>_to_<ask\|allow\|deny>` + **parameter `from`** | a committed change in the sheet **or** the per-site Settings page (macOS parity); a reset to Ask is `…_to_ask` — there is no separate reset family |
| `permission_center_dismissed_dirty` | the sheet closed with an edit begun but not committed — the parent-KPI friction signal |
| `permission_remove_site` / `permission_remove_all` / `permission_remove_undo` | the removal flows and Undo |
| `permission_system_settings_opened_<type>` | any `Go to System Settings` tap from the sheet or Settings links — the same family Phase 3's reminder dialog fires |
| `settings_site_permissions_open` | Settings › Site Permissions page opened |
| `settings_site_permissions_global_changed_<type>_to_<ask\|deny>` | a global default changed |

`permission_center_changed` keeps macOS's exact three-segment shape —
`permission_center_changed_{type}_to_{ask|allow|deny}` with `from` as a **parameter**, not a suffix
(macOS: `PermissionPixel.swift:85-93`; JSON5 inline param at
`macOS/PixelDefinitions/pixels/definitions/permission_pixels.json5:41-46`). Do not flatten `from`
into the name — cross-platform analysis depends on the shapes matching.

**No domains, hosts, or origins in any name or parameter.** Site-vs-all removal is a **name-level,
count-free** distinction (`permission_remove_site` / `permission_remove_all`) — not the site
itself, not how many.

```bash
cd iOS && npm run validate-pixel-defs
```

### 7.4 Tests

| Area | Cases |
|---|---|
| Menu entry present/absent | shown with a stored record (incl. explicit Ask) or active state; **hidden** with no record; hidden with the flag off — **in both menu layouts** |
| **Dynamic detent** | the count tracks Open Bookmarks' real position: with the new row present, with it absent, with the YouTube Ad Block section present, and with optional entries missing. **These tests do not exist today — you are creating the first ones.** |
| Sheet states | all three render; membership is `stored ∪ active ∪ requested-this-visit`; a globally-denied type with no record adds **no** row |
| Sheet picker | 3 options normally; `Allow This Time` (checked) replaces `Ask Each Time` while an ephemeral grant is active |
| Immediate revocation | deny → capture stops **now**; Remove → capture stops **now**; **grant → capture does not change until reload** |
| Settings entry | present when the flag is on, **absent** when off; locale sorting unaffected |
| Global pickers | **two** options only (`Ask Each Time` / `Never Allow`) — assert a third is not representable |
| Prevent-asking enforcement | global Never silently declines a no-record request; **a stored Always Allow still works** |
| Manage Sites | listed only after an explicit persistent choice; an explicit Ask row **stays** listed; ephemeral grants **never** appear |
| Remove / Undo | per-site and all-sites remove; Undo restores exactly; Undo **refuses** over a newer record; Undo never restores ephemeral; **globals survive both** |
| Fireproof asymmetry | manual removal **does** delete a fireproofed site's record; Fire **does not** |
| Pixels | correct names and tokens; `from` is a parameter; **no domain anywhere** |

### 7.5 UI specification

Requirements §5 FR-4 and FR-6 plus §6 are the source. Icon states are in §6.5.4 (Phase 3) — reuse
them; do not redefine. Where the spec runs out — or you are unsure how a screen, sheet state, or
row should look — apply the UI yield rule (§2.12): ask for the Figma screenshot; never improvise.

#### 7.5.1 The on-site bottom sheet

Figma set 442:114704.

**Header:** `Permissions for “<domain>”` + a close button. **Truncate long domains with an
ellipsis** — must hold across locales.

**Row anatomy:** type icon · label · current state · picker chevrons.

| Element | Values |
|---|---|
| Label | `Location` · `Camera` · `Microphone` |
| State | `Ask Each Time` · `Always Allow` · `Never Allow` |

Note the label/token split: the UI says **Location**, the persisted value and pixel token are
**`geolocation`**.

**Per-site picker options:**

- Normally: `Ask Each Time` · `Always Allow` · `Never Allow`
- **While an ephemeral grant is active** (Figma 870:21926): `Allow This Time` (checked) ·
  `Always Allow` · `Never Allow`

`Allow This Time` is its **own distinct string** — not `Allow Once` (the dialog button) and not
`Ask Each Time` (the option it replaces while a grant is live). Four strings, four meanings, four
`UserText` entries: `Allow Once`, `Allow While Using Site`, `Ask Each Time`, `Allow This Time`.
`Allow This Time` appears **only** in this picker, only while a grant is live, and it is always
the checked one.

**Three states:**

| # | State | Contents, top to bottom |
|---|---|---|
| 1 | **Permissions only** | header · one row per relevant permission with an inline picker · caption `Reload the page for changes to take effect.` · blue `Remove Permissions` row |
| 2 | **Permissions + Reminder** | header · rows · a group containing `Remove Permissions` **and** `Go to System Settings` (grouped together, per the design) · the reminder footer |
| 3 | **Reminder only** | header · `Go to System Settings` · the reminder footer |

State 2 is also the **mixed** state (running permissions plus a system-denied one) — OQ-3.

**`Remove Permissions` is blue** (accent), and it is a row, not a button.

**Reminder footer** — the multi-permission dynamic bracketed list; the bracket marks the growing part:

> `DuckDuckGo needs to access your camera, [location, and microphone], if you want to use related
> features on this site.`

Single-permission variants exist in Figma in **two** competing phrasings. Per OQ-4, use the one
that scales: `DuckDuckGo needs to access your <list>, if you want to use related features on this
site.` **Do not** use `DuckDuckGo needs access to this device camera, …`.

**`Go to System Settings` appears only when the user allowed the site but the OS denies it, and
disappears once the OS permission is granted** (requirements §4.2.4). Under the kick-off deferral
of OQ-15, `restricted` / `unavailable` follow the same standard denied handling — the row appears
for them too, even though System Settings may not fix those states; the designer will demo the
real restricted experience later.

**`Remove Permissions`** resets all of the site's permissions to Ask Each Time, removes the site
from the Settings list, and shows `Permissions removed for <domain>` + `Undo`.

**Presentation:** a bottom sheet with detents, presented by the app. Copy
`iOS/DuckDuckGo/Fire/FireConfirmationPresenter.swift:154-172` — a content-height-fitting custom
detent capped at a ratio of `context.maximumDetentValue`, with the iOS 15 `.medium()` fallback and
the `#unavailable(iOS 26)` corner-radius guard. Copy its **iPad branch** too (`:118-135`: popover +
`adaptiveSheetPresentationController`) — you need it, and it is easy to forget until an iPad
reviewer finds it. Take spacing from `SheetMetrics`
(`SharedPackages/Infrastructure/MetricBuilder/Sources/MetricBuilder/SheetMetrics.swift:23-44`)
rather than hardcoding.

`iOS/DuckDuckGo/MainViewController.swift:5243-5259` shows the same APIs in the browsing-menu context
and is worth reading alongside it — that is also the code Step 5's detent change touches.

**Accessibility (OQ-14 — resolved at kick-off: VoiceOver only, no visible design change):** the
row's visible state text always shows the stored state — there is **no** `In Use` text
replacement and no other new visible affordance. While a permission is actively in use, VoiceOver
announces `<Type>, <stored state>, in use`; the red icon is the visible signal. `.muted` is the
**paused** state: solid icon, not red, and VoiceOver reflects paused — it is never announced as
in use. The VoiceOver strings are still marked for copy review.

Every picker row needs an `.accessibilityValue` carrying the selected option, and the close button
an `.accessibilityLabel`. If you use `CardItem`, pass its `accessibilityValue:` init parameter and
it does the collapse-then-value step internally (`CardItem.swift:243`, with the carve-out for
interactive accessories at `:241-242`). **Do not try to call `combinedAccessibilityValue(_:)`
yourself** — it is declared in a `private extension View` (`CardItem.swift:315-326`) and is not
visible outside that file. Identifiers follow the dotted `Area.Feature.Element` convention —
`iOS/DuckDuckGo/SettingsAIFeaturesView.swift:109`. For the UIKit menu row, the `.selected` trait
precedent is `iOS/DuckDuckGo/DuckAIChromeChipView.swift:149-152`.

#### 7.5.2 Settings › Site Permissions

**Entry row:** `Site Permissions`, icon `Website-Permissions-Color-24`
(`DesignSystemImages.Color.Size24` — **the asset and accessor are created in Phase 1**;
see §4.3 Step 2). Position varies by locale (locale-sorted); Figma's "after Sync & Backup" is
indicative only.

**The Site Permissions page:**

1. A section with three global rows — `Location`, `Camera`, `Microphone` — each a **2-option
   picker**: `Ask Each Time` (default) · `Never Allow`.

   **There is no global `Always Allow`.** That is a hard privacy requirement (requirements §4.3),
   not a simplification. It is a **picker, not a toggle** — do not "simplify" it into a switch.

2. **Footer:** `You can view and modify DuckDuckGo’s system permissions in System Settings.`
   with **"System Settings."** (including the period) as a link to Settings → Apps → DuckDuckGo.
   Note the curly apostrophe in `DuckDuckGo’s`. Use the `SettingsAutoplayView.swift:36-45,69-103`
   attributed-footer + `action://` pattern.

3. **Manage Sites** section — shown **only** when at least one site has stored permissions.
   Favicon + domain rows → the per-site page. Below the list:
   `Remove All Site Permissions` → toast `Permissions removed for all sites` + `Undo`.

**Empty state:** the global pickers and the footer only. No Manage Sites section, no empty-list
placeholder.

**Per-site page:**

- **Header: `Permissions for <domain>`, with the real domain substituted** — the Figma's literal
  `site.com` is a placeholder, not copy (OQ-12, default adopted 2026-08-28).
- Three rows with the **3-option** picker.
- `Remove Permissions` — removes the site from the list, resets to Ask Each Time, toast + `Undo`.

**List membership rule (privacy-mandated, requirements §4.3 and FR-6):**

- A site appears **only after an explicit persistent choice** (Always or Never, via prompt or manager).
- A row manually reset to Ask Each Time **stays listed** until explicitly removed.
- **Merely being prompted creates nothing.** Ephemeral grants **never** appear here.

The risk this guards against is concrete and stated in the triage: a user clears History, and a
sensitive site is still visible in Settings. If you are ever unsure whether to write a record, the
answer is don't.

### 7.6 Flag-off safety checklist

- [ ] `buildSitePermissions` returns **nil** with the flag off → the Settings row is absent.
- [ ] Both menu entry builders return nil/absent with the flag off — verified in **both** layouts.
- [ ] The **dynamic detent is correct in both flag states and both layouts.** This is the one
      flag-off risk that is easy to miss: the detent change is in shared code that runs with the
      flag off. Test it off as well as on.
- [ ] No sheet and no Settings screen reachable with the flag off.
- [ ] Both legacy capture matrices still frozen; `AIChatWebViewController` still untouched.
- [ ] The Fire worker still burns with the flag off.

### 7.7 Exit criteria

- [ ] Build green; `SitePermissionsTests` + `UnitTests` green, frozen matrices unmodified.
- [ ] `MockBrowsingMenuEntryBuilder` updated; the test target compiles.
- [ ] **New detent tests exist and pass** (there were none before).
- [ ] `npm run validate-pixel-defs` clean.
- [ ] Review loop completed; findings applied or logged.
- [ ] History clean; `project_log.md` and `pr4-description.md` on the documentation branch.
- [ ] The camera/mic milestone is coherent: a user can grant, see, change, and remove camera and
      microphone permissions end to end.
---

## 8. Phase 5 — Geolocation: shim, provider, dialogs

**Branch:** `bartosz/on-site-permissions-5` — **base: `bartosz/on-site-permissions-4`**
**Asana:** https://app.asana.com/1/137249556945/task/1217863452475662
**Estimate:** ~4 days, ~1.8k LOC
**Depends on:** Phase 3 (per tech-design §5 — the dialog component and the coordinator wiring it needs land in Phase 3)

### 8.1 Scope

**Ships:**

- The `navigator.geolocation` shim: a dedicated app-registered `UserScript`, with reply-handler
  one-shots, request IDs for watches, frame routing, secure-context and Permissions-Policy gating,
  and the cross-site-iframe guard.
- The geolocation provider in the package, wired to Phase 2's shared `CLLocationManager`.
- Coordinator wiring for location requests.
- The **Location** and **Location on DuckDuckGo SERP** dialog variants.
- **Extensions** to the existing privacy-test-pages fixtures.

**Explicitly out of scope for this phase:**

- Sheet and Settings rows for location — Phase 6.
- `PermissionStatus` `change` events and the transition table — Phase 6.
- Geo pixels — Phase 6.
- Worker / service-worker Permissions API parity — **a documented gap, not a task.** No worker
  injection route exists.
- Porting macOS's private geolocation WebKit API.

### 8.2 Assumptions in effect

| OQ | Default applied here |
|---|---|
| OQ-1 | Never the OS prompt without the site dialog first (ratified at kick-off). After a site-dialog allow: OS prompt when `notDetermined`; the designed reminder dialog when already `denied`. |
| OQ-3 | Multi-permission copy uses the bracketed dynamic-list footer pattern. |
| OQ-4 | Figma copy verbatim from requirements §5–§6; multi-scaling phrasing preferred; mark for copy review. |
| OQ-21 | Host-only key from the committed main-frame URL; the requesting frame's origin is kept separately for gating and routing. |

### 8.3 Ordered implementation steps

#### Step 1 — The shim's JS and where it lives

The tech design (D3) puts the `.js` in the package, loaded via `Bundle.module` +
`UserScript.loadJS(_:from:)`. **Verified caveat: no in-repo local package pairs a `.js` resource
with `loadJS` today.** The mechanism is proven, but only by a *remote* package —
`FindInPageIOSJSSupport` (`iOS/DuckDuckGo/FindInPageUserScript.swift:23,29`), whose own package
declares `resources: [.process("jsSources")]` and `public static var bundle: Bundle = .module`.
`UserScript.loadJS` is at
`SharedPackages/BrowserServicesKit/Sources/UserScript/UserScript.swift:69`.

**Plan A** — copy the `ios-js-support` shape into the `SitePermissions` package: a `jsSources/`
directory, `resources: [.process("jsSources")]` in the target, and a
`public static var bundle: Bundle = .module` accessor.

**Plan B (pre-authorized fallback, no approval needed)** — if `Bundle.module` resolution costs
more than about half an hour of fighting SPM resource layout, **move the `.js` to `iOS/Core/` and
load it from `Bundle.core`**, exactly like `iOS/Core/FullScreenVideoUserScript.swift:26`
(`try Self.loadJS("fullscreenvideo", from: Bundle.core)`; `Bundle.core` is defined at
`iOS/Core/global.swift:48`). This is the tech design's own named fallback. Take it without
hesitation and log the choice — it costs one file location and buys back a day of risk.

#### Step 2 — The user script

**Create** the script class in the package (Swift) with the JS per Step 1. Injection config —
copy `iOS/Core/FullScreenVideoUserScript.swift` (41 lines — the whole file is the precedent):

```swift
    public var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    public var forMainFrameOnly: Bool = false
    public var requiresRunInPageContentWorld: Bool { true }
```

`.atDocumentStart`, **all frames** (`forMainFrameOnly: false`), **page content world**
(`requiresRunInPageContentWorld: true` → `WKContentWorld.page`, mapped at
`SharedPackages/BrowserServicesKit/Sources/UserScript/UserScript.swift:51-56`). The page world is
required — `navigator.geolocation` must be shimmed in the world the page actually runs in.

Unlike `FullScreenVideoUserScript`, this script **has** `messageNames` — see
`iOS/DuckDuckGo/FindInPageUserScript.swift:38-42` for the shape with names.

**Message plumbing:**

- **One-shot calls** (`getCurrentPosition`, `permissions.query`) → `WKScriptMessageHandlerWithReply`.
  Registration and forwarding already exist:
  `SharedPackages/BrowserServicesKit/Sources/BrowserServicesKit/ContentScopeScript/UserContentController.swift:296-318`
  branches on `userScript is WKScriptMessageHandlerWithReply` at `:309-313` and calls
  `addScriptMessageHandler(_:contentWorld:name:)`. Existing conformers to copy:
  `iOS/DuckDuckGo/Autoconsent/AutoconsentUserScript.swift:48`,
  `.../ContentScopeScript/ContentScopeUserScript.swift:332`.

  > **Reply-handler leak hazard.** The shared `PermanentScriptMessageHandler`
  > (`UserContentController.swift:379-432`) holds handlers in **weak** boxes. If the handler is
  > deallocated, `replyHandler` is **never called** and the page's promise hangs forever — the only
  > signal is an `assertionFailure` in debug (`:424-427`). Keep the script's lifetime tied to the
  > tab explicitly, and add a test that a deallocated handler does not leave a pending promise.

- **Long-lived `watchPosition` / `clearWatch`** → request IDs. IDs only; JS payloads carry **no
  hosts, no origins, no URLs**.

- **Repeated watch callbacks** → wrap the frame with the safe-frame pattern from
  `iOS/DuckDuckGo/TextSelection/SelectionFrameUserScript.swift:23-49`. `WKFrameInfo` stays
  `private`; the only escape hatch is
  `evaluateJavaScript(_:in:contentWorld:completionHandler:)` (`:37-42`); replies are correlated by
  a timestamp/ID and stale ones rejected (`:44-48`). **Never read `WKFrameInfo.request` — it
  terminates the app** (documented at `:25-26`).

#### Step 3 — Registration, app-side

**Modify** `iOS/DuckDuckGo/UserScripts.swift` (236 lines). Three insertion points:

1. **Property declaration** — the `private(set) var` group at **lines 60–66**, next to
   `fullScreenVideoScript` (`:64`) and `selectionFrameScript` (`:63`).
2. **`init`** — construction body, **lines 76–176**. Anything the script depends on must be
   initialized **before line 171**, because `userScripts.append(specialPages)` on that line forces
   the lazy var during `init`.
3. **The `userScripts` array** — **lines 186–193**, inside the `lazy var userScripts` at `:185-200`.

**Gate registration on the flag.** With `sitePermissions` off the script must not be in the array
at all.

> **Correction to the tech design's framing.** It says "assembly order is nondeterministic
> (`UserScripts.swift:219-233`)". Precisely: the `userScripts` array order **is** deterministic —
> it is a fixed literal plus one conditional `insert(at: 1)` (`:186-197`). What is
> nondeterministic is `loadWKUserScripts()` (`:219-233`), which appends via
> `withTaskGroup` + `for await result in group`, i.e. in **completion** order. The practical rule
> is unchanged and still mandatory: **the shim must not depend on installation order.**

**Per-tab wiring** — `iOS/DuckDuckGo/TabViewController.swift`. The delegate/handler wiring pass is
`didInstallContentRuleLists(...)` at **`:4188-4264`** (the tech design's `:4204` is one line inside
it — `registerEventHubSubfeature`). Scripts are *read* there through the computed
`userScripts` at `:4178-4180`, not attached. Two patterns available:

- Set `.delegate = self` on a shared script — the majority of `:4192-4212`.
- Construct a per-tab object and register it — `:4240-4244`
  (`breakageReportingSubfeature`, `siteLoadingPerformanceSubfeature`).

The geolocation shim needs per-tab state, so follow the second.

#### Step 4 — v1 scope boundaries and platform gating

**In scope:** Window contexts in the main frame and in document iframes.

**Gating that must be preserved — a stored allow never overrides any of these:**

- an insecure context;
- a sandboxed frame;
- an iframe not delegated by Permissions Policy.

**Cross-site iframe guard:** if the requesting frame and the top-level page differ at **eTLD+1**,
**deny outright.** Android's shipped guard, adopted.

**Never store or match** for `duck://`, `file:`, or error-page origins.

**Lifecycle:** watches cancel on navigation **and** on web-content-process replacement.

**`permissions.query`:** answer **immediately** from current state — never queue it. Phase 6 owns
the authoritative transition table. Two Android bridge defects **not** to copy: its Permissions API
returns denied for geolocation entirely, and its query checks existing grants before
allowed-to-ask, so query and the next real request can disagree. **iOS `query` must apply exactly
the same precedence as a real request.**

#### Step 5 — Dialog variants

Add two variants to the Phase 3 dialog component. Copy verbatim from requirements §5 FR-1:

| Variant | Icon | Title | Body |
|---|---|---|---|
| Location | location arrow — `DesignSystemImages.Glyphs.Size24.location` | `“<domain>” website wants to access your location` | — |
| Location on DuckDuckGo SERP | DuckDuckGo logo | `“duckduckgo.com” wants to access your location` | `We’ll anonymize your location and use it to deliver better results, closer to you.` |

Buttons are identical to every other variant, top→bottom: `Allow Once` · `Allow While Using Site`
· `Never Allow`, all equally weighted, **no visual primary**.

Note the two deliberate copy quirks preserved from Figma: the SERP variant **drops the word
"website"**, and its domain is the literal `duckduckgo.com`. Both are flagged for copy review
(OQ-4) but ship as-is. If either variant's look is unclear beyond this table and requirements §5,
yield per §2.12 — ask for the Figma screenshot.

**Case A toast (location):** `DuckDuckGo couldn’t share location with this site` — no action button.

**SERP behavior not to regress** (requirements §3.6, tested, no conflict): with DDG location set
to always allow, the SERP's "Clear location" control clears the stored SERP value but does **not**
re-trigger the prompt.

#### Step 6 — Fixtures

The privacy-test-pages fixtures **already exist** — verified in a local checkout at `647ae40`.
**Extend, do not recreate:**

| Fixture | Status |
|---|---|
| `features/geolocation.html` | exists — `getCurrentPosition`, coords/errors, background updates |
| `features/permissions-api.html` | exists — `navigator.permissions.query` for camera/mic/geo/notifications/push, `getUserMedia`, `PermissionStatus` change listeners |
| `features/iframe-permissions.html` | exists — first-party, same-origin iframe, cross-origin iframe for geo/camera/mic/DRM with explicit `allow` attributes |
| `features/iframe-media-prompt.html` + `-child.html` | exists — cross-origin camera prompt reproduction |

**Gaps to add:**

1. A minimal **combined camera+microphone** page (the existing combined call is buried in
   `features/device-enumeration-chaos/main.js`, a broad stress page).
2. An **Allow Once** reload / navigation / tab-close matrix.
3. **OS-denied recovery.**
4. A **manager-originated mutation while a `PermissionStatus` change listener is attached**.

### 8.4 Tests

| Area | Cases |
|---|---|
| iframe attribution | same-origin, same-site, and **cross-site** requesters; the cross-site eTLD+1 guard denies |
| Platform gating | insecure context, sandboxed frame, and Permissions-Policy-undelegated iframe are all denied **despite a stored allow** |
| `permissions.query` | agrees with the next real request in every precedence branch; answered immediately, never queued |
| Watch lifecycle | cancelled on navigation and on process swap; `clearWatch` works; no callback after cancellation |
| Reply handlers | one-shots resolve; **a deallocated handler leaves no hanging promise** |
| Key contract | the key comes from the committed main-frame URL, never the requesting frame, never a JS value |
| Internal pages | `duck://`, `file:`, error pages never store or match |
| Order independence | the shim works regardless of user-script installation order |

### 8.5 Verification commands

```bash
xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"
```

```bash
xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args -only-testing:SitePermissionsTests -only-testing:UnitTests -only-testing:WebViewUnitTests
```

### 8.6 Flag-off safety checklist

- [ ] **The shim is not registered when the flag is off** — assert it is absent from
      `UserScripts.userScripts`.
- [ ] Already-loaded pages keep the shim until reload. **This is documented, expected behavior** —
      note it in the PR description. Phase 6 tests the ON→OFF path properly.
- [ ] With the flag off, `navigator.geolocation` behaves exactly as it does on `main` today:
      WebKit's own prompt, no interception.
- [ ] Location dialog variants unreachable with the flag off.
- [ ] Camera/mic behavior from Phases 3–4 unchanged.

### 8.7 Exit criteria

- [ ] Build green; targeted tests green.
- [ ] Fixture extensions committed to the privacy-test-pages checkout (not to this repo) — note the
      branch/commit in the PR description.
- [ ] Review loop completed; findings applied or logged.
- [ ] History clean; `project_log.md` and `pr5-description.md` on the documentation branch.

---

## 9. Phase 6 — Geolocation management + hardening

**Branch:** `bartosz/on-site-permissions-6` — **base: `bartosz/on-site-permissions-5`**
**Asana:** https://app.asana.com/1/137249556945/task/1217863452475663
**Estimate:** ~3.5 days, ~1.2k LOC
**Depends on:** Phases 4 and 5

### 9.1 Scope

**Ships:**

- Sheet and Settings states for **location** (Phase 4 built both surfaces for camera/mic; this
  adds the third type).
- The authoritative **`PermissionStatus` transition table** plus `change` events.
- Geolocation pixels.
- **Rollback tests:** ON→OFF→new-navigation, and handler-vs-script lifetime.
- Integration hardening.

**Explicitly out of scope:** everything in tech-design §8. In particular: no address-bar
indicator, no Privacy Dashboard wiring, no per-session live toggles, no worker/service-worker
parity, no cross-device sync, no permission types beyond the three.

### 9.2 Assumptions in effect

| OQ | Default applied here |
|---|---|
| OQ-3 | Multi-permission and mixed-state copy uses the bracketed dynamic-list pattern; mixed = sheet state 2. |
| OQ-4 | Figma copy verbatim; mark for copy review. |
| OQ-20 | Explicit deny / Remove stops geolocation **watch delivery** immediately; grants apply on reload / next request. |

### 9.3 Ordered implementation steps

#### Step 1 — Location in the management surfaces

Extend Phase 4's sheet and Settings screens with the `Location` row. Same row anatomy, same
picker options, same icon-state rules — see the Phase 4 UI specification (§7.5) and reuse it
verbatim. Icons: `Glyphs.Size24.location` / `.locationBlocked` / `.locationSolid`.

Nothing structurally new here. If it feels like new structure, Phase 4 built the wrong abstraction —
fix Phase 4's code rather than adding a location-specific path. If any location-row visual is
unclear, yield per §2.12.

#### Step 2 — `PermissionStatus` transition table

Deliver an authoritative table covering **every** source state and the `change` event it emits:

- global Never;
- stored allow / stored deny / stored explicit ask;
- active allow-once;
- all OS states — `notDetermined`, `authorized`, `denied`, `restricted`, `unavailable`;
- policy denial (insecure context, sandboxed frame, undelegated iframe, cross-site iframe).

**The invariant to test:** `permissions.query` and the next real request must **never disagree**.
This is the Android defect the docs single out — its query checks existing grants before
allowed-to-ask. Encode the table as a data-driven test so a future precedence change cannot break
it silently.

Fire `change` events when a manager-originated mutation lands while a listener is attached — the
fixture for this is one of Phase 5's four additions.

#### Step 3 — Geolocation pixels

Start firing the `geolocation` type in the four flow families from the DRI-approved set
(2026-08-28): `permission_dialog_impression_<type>`,
`permission_dialog_click_<type>_<allow_once|allow_always|never>`,
`permission_system_prompt_result_<type>_<granted|denied>`, and
`permission_reminder_dialog_<type>_<shown|settings|cancel>`. **No new pixel names and no new
tokens** — Phase 3's JSON5 already defines `geolocation` in the type enum. If you find yourself
adding a `geo_`-prefixed family, stop: reuse the type token.

Note the persisted/pixel token is **`geolocation`**, matching macOS, while the user-facing label is
**Location**. Do not let the UI string leak into the wire name.

```bash
cd iOS && npm run validate-pixel-defs
```

#### Step 4 — Rollback hardening

The ON→OFF path is **not free**, and this step is the whole reason Phase 6 exists as a separate PR.
Two independent hazards, both must be tested:

1. **`UserScripts.userScripts` is lazy** (`iOS/DuckDuckGo/UserScripts.swift:185`) and
   `ContentBlockingUpdating` does **not** subscribe to feature-flag updates. So flipping the flag
   off does not by itself rebuild the script set. Test **ON → OFF → new navigation** explicitly and
   assert the shim is absent for the new load.
2. **Handler-vs-script lifetime.** WebKit removes injected scripts when content-blocking assets
   change, but **retains message handlers**. Test that a retained handler with no script does not
   crash, does not answer, and does not leave a hanging promise
   (`UserContentController.swift:419-430`).

Also test: already-loaded pages keep the shim until reload — assert the *documented* behavior
rather than pretending it doesn't happen.

#### Step 5 — Integration hardening

Work through the edge cases the docs flag as untested on either platform:

- repeated Deny on the same page;
- concurrent requests across tabs, and a tab change mid-request;
- fire-mode persistence (nothing written, in any path);
- Duck.ai requests in every flag state (must be identical to `main`);
- combined camera+mic with one OS permission denied and the other authorized;
- a manager mutation arriving while a request is pending in the FIFO.

### 9.4 Tests

Everything in Step 2 and Step 4 above, plus:

| Area | Cases |
|---|---|
| Location sheet/Settings | all three sheet states with a location row; per-site picker; global picker is **Ask/Never only** |
| Immediate revocation | explicit deny or Remove stops watch delivery **now**; a grant does not take effect until reload |
| Rollback | ON→OFF→navigation; handler lifetime; already-loaded page behavior |
| Full regression | both legacy matrices still frozen; Voice Search mic flow; SERP "Clear location" |

### 9.5 Verification commands

```bash
xcodebuildmcp simulator build --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17"
```

```bash
xcodebuildmcp simulator test --workspace-path DuckDuckGo.xcworkspace --scheme "iOS Browser" --simulator-name "iPhone 17" --extra-args -only-testing:SitePermissionsTests -only-testing:UnitTests -only-testing:WebViewUnitTests
```

```bash
cd iOS && npm run validate-pixel-defs
```

This is the last phase — run the **full** app unit-test target here, not just the touched suites.

### 9.6 Flag-off safety checklist

- [ ] ON→OFF→new-navigation proven by test: no shim, no interception, WebKit's own prompt returns.
- [ ] Retained-handler case proven safe.
- [ ] All menu and Settings builders nil; both legacy matrices verbatim; Duck.ai identical.
- [ ] The Fire worker still burns with the flag off (the Phase 1 exception is intact).
- [ ] Dynamic menu detent correct in both flag states and both menu layouts.

### 9.7 Exit criteria

- [ ] Build green; **full** `UnitTests` + `SitePermissionsTests` + `WebViewUnitTests` green.
- [ ] `npm run validate-pixel-defs` clean.
- [ ] Transition table encoded as a data-driven test.
- [ ] Review loop completed; findings applied or logged.
- [ ] History clean; `project_log.md` and `pr6-description.md` on the documentation branch.
- [ ] A short "what's left" note in the project log: copy review, design-fidelity pass, translations
      finalization, rollout and monitoring.
---

## 10. Assumptions register

Every open question in [`requirements.md`](requirements.md) §10 appears here with the default you
apply and the phase where it lands. **None of these blocks anything, and no row is gated.**
Kick-off (2026-08-28) ratified, resolved, or deferred the rows as noted below, and the DRI's
same-day follow-up answers cleared the rest — every **A** row is an adopted default, to be
finalized later in a working build. If a later correction lands, this table tells you exactly
which phase to revisit.

Legend: **R** = resolved — settled in the source docs or ratified at the 2026-08-28 kick-off.
**A** = default adopted — the DRI's 2026-08-28 follow-up answers cleared the former design/copy
gate; proceed on the documented default and finalize later in a working build.

| OQ | Question | Default applied | Kind | Phase |
|---|---|---|---|---|
| OQ-1 | Show a system dialog directly instead of the Case B reminder dialog? | Ratified at kick-off (2026-08-28): the OS prompt is **never** shown without the site dialog first — there is no "show the OS prompt directly" path anywhere. After a site-dialog allow, request the OS prompt when OS state is `notDetermined`; the designed reminder dialog applies when the OS permission is already `denied`. | R | 3, 5 |
| **OQ-2** | **Combined camera+microphone: two sequential dialogs or one combined?** | **One combined dialog.** WebKit hands a single decision handler for the pair (`TabViewController.swift:3938-3951`), so two independently-answered dialogs are physically impossible. Copy default adopted (DRI 2026-08-28): title `“<domain>” website wants to access your camera and microphone`, the standard three buttons, no body — marked for later copy review. Sites are assumed able to request camera-only or microphone-only (`WKMediaCaptureType` has `.camera` and `.microphone` cases — verification assumed yes). | **A** | **3** |
| OQ-3 | Copy for multiple denied location; mixed running-plus-denied state | Reuse the bracketed dynamic-list footer from FR-4 for multi-permission text. The mixed state is sheet **state 2** (Permissions + Reminder) — rows first, then the `Remove Permissions` + `Go to System Settings` group, then the footer. Still-missing strings (multi-denied, mixed granted+reminder) get minimal sensible copy, marked for later copy review. (Default adopted 2026-08-28.) | A | 4, 6 |
| **OQ-4** | **Two competing footer phrasings; title and punctuation inconsistencies** | **Use the Figma copy verbatim as captured in requirements §5–§6.** Where two phrasings coexist, prefer the one that **scales to multiple permissions** — i.e. `DuckDuckGo needs to access your <list>, if you want to use related features on this site.` over `needs access to this device <type>`. Keep `Reload the page for changes to take effect.` with the period. **Mark every new string for copy review; do not wait for it.** (Defaults adopted 2026-08-28; finalize in copy review.) | **A** | **3, 4, 5, 6** |
| OQ-5 | Menu-entry visibility timing after a fresh OS denial | Follows from OQ-13 + OQ-17: the site allow commits at choice time, so the menu entry appears immediately and the sheet opens in its reminder state. Ignore the contradictory Figma sticky ("No Site Permissions entry in the menu"). | R | 3, 4 |
| OQ-6 | Grant-animation placement | **Skipped in v1** — the grant animation was cut (DRI decision 2026-08-28), so placement is moot. No animation ships; the Voice Search denied-permission prompt took its slot in Phase 3. | R | — |
| OQ-7 | Fireproof exemption on Fire-Button clearing | **Fire exempts fireproofed sites; manual Remove / Remove All delete everything, fireproofed sites included; both clear per-site records only and preserve global defaults.** Ratified at kick-off (2026-08-28); the privacy ping is assumed fine and blocks nothing — the for-the-record ping can still be sent. | R | 1 |
| OQ-8 | Global Never vs stored per-site Allow | **Resolved, ratified at kick-off:** a stored per-site Always Allow overrides global Never. The global control prevents *asking* only. | R | 2 |
| OQ-9 | Allow Once validity window | **Resolved (macOS model):** in-memory, page-scoped. Ends on reload, any non-same-document navigation, tab close, web-content-process replacement, app termination. Never persisted or restored. **No** Android-style 24-hour TTL. Same-document/SPA history updates do **not** end it, and backgrounding alone does not end it. Ratified at kick-off as **provisional** — to be validated by feel in an early build. | R | 2 |
| OQ-10 | Fire-mode tabs | **Resolved (Android model), ratified at kick-off:** read stored decisions and global defaults, **never write**. Grants there are memory-only. | R | 2 |
| OQ-11 | Can changes apply without reload? | v1 assumes reload — hence the caption. The one exception is OQ-20's immediate revocation. | R | 4 |
| OQ-12 | Per-site Settings page shows a literal `Permissions for site.com` header under a real-domain nav title | The literal `site.com` is a Figma placeholder for the real domain: **the header reads `Permissions for <domain>`, with the real domain substituted** — not the literal placeholder. (Default adopted 2026-08-28; finalize later in a working build.) | A | 4 |
| OQ-13 | Does an OS denial rewrite the stored site decision? | **Resolved:** no. The site decision commits at choice time; an OS denial never converts a stored Allow into Never Allow. Deliberate divergence from Android. OS state is re-checked on app activation. Ratified at kick-off (provisional): copies macOS — the stored site Allow is kept, the request declined, and the reminder affordances appear. | R | 3 |
| OQ-14 | Non-color "currently in use" affordance | **Resolved at kick-off (2026-08-28): no visible design change** for the in-use state — no `In Use` state text, no new visible affordance. Add VoiceOver labels only: `<Type>, <stored state>, in use` while active. The solid-red icon stays as designed. | R | 4 |
| OQ-15 | UX for `restricted` / `unavailable` OS states | **Deferred at kick-off (2026-08-28): no special alert or dedicated UI in v1** — the standard denied handling applies, even though System Settings may not fix these states. Keep the states modelled distinctly in the system client (cheap); the designer will demo the real restricted experience later. | R | 2, 3 |
| OQ-16 | Friction-pixel definition | **Resolved — the DRI approved the final pixel set on 2026-08-28** (12 families; exact wire names in Phase 3 Step 6, Phase 4 Step 7, and Phase 6 Step 3). The parent-KPI friction signal is `permission_center_dismissed_dirty` — the sheet closed with an edit begun but not committed. No domains anywhere. | R | 3, 4, 6 |
| OQ-17 | Does an explicit Ask-Each-Time record show the menu entry? | **Yes** — any stored record (including explicit Ask) or active session state shows the `Site Permissions` menu row. (Default adopted 2026-08-28; finalize after a working build.) | A | 4 |
| OQ-18 | Which rows the on-site sheet lists | `stored ∪ active ∪ requested-this-visit`. **Do not** add a row solely because a type's global default is Never Allow. (macOS confirms this; see platform-precedents §6.) (Default adopted 2026-08-28; finalize after a working build.) | A | 4 |
| OQ-19 | Presentation of WebKit's `.muted` capture state | **Resolved at kick-off (platform rule):** `.muted` maps to **paused** — allowed, **not** shown as in-use (no red); the VoiceOver label reflects it. No design change. | R | 3, 4 |
| OQ-20 | Mid-session changes | **Resolved (macOS model):** an explicit per-site deny or Remove Permissions **immediately** revokes active use (`setCameraCaptureState(.none)` / `setMicrophoneCaptureState(.none)`, geolocation watches stopped). Grants and every other change apply on reload / next request. | R | 4, 6 |
| OQ-21 | Host-only key collapses scheme and port | **Host-only key** — leading `www.` dropped, punycode for IDN, scheme and port collapsed. Ratified at kick-off (2026-08-28); the privacy ping is assumed fine and blocks nothing — the for-the-record ping can still be sent. Platform gating still restricts grants to secure contexts. | R | 1 |
| — | Voice Search denied-permission prompt (scope addition, not an original OQ) | **In scope** (DRI decision 2026-08-28): `NoMicPermissionAlert` is restyled to the redesigned reminder dialog — `Change Permissions` (primary, System Settings deep link) / `Hide Voice Search` (turns the voice-search setting off) / `Cancel` — behind `sitePermissions`; flag off shows the legacy alert unchanged. Ask for the Figma screenshot before building (§2.12). See Phase 3 Step 5. | R | 3 |

---

## 11. Genuine ambiguities

Everything in the OQ table has a default (§10). These five are different: they are places where
the code, the assets, or a shipped string does not match the documents. **None blocks any phase** —
each has a stated resolution you can act on. They are listed so a reviewer can overrule a
resolution cheaply.

### 11.1 `Video-24-1` does not exist

requirements.md §7 lists `Video-24-1` among the icon assets. There is **no such asset anywhere in
the repo** — the only occurrence of that string is requirements.md itself. The real asset is
`Video-24` (`Glyphs/24px/Video-24.imageset`), accessor `DesignSystemImages.Glyphs.Size24.video`
(`DesignSystemImages+Glyphs.swift:656`).

**Resolution:** use `Glyphs.Size24.video`. Treat requirements §7 as having a typo. No design
question here — there is one video glyph at 24px and this is it.

### 11.2 iOS has no `Status-Red` token

requirements.md §7 specifies a `"Status-Red"` colour, Light `EB102D` / Dark `FF545A`. On iOS,
`DesignSystemColor` (`SemanticColor.swift:21`, `#if os(iOS)`) has **no** `statusRed`, no
`alertRed`, and no `status*` case at all. `statusRed` exists only on the **macOS**
`SharedDesignSystemColor` enum — and its values are `0xea0f2c`/`0xff5359` or `0xd83544`/`0xff5359`
depending on palette, i.e. **not** the specified pair.

The one iOS token that resolves to exactly `EB102D`/`FF545A` is **`buttonsDeleteGhostText`**
(`DefaultColorPalette.swift:192` → `alertRedOnLight`/`alertRedOnDark`, which are aliases at
`Colors/ColorSystem/Alerts.swift:37-38` for `alertRed50 = Color(0xEB102D)` (`:31`) and
`alertRed20 = Color(0xFF545A)` (`:28`)), and it is not overridden by the rebranded palette.

**Resolution:** reuse `.buttonsDeleteGhostText`. It is an exact hex match, it already has iOS call
sites (`DownloadsList.swift:215`, `BookmarkFoldersTableViewController.swift:305`), and adding a
semantic `statusRed` case to the iOS palette for one feature is a design-system change this project
did not scope. Flag it in the project log so a future rename is findable. If the design system
later gains a proper iOS `statusRed`, swapping one accessor is a one-line change.

### 11.3 The menu entry needs two independent insertions, not one

tech-design §3 (row 7) says "one entry-builder consulted by both" menus. The code is not shaped
that way today, and the difference is a real amount of work:

- The **legacy list menu** builds entries in `buildLinkEntries`
  (`iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift:328-360`).
- The **sheet menu** does **not call `buildLinkEntries` at all.** It goes through
  `BrowsingMenuBuilder`, which pulls each entry via the `BrowsingMenuEntryBuilding` protocol
  (`iOS/DuckDuckGo/BrowsingMenu/SheetPresentationMenu/BrowsingMenuBuilding.swift:32-64`) and
  assembles the bookmark group at `BrowsingMenuBuilder.swift:147-148` (merged layout) and
  `:160-161` (non-merged).

So the sheet path needs a **new protocol requirement** on `BrowsingMenuEntryBuilding`, which is a
breaking change for `MockBrowsingMenuEntryBuilder`
(`iOS/DuckDuckGoTests/BrowsingMenu/BrowsingMenuBuilderTests.swift:131-160`) — the test target will
not compile until that mock is updated.

**Resolution:** the tech design's *intent* is satisfiable and worth keeping — write **one** shared
entry-building function and call it from both paths, rather than duplicating the entry construction.
But budget for the protocol requirement and the mock edit; they are unavoidable. Phase 4 §7.3
Step 4 spells this out.

### 11.4 The detent's hard-coded `7` is already stale

tech-design §3 (row 7) describes `BrowsingMenuBuilder.swift:220-228`'s
`preferredDetentItemCount = 7` as a hard-coded index to be made dynamic. Correct — and it is
**already wrong today**, before this project touches anything: `BrowsingMenuBuilder.swift:140-142`
prepends a YouTube Ad Block toggle section ahead of the bookmark group when that entry exists,
pushing "Open Bookmarks" to position 8. The explanatory comment at `:220-222` does not mention it.
Several entries in the group are also optional (`.compactMap`, `:154/164/173`), so the position can
drift below 7 as well.

There is also **no test at all** for the detent — grep for `preferredDetentItemCount`,
`estimatedInitialDetentHeight`, `estimatedContentHeight` across every iOS test target returns
nothing, and `BrowsingMenuModel+ContentHeight.swift` has no test file.

**Resolution:** make it dynamic as the tech design says, tag-based (the sheet entry model already
carries `tag:` — `BrowsingMenuSheetView.swift:231,240,250-253`, used at
`BrowsingMenuBuilder.swift:149,200`), and
**add the missing tests** as part of Phase 4. Fixing a latent bug the project would otherwise make
worse is in scope; expanding into a menu refactor is not.

### 11.5 The camera usage-description string reads like a photo picker

Not a contradiction, but the one copy issue nobody has looked at. The OS camera prompt shows
`NSCameraUsageDescription` verbatim, and today it says:

> `Allows you to upload photographs and videos` — `iOS/DuckDuckGo/Info.plist:169-170`

That was written for the photo-upload flow. After this project ships, the **same** string appears
when a website asks for live camera access — immediately after our own dialog said
"…wants to access your camera". Compare the microphone one, which already reads for a live-capture
context: `This is required to use voice features. DuckDuckGo never records what you say.`
(`:175-176`). Location's is `Allows you to share your location` (`:173-174`), which reads fine.

**Resolution:** ship as-is; the plist keys need no code change and the feature works. **Add the
camera string to the copy-review list** in the Phase 3 PR description — it is a one-line plist edit
whenever copy gets to it, and it is the last thing the user reads before granting. Changing it is
out of scope for this project to decide unilaterally: it also affects the existing photo-upload flow.

---

## 12. Self-check

Could an agent execute Phase 1 tomorrow from this document alone, with no Asana, no Figma, and no
access to the conversation that produced it?

- Branch and base: §3. ✔
- Flag: exact files, exact insertion line numbers, exact code, and the reason the default must stay
  `.disabled`: §4.3 Step 1. ✔
- Icons: which exist, which need only an accessor, which needs a new asset, and the one requirements
  typo: §4.3 Step 2 + §11.1. ✔
- Package: full `Package.swift`, verified dependency path and product name, directory layout,
  license-header source: §4.3 Step 3. ✔
- pbxproj + scheme: the six package-registration edits with line anchors, the correct target to
  link into, the exact 10-line scheme block, the two competing registration patterns and which to
  follow, and the trap that makes tests silently not run: §4.3 Step 4. ✔
- The fact that this project has **no** buildable folders, so every new app-side file needs four
  pbxproj entries — with a worked example: §4.3 Step 7. ✔
- Model + store: raw values, key contract, the two-declaration storage pattern with real code, the
  stale-rule warning about dots, the plist-vs-Codable trap, sparse-map semantics, Undo rules:
  §4.3 Steps 5–6. ✔
- Fire worker: protocol body, template file, the reusable wide-event action, the registration array
  with line numbers, the `isAllowed(fireproofDomain:)` requirement and why: §4.3 Step 7. ✔
- Tests: the table, the mock types and their real setup lines, and the `MockFireproofing` gotcha
  that would otherwise produce vacuously-passing tests: §4.4. ✔
- Commands: copy-pasteable, with the `iOS Browser` vs `iOS Browser Alpha` trap called out: §4.5. ✔
- Flag-off and exit criteria: §4.6–§4.7. ✔
- What to do when an OQ comes up: §10, and §2.11 says not to stop for one. ✔

Yes.
