# iOS 27 (Beta) — Validated New APIs & Feature Proposals for the DuckDuckGo iOS App

*Research date: August 25, 2026. iOS 27 was announced at WWDC26 (June 8, 2026); current beta is beta 7 (Aug 24); GA expected mid-September. All claims below were researched from current sources (my baseline knowledge predates WWDC26) and then fact-checked against primary sources — Apple developer documentation and WWDC26 session pages (reachable), WebKit source headers on GitHub, and Apple support pages. Confidence tags: **[PRIMARY]** verified against Apple docs/sessions/source; **[SECONDARY]** multiple reputable outlets (MacRumors/9to5Mac/Bloomberg-Gurman), not Apple-confirmed; **[RUMOR]** single/weak sourcing.*

---

## 1. Platform context and our readiness

- **Timeline**: dev beta 1 June 8 → beta 7 Aug 24 (current) → GA ~mid-September with new iPhones. Our codebase already gates aggressively on new OS versions (50+ `#available(iOS 26)` checks, `#available(iOS 26.4)` for data-import APIs), so day-one `#available(iOS 27)` adoption fits our normal pattern.
- **Launch blocker — already handled**: building with the iOS 27 SDK **requires the UIScene lifecycle; apps without it will not launch** (Apple, WWDC26 session 278). **[PRIMARY]** ✅ We already ship `SceneDelegate` + `UIApplicationSceneManifest`. Action: verify all app extensions/widget processes and the experimental Info.plist stay compliant when we move to the 27 SDK.
- **Liquid Glass opt-out ends**: `UIDesignRequiresCompatibility` is ignored when building with the 27 SDK. **[SECONDARY]** Action: audit remaining compatibility-mode UI before the SDK bump.
- **iPhone apps become fully resizable** on iPad and in iPhone Mirroring on Mac (not on the iPhone screen itself). `UIScreen.main`/bounds/idiom assumptions break; use trait collections and `windowScene.effectiveGeometry`. **[PRIMARY]** Our omnibar/UTI layout code should be audited.
- **Hardware gating reality**: Apple Intelligence APIs (Foundation Models on-device, Visual Intelligence, Safari AI features) require iPhone 15 Pro+; the larger 20B on-device model reportedly needs iPhone 17-class hardware. Every proposal below that uses them needs a graceful fallback for the majority of devices at launch.

## 2. Validated API inventory (what's actually real)

### Foundation Models framework, year two — the big one **[PRIMARY]**
Verified against WWDC26 session 241 and Apple's ML guide:
- **`LanguageModel` protocol**: `LanguageModelSession` can now be backed by *any* model — built-in `SystemLanguageModel` (rebuilt on-device ~3B), `PrivateCloudComputeLanguageModel` (server, 32K context, Light/Medium/Deep reasoning levels), open-source `CoreAILanguageModel` (Neural Engine local models) and `MLXLanguageModel` (Mac GPU) — **and Anthropic and Google ship first-party Swift packages** so Claude/Gemini slot in behind the same API.
- **On-device model is now multimodal**: image input via `Attachment` (UIImage/CGImage/CIImage/CVPixelBuffer/file URL) in prompts; better tool calling; built-in Vision-powered **`OCRTool`** and **`BarcodeReaderTool`**; a Spotlight-backed local-search tool for on-device RAG. Guided generation (`@Generable`) continues; the model was **rebuilt**, so any iOS 26-era prompt behavior must be regression-tested (Apple ships a new **Evaluations framework** for exactly this).
- **Cost — validation catch**: the free Private Cloud Compute tier is real but **only for developers with fewer than 2 million *total* first-time App Store downloads** (widely misreported as "Small Business Program" / "annual" — neither appears in Apple's materials). **We do not qualify.** For us: the **on-device model is free and offline; PCC would be a paid API**. Plan accordingly.

### App Intents wave **[PRIMARY]**
Verified against session 343 and the Apple Intelligence guide:
- **View Annotations** for Siri's onscreen awareness: `.appEntityIdentifier(...)` on views, `.appEntityIdentifier(forSelectionType:)` for lists.
- **`.system.searchInApp`** schema (renamed from `.system.search`), **`IndexedEntity`** + `CSSearchableIndex.indexAppEntities(_:)` feeding the **semantic Spotlight index**, `IntentValueQuery` for structured search.
- **`UNMutableNotificationContent.appEntityIdentifiers`** (correct class name — commonly misreported) so Siri has entity context when announcing notifications.
- **App Intents Testing framework** — exercise intents through real Siri/Shortcuts/Spotlight pathways in CI.
- SiriKit is on a deprecation clock; App Intents is the sole integration path. **[SECONDARY]**

### Siri AI and the "Extensions" program
- **Siri AI** (rebuilt assistant + dedicated chatbot app, Gemini-powered brain in PCC, web answers with citations): real, in betas, **waitlisted at September GA** — and **not shipping in the EU on iOS/iPadOS, indefinitely** (Apple newsroom statement; Federighi: no timeline; it does reach EU users on macOS/visionOS 27). **[PRIMARY for EU absence; SECONDARY for waitlist]**
- **Third-party model "Extensions"** (Gemini/Claude/Grok/ChatGPT powering Siri, Writing Tools, Image Playground; user-selectable default model; providers plug in **via their App Store apps** — an open opt-in program, not bilateral deals): **not in current betas**; expected in iOS 27.x point releases later this year, possibly revealed at the September event. **[SECONDARY — Bloomberg/Gurman-sourced; not Apple-confirmed]**
- **Side-button third-party assistants**: Apple-documented ("Launching your voice-based conversational app from the side button of iPhone") via App Intents + App Shortcuts — **Japan only** (iOS 26.2+, Mobile Software Competition Act). No announced EU/global expansion; the EU equivalent is stalled in the Siri-AI/DMA standoff. **[PRIMARY for Japan]**

### Safari 27 and WebKit **[PRIMARY where noted]**
- Safari app (Apple-announced, Apple Intelligence-gated): **automatic AI tab organization** into topics; **"Notify Me"** page-change monitoring (restocks, price drops); **"Describe an Extension"** — users generate personal Safari extensions from natural language (name commonly misreported as "Create an Extension"). **[SECONDARY, WWDC-day coverage of Apple announcements]**
- WKWebView (verified in WebKit source headers, `WK_API_AVAILABLE(ios(27.0))`): **`WKHTTPCookieStore.getCookiesForURL`** (per-URL cookie fetch), `WKWebpagePreferences.alternateRequest` / `overrideReferrerForAllRequests`, **`willSubmitForm`** on WKNavigationDelegate, `loadURL:`, `WKContentWorldConfiguration`. **Correction from validation: there is no "clear a content world" API** — that claim circulating in coverage is false. **[PRIMARY]**
- **Safari Web Extension Packager**: package/submit Safari extensions via App Store Connect without Xcode. **[PRIMARY]**
- Japan (iOS 26.2, same fall window, not iOS 27): alternative browser engines, **browser choice screen**, **search-engine choice screen in Safari**, Safari uninstallable. **[PRIMARY — Apple support page]**

### Other validated items
- **Visual Intelligence third-party integration**: App Intents-based (`IntentValueQuery` receiving `SemanticContentDescriptor`); camera gains a "Siri mode". Launch partners: QuickBooks, HelloFresh, Pinterest. **[PRIMARY]**
- **Core AI framework** (new, OS-built-in): modern Swift API for running your own on-device models (AOT compilation, memory control, stateful execution); Core ML remains supported. **[PRIMARY]**
- **Shortcuts rebuilt**: "Use Model" gains **web retrieval** and model tiers (on-device / Cloud / Cloud Pro — Cloud Pro requires a 200GB+ iCloud+ tier); persistent **Storage** values synced via iCloud. **[PRIMARY + SECONDARY for tiers]**
- **Live Activities**: Dynamic Island in landscape; auto-propagation to Watch Smart Stack, macOS menu bar, CarPlay. **[PRIMARY]**
- **System dictation substantially improved**; Writing Tools adds a grammar checker; system "select anything → ask Siri" flows. **[SECONDARY]**
- UIKit menus get an **automatic "Ask Siri" button**. **[PRIMARY]** (We should decide whether we want that appearing in our menus.)
- No new BGTask/push APIs; no significant SpeechAnalyzer changes; no new PrivacyInfo requirements found.

## 3. Feature proposals

### Tier 0 — SDK-readiness work (required before any of it)
| # | Item | Why |
|---|---|---|
| 0.1 | iOS 27 SDK audit: extension targets' scene compliance, `UIScreen.main`/bounds/idiom sweep, Liquid Glass compat-flag removal, UTI/omnibar layout under resizable windows | Launch-blocker class; main app is already scene-based |
| 0.2 | Decide policy on UIKit's automatic "Ask Siri" menu button and on View Annotations | Onscreen awareness sends annotated context to Siri AI (Apple/Google infrastructure) when the user invokes it — for a privacy browser this must be a deliberate, probably user-controlled, choice |

### Tier 1 — High-value, buildable at GA
1. **Duck.ai On-Device Fast Lane** *(Foundation Models `SystemLanguageModel`)* — free, offline, provably private inference for: instant answers to simple prompts with smart routing up to Duck.ai cloud models ("answered on your device" badge); offline Summarize/Translate of pages and selections in contextual mode; on-device generation of suggested prompts and follow-ups. This is exactly the "on-device mini model" bet from our competitive analysis — except Apple now ships the model, the API, and the marketing narrative ("private by architecture") for free. Gate: iPhone 15 Pro+, `#available(iOS 27)`; regression-test everything against the rebuilt model using Apple's Evaluations framework.
2. **Private Tab Intelligence** *(SystemLanguageModel + guided generation)* — match Safari 27's AI tab organization with on-device tab grouping/dedup suggestions in the tab switcher, and "ask about my open tabs" in Duck.ai (ties into porting macOS @-mention/multi-tab attach). Safari sets the feature bar this fall; we can meet it with a stronger privacy story (never leaves the device).
3. **Semantic Spotlight presence** *(`IndexedEntity` + `.system.searchInApp` + `IntentValueQuery`)* — index bookmarks, favorites, history (and, opt-in, Duck.ai chat titles) into the semantic Spotlight index so Siri AI-era system search surfaces our content and deep-links into the app. Free re-engagement traffic; entirely local index. Chat content should stay out by default.
4. **Side-button Duck.ai Voice in Japan** *(documented App Intents/App Shortcuts pattern, iOS 26.2+)* — we already ship `AIVoiceChatIntent`; conform it to Apple's side-button assistant pattern so Japanese users can set Duck.ai as their side-button assistant. Japan simultaneously gets browser and search choice screens — a coordinated Japan acquisition push this fall is cheap and timely. Keep the implementation ready to flip on for the EU if the DMA standoff forces expansion.
5. **Voice-session Live Activity** *(Live Activities/Dynamic Island)* — ongoing Duck.ai voice chat as a Dynamic Island live activity (Siri now lives there; we should too), propagating to Watch/CarPlay automatically. Pairs with the existing live-voice tab-switcher card.
6. **WebKit engineering wins** *(verified 27.0 APIs)* — `getCookiesForURL` for faster cookie-popup handling and Fire-button scoping; `willSubmitForm` for autofill/Email Protection improvements; evaluate `alternateRequest`/`overrideReferrerForAllRequests` for privacy protections. Small, concrete, ships with the SDK bump.

### Tier 2 — Strategic bets and watch items
7. **"Notify Me," but private** — Safari's page-change monitoring validates demand; a client-side page-watch (background refresh + local notifications, no server profile) slots directly into the "Private Daily Prompts" concept from our competitive analysis and works on all devices (no Apple Intelligence gate).
8. **Extensions program readiness** — if the third-party-model program ships as reported (open opt-in via App Store apps), evaluate registering **Duck.ai as a selectable system AI provider** (Siri/Writing Tools backed by Duck.ai). Enormous distribution if real; requirements unknown until Apple publishes them. Owner + a decision memo when the program is announced (possibly September event).
9. **`DuckAILanguageModel` Swift package** — Anthropic and Google ship packages conforming to `LanguageModel` so any Foundation Models app can use their models. A Duck.ai package (anonymous, no API key, privacy-first) would put Duck.ai inside other developers' apps. Needs a public-API decision, so flagging as strategic, not committed.
10. **Visual Intelligence integration** — register DDG search results for Visual Intelligence camera/screenshot queries via `IntentValueQuery`/`SemanticContentDescriptor` (as Pinterest et al. did). Caveat: the image flows through Apple's surface first; position as reach, not a privacy feature.
11. **EU window** — Siri AI is absent from EU iPhones indefinitely. For at least this cycle, the EU has no built-in AI chatbot: our strongest market to push Duck.ai as the default AI habit, while ChatGPT/Gemini fight the waitlisted Siri elsewhere.

### Explicitly deprioritized
- **PCC-based server features** — we exceed the 2M-download free-tier cap; our own anonymized backend remains the right cloud path.
- **Core AI framework custom models** — powerful but heavy; revisit if we ever ship our own fine-tuned on-device model (the Foundation Models system model covers Tier 1 needs).
- Waiting on **SpeechAnalyzer/BGTask/push changes** — validated as unchanged in iOS 27; no work to plan.

## 4. Corrections surfaced by validation (worth knowing before anyone plans against them)
1. The Foundation Models free cloud tier is **not** Small-Business-Program-based and **not** annual — it's total first-time downloads < 2M, which excludes us.
2. There is **no** "clear a content world" WKWebView API despite press claims — only `WKContentWorldConfiguration` and per-world handler/buffer removal.
3. Safari's NL extension builder is **"Describe an Extension"**, not "Create an Extension".
4. Notification entity annotation is on **`UNMutableNotificationContent`**, not `UNNotificationContent`.
5. The third-party "Extensions" program was **not announced at WWDC26** (several outlets claim otherwise) — it's Gurman-reported, expected in iOS 27.x.
6. iPhone "resizability" applies to iPad/iPhone-Mirroring contexts, not windowing on the phone itself.
