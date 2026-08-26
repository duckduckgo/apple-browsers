# Prompt: investigate macOS and Android permission implementations (platform precedents)

You are a senior engineer investigating prior art for the iOS "On-site Permission Manager" project. Your only deliverable is **`docs/on-site-permission-manager/platform-precedents.md`**, committed on the current branch **`bartosz/on-site-permissions`** of the apple-browsers repo (repo root = your working directory). This is a **read-only investigation**: change no code, in any repo, and never push. You have **no Asana or Figma access** — do not open such links; `docs/on-site-permission-manager/requirements.md` and `tech-design.md` are authoritative for product context.

## Why this investigation exists

DuckDuckGo shipped a per-site permission model on **macOS** (Permission Center, Dec 2025), and **Android** has long-standing site-permissions infrastructure (a global "prevent sites from asking" setting and a per-site list) plus a recent sibling project that redesigned the denied-permission recovery prompt; two further Android siblings (tiered 3-option prompt, on-site manager) may or may not have shipped — verify in code. The iOS project made several decisions on *defaults* that kick-off and a privacy ping still need to ratify. Concrete precedent from the two shipped platforms is the strongest input for both. Spawn sub-agents freely and in parallel.

## Where the code is

- **macOS:** this repo — `macOS/DuckDuckGo/Permissions/{Model,View,ViewModel}/`, `macOS/DuckDuckGo/Tab/Model/Tab+UIDelegate.swift`, `macOS/DuckDuckGo/Fire/Model/Fire.swift`, `macOS/UnitTests/Permissions/`, `macOS/DuckDuckGo/Statistics/PermissionPixel.swift`.
- **Android:** local checkout at `/Users/bkunat/Desktop/ddg-workspace/ddg-android`. First record `git -C … log -1 --format='%h %ad %d'` in your report so staleness is known; do not fetch or pull. Start from modules/paths matching `site.permissions` / `sitepermissions` and the location permission feature; find the dialogs, the settings screens, the storage layer (Room/SharedPreferences), the fire/clear-data integration, and the pixel definitions.
- **Side task — fixtures:** local checkout at `/Users/bkunat/Desktop/ddg-workspace/privacy-test-pages`. Report whether geolocation / Permissions-API test fixtures exist there (the iOS plan needs them in PR 5), with paths.

## Questions to answer

For each item: **macOS behavior** (file:line), **Android behavior** (file:line), and a one-line **recommendation for iOS** — explicitly saying whether it confirms or contradicts the iOS default already recorded in requirements.md / tech-design.md.

1. **Global vs per-site precedence (OQ-8).** Android has global per-type controls: when the global is "deny/never ask", does a per-site allow still win? Where is that enforced? (iOS default: global Never is absolute.)
2. **"Allow once" validity window (OQ-9).** What exactly ends Android's session-scoped grant (reload, navigation, tab close)? What does macOS do (its model distinguishes until-reload vs page semantics)? (iOS default: per tab+site, ends on leaving the site or tab close, survives reload.)
3. **Combined camera+microphone (OQ-2).** macOS has a combined `.cameraAndMicrophone` authorization dialog — extract its exact copy and button structure. How does Android present combined requests? (iOS default: one combined dialog.)
4. **Recovery from OS/app-level denial (OQ-5, OQ-13, FR-5).** The Android "redesign prompt following a denied permission" sibling shipped — find its actual UX: what it shows, when, and how the per-site decision is committed relative to the system answer. Note the platform difference (Android can re-request runtime permissions unless permanently denied; iOS cannot re-prompt at all) and say what transfers.
5. **List membership / explicit-ask rows (OQ-17).** When does a site appear in and disappear from Android's per-site list? Does a user-reset "ask" row stay listed? Compare macOS's `.ask`-marker semantics. (iOS default: user-reset ask rows stay listed; menu entry shows for any stored record or active state.)
6. **Manager row rules (OQ-18).** Which permission rows do the macOS Permission Center and Android's per-site screen show — persisted only, used-this-page, requested-this-visit? (iOS default: stored ∪ active ∪ requested-this-visit.)
7. **In-use and muted indication (OQ-14, OQ-19).** How does macOS represent active vs paused/muted capture (`PermissionState`, tab-bar indicator), and what accessible affordances exist? Anything equivalent on Android?
8. **Restricted / system-disabled states (OQ-15).** macOS distinguishes restricted/system-disabled and has a dedicated info view — extract its copy and behavior. Android equivalent, if any.
9. **Mid-session changes and reload (OQ-11, OQ-20).** macOS `permissionsNeedReload` behavior; what Android does when a permission changes while a page is using it. (iOS default: applies on reload/next request.)
10. **Privacy defaults to validate (for the privacy ping):**
    - **Fire/fireproofing:** does Android's fire button clear site permissions, and does anything survive (fireproofed sites)? Confirm macOS `burnPermissions(except: fireproofDomains)` details. (iOS default: Fire exempts fireproofed sites; manual removal clears everything.)
    - **Clearing scope:** does Android's clearing reset the global toggles or only per-site rows? (iOS default: per-site only; globals preserved.)
    - **Storage key:** exactly how each platform keys stored permissions — origin, host, eTLD+1? `www.` handling? scheme/port? (iOS default: host-only, www-dropped — OQ-21.)
11. **Tiered 3-option prompt status on Android.** Shipped, behind a flag, or unmerged? If any copy exists, capture the option labels (compare against iOS's "Allow Once / Allow While Using Site / Never Allow").
12. **Pixels.** Android's site-permission pixel names and parameters, and macOS's `PermissionPixel` set — anything measuring manager engagement or abandoned changes (informs OQ-16), and naming worth mirroring for cross-platform ClickHouse comparisons. Confirm neither platform puts domains in pixels.
13. **Anything else the iOS docs miss** — edge cases visible in Android/macOS code comments and tests (e.g. DRM/protected-media as an Android permission type, multi-window, external-scheme interactions) worth a line in requirements or explicitly out of scope.

## Output format (`platform-precedents.md`)

1. Header: Android checkout ref + date; scope note (read-only, no fetch).
2. One section per question above: macOS findings, Android findings (file:line for every claim), recommendation, and a **verdict tag**: `confirms iOS default` / `contradicts iOS default` / `no precedent`.
3. A summary table mapping each finding to the kick-off discussion item / OQ number it informs.
4. **Fixtures answer** for privacy-test-pages.
5. A short list of concrete edits you recommend to requirements.md / tech-design.md / kickoff.md (do not make them — list them).

Commit the file on `bartosz/on-site-permissions` with the repo's Claude co-author trailer. Never push. Then summarize the contradictions (if any) first — they matter most.
