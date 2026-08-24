# Duck.ai on iOS — Competitive Analysis & Product Recommendations

*Research date: August 2026. Sources: codebase audit of `iOS/DuckDuckGo/AIChat`, `UnifiedToggleInput`, `SharedPackages/AIChat`; web research on ChatGPT, Gemini, Perplexity, Claude, Copilot, Meta AI, Grok, Brave Leo, Proton Lumo, and AI-browser products. Goal: increase prompts per user and retention vs. standalone AI apps.*

---

## 1. Market snapshot (August 2026)

- **ChatGPT**: ~1B weekly actives, ~2.5B prompts/day — but its mobile assistant share fell **below 50% for the first time** (46.4% by May 2026). Free tier now shows **ads** (since Feb 2026), a fresh positioning opening for us. DAU/MAU ~36%; paid retention is best-in-class (~71% at 6 months).
- **Gemini**: 1B+ MAU, DAU tripling YoY. Won the deeper prize on iOS: a ~$1B/yr deal to **power Siri itself** (from iOS 26.4) via Apple Private Cloud Compute. Its free tier gives away live voice **with camera**.
- **Category economics**: generative-AI apps have among the *worst* D30 retention of any app category (~5%). Menlo's 5,000-adult survey: most people pick **one default assistant and try it first for everything**. Habit, not capability, is the scarce asset — and the market is loosening (multi-homing and switching are rising).
- **The industry's chosen retention stack** (converged on by ChatGPT, Gemini, and Copilot in 2025–26): **memory/personal context** (the switching cost) + **scheduled tasks & daily briefings with push notifications** (the daily-open lever) + **voice with camera on the lock screen / Action Button** (the frictionless entry) + OS hooks.
- **Browser+AI fusion is the 2026 battleground on iOS**: Perplexity's Comet hit **#3 overall on the US App Store**; Microsoft dissolved Copilot Mode *into* Edge; Opera ships free "Opera AI". Dia still has no mobile app. DDG's browser distribution is a structural advantage here that standalone chat apps cannot copy.
- **Privacy tailwind is empirical now**: ChatGPT shared-chats indexed by Google; the NYT court order forcing retention of *deleted* ChatGPT chats; Anthropic's flip to opt-out training with 5-year retention; Meta targeting **ads from AI chat content with no opt-out**; ads in ChatGPT free. Pew (June 2026): **71% of US adults say AI makes personal data less secure**; only 29% of users trust chatbot outputs; KFF: 77% worry about the privacy of health questions asked of AI.
- **What doesn't work**: gamification. Grok's companion/affection-meter mechanics drove downloads, then got retired (July 2026). Meta's engagement-feed-plus-ads model is the cautionary tale our marketing writes itself against.

## 2. Where Duck.ai on iOS stands today

The codebase audit shows we are much closer to feature parity than the market perceives.

**Already at or near parity (table stakes we have):** native composer with Search↔Duck.ai toggle (UTI), model picker with tier gating, reasoning-effort picker, image + file/PDF attachments, image generation, web-search tool, voice mode (incl. lock-screen widget, Control Center, Siri phrases), native chat history with search/pin/multi-select/export, E2E-encrypted chat sync, contextual page chat with auto page-context and page-aware suggested prompts, prompt editing, usage-limit UI, subscription tiers with upsell funnels, ~15 instrumented entry points.

**Unique structural advantages nobody else has:**
1. **No account required.** Anonymous by architecture (proxying to frontier models), chats never used for training, Fire button. Brave Leo is the closest analog but is locked to its browser's small base; Proton Lumo requires ecosystem buy-in for the good parts; Venice paywalled its differentiators.
2. **The default-browser slot.** The one OS-level position Apple grants freely — ChatGPT's Atlas browser died before reaching iOS; Gemini rents Siri but can't be the browser. Every address-bar moment is a potential prompt.
3. **Search + chat in one box.** The UTI toggle is a genuinely differentiated surface; nobody else owns the "one box for both" pattern on iOS.

**Gaps vs. ChatGPT/Gemini (the retention stack we lack):**

| Capability | ChatGPT | Gemini | Duck.ai iOS |
|---|---|---|---|
| Memory / personal context | ✅ free tier | ✅ | ❌ none |
| Custom instructions / personas | ✅ + 8 personalities | ✅ Gems | ⚠️ web modal only (macOS has native) |
| Scheduled tasks + push notifications | ✅ | ✅ + Daily Brief | ❌ none |
| Projects / folders | ✅ free tier | ⚠️ | ⚠️ pin only |
| Live camera in voice | ✅ paid | ✅ **free** | ❌ audio only |
| Share-sheet target ("Ask about this") | ✅ | ✅ | ❌ none |
| Shortcuts intent with prompt parameter | ✅ "Use Model" | ✅ | ⚠️ open-app only |
| Image editing | ✅ | ✅ Nano Banana | ❌ generation only |
| Group / shared chats | ✅ (viral loop) | ❌ | ❌ |
| Conversation branching | ✅ | ❌ | ❌ |

**Internal gaps (built on macOS, missing on iOS):** native sidebar, @-mention tab attachment, attach-multiple-tabs, Translate/Summarize page as first-class services, native Customize Responses, prompt draft persistence.

**Nearly done, just not shipped:** text-selection actions (Ask/Summarize/Translate — internal flag), paste-to-attach, iPad model picker, usage warnings.

## 3. Strategy

Frame everything against a three-part loop, with privacy as the wedge on each part:

- **Reach** — more moments where opening Duck.ai is the path of least resistance.
- **Habit** — a reason to open the app *daily*, not just when a question strikes.
- **Investment** — accumulated value (memory, organized chats, personalization) that makes leaving costly — *without* an account, which is our twist nobody can copy credibly.

The market's own data says memory is the real lock-in ("the months of accumulated context users would leave behind") and daily briefings/scheduled tasks are the daily-open lever. Both are considered privacy-incompatible by users — Lumo's zero-access encrypted memory proves they aren't. **"The AI that remembers for you, not about you" is an ownable position.**

## 4. Recommendations

### P0 — Quick wins (reach; mostly existing code)

1. **Share extension: "Ask Duck.ai" from any app.** Accept text, URLs, images, PDFs from the iOS share sheet into a chat (reuse the attachment pipeline). ChatGPT and Gemini are both share targets; we have zero presence at the OS's main cross-app junction. Every share is a prompt we currently don't get.
2. **Parameterized App Intents + Action Button story.** Today `AIChatIntent` only opens the app. Add an `AskDuckAI(prompt)` intent usable in Shortcuts chains (mirroring iOS 26 "Use Model"), and actively market the Action Button / Control Center / lock-screen setups we already ship — competitors treat Action Button placement as a primary habit vector; ours is buried in a settings education screen.
3. **Ship what's behind internal flags.** Text-selection actions (Ask/Summarize/Translate) and paste-to-attach are built. Selection actions turn every page into a prompt source.
4. **Port Translate/Summarize-page as first-class actions from macOS** into the browsing menu and contextual sheet — one-tap page utility, no typing, pure prompt volume.
5. **Privacy receipts in-product.** Small, factual trust moments at the right time: first prompt ("No account. Not used for training. Burn it any time."), after Fire, in the history view. With ads in ChatGPT's free tier and Meta targeting ads from chats, the contrast now states itself — our UI should surface it where the decision happens.

### P1 — The retention core (habit + investment; the big bets)

6. **Private Memory + native personalization.** Device-local memory and custom instructions (tone, profession, standing context), user-viewable and editable, synced only via our existing E2E-encrypted sync, injected client-side into prompts. Never server-side, never profiled. This is the single biggest driver of both prompts/user and retention in every competitor analysis — and Lumo shows a privacy player can ship it. Includes making Customize Responses native (macOS already has the store/modal to port).
7. **Import from ChatGPT/Claude.** Claude shipped memory *import* as an explicit switching-cost attack. Both competitors offer chat export; we should parse it: "Bring your chats and what your AI knows about you. Here, it stays yours." Cheap, high-leverage at the exact moment (46.4% share and falling) users are shopping around.
8. **Private Daily Prompts — scheduled prompts with local notifications.** The client-side answer to ChatGPT Scheduled Tasks / Gemini Daily Brief / Copilot Daily: the user picks prompts and a schedule ("every morning: top AI news + weather in Amsterdam"); the app fires them anonymously via background refresh and delivers a **local** notification. No server ever holds a profile or schedule. This is the category's proven #1 daily-open mechanic, rebuilt in a form only we can claim: *a daily briefing that no server knows you get.* Also a natural subscription perk (more scheduled prompts, better models).
9. **Camera in chat and voice.** Gemini made live camera in voice free for everyone; it's become table stakes for "point at the world and ask." Milestone 1: camera capture button in the composer (attachment pipeline exists). Milestone 2: vision in voice mode.
10. **Projects/folders on native history.** Pin exists; add folders, then per-project instructions once memory ships. Organization is investment — accumulated structure users won't abandon.

### P2 — Differentiated bets

11. **Own browser+AI fusion on iOS.** Comet's #3 ranking validates the category; Dia's absence leaves the field open; we already have contextual mode, page context, and full-tab Duck.ai. Double down: port @-mention tabs and multi-tab attach from macOS, ship the iPad native sidebar, make "ask about what I'm looking at" the signature move. A browser that chats beats a chatbot that browses — and we're the only privacy player with real browser distribution.
12. **Image editing.** Nano Banana was the single largest user-acquisition event in the category's history (23M first-time users in weeks, took Gemini to #1). We have generation; editing (upload → transform) is the viral, demoable half. Strong Pro-tier upsell.
13. **On-device mini model.** Instant/offline answers for simple prompts, routing up to cloud models when needed. Rides the Apple Intelligence "private-by-architecture" wave, cuts inference cost, and gives marketing an unmatchable demo: airplane-mode AI.
14. **Evaluate, don't chase: group chats.** ChatGPT's group chats are a viral loop but sit awkwardly with anonymity and would be heavy to build. Revisit after P1 lands.

### Explicitly not recommended

- **Streaks/gamification** — Grok built the category's only real gamified companion system and retired it within a year.
- **Ad-funded feeds or server-side profiling briefings** — Meta's ads-on-chats and ChatGPT's free-tier ads are the trust failures our position is built against; local-only proactivity (P1.8) achieves the habit without the liability.

## 5. Measurement

Instrumentation is already unusually strong (unified `m_aichat_entry_point`, funnel + retention pixel patterns from SwitchBar, wide events). Suggested focus:

- **North star: prompts per weekly Duck.ai user** (volume × habit in one number), segmented by entry point.
- **Guardrail: W1→W4 repeat-prompt retention**, watching which entry point a user's *first* prompt comes from — the research suggests OS-surface entries (widget, share, selection) predict habit better than in-browser curiosity.
- Reuse the SwitchBar funnel pattern (first exposure → first prompt → repeat → retained) for each P0/P1 launch.

## 6. TL;DR

We have near-parity on chat features and two moats nobody can copy (no-account privacy, browser distribution) — what we lack is the **retention stack**: memory, daily-utility notifications, and OS-level reach (share sheet, parameterized Shortcuts, camera). The competitors' own playbook, rebuilt privacy-first — private memory, local scheduled briefings, import-your-history — turns their lock-in mechanics into our differentiators at exactly the moment ChatGPT's share is slipping and its free tier turned on ads.
