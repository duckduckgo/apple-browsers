# Reader mode prototype

Hack project shared by the iOS and macOS browsers. Articles are extracted on device; page content is never uploaded.

## Package

- `ReaderModeExtractor` runs trafilatura on a page's HTML and returns a `ReaderArticle`, or nil when the page is not eligible. It is synchronous; callers run it off the main actor.
- `ReaderArticle` sanitizes its content in its initializer with a SwiftSoup allowlist, so no caller can create an article that carries scripts, forms, frames, event handlers, inline styles, source sets, or non-HTTP links and images. Relative links become absolute against the article URL; element IDs survive so in-page links work.
- `ReaderDocument.html(for:theme:)` wraps an article in a static page with a strict Content Security Policy and `no-referrer`. `ReaderTheme.designSystem` resolves the page colors from DesignResourcesKit for light and dark appearance on each platform.

A page is eligible when the input is at most 1 MiB, the extracted text has at least 500 characters in at least two paragraphs, and at most half of the page's visible text sits inside links. The link ratio rejects link listings such as a news aggregator front page, which trafilatura otherwise flattens into a single paragraph. These are prototype policies, not measured accuracy targets.

## Trafilatura binary

`TrafilaturaFFI` comes from the `ayoy/trafilatura-rs` fork, release `v0.5.0-ddg.1`, pinned by checksum. Upstream ships a static library, which clashes with the macOS app's other Rust static library (duplicate `rust_eh_personality` and `module.modulemap`); the fork builds the same 0.5.0 code as a dynamic framework with iOS device, iOS simulator, and macOS slices. The Swift bindings in `Sources/Trafilatura` come from the same release, because uniffi checks at load time that bindings and binary match. They are generated code, so SwiftLint skips them. The license is in `LICENSE-trafilatura`.

Before any production use, the fork should move to the DuckDuckGo organization or the binary should be hosted on DuckDuckGo infrastructure.

## Apps

Both apps use the `readerMode` feature flag.

- iOS samples the visible tab's HTML every three seconds until an article is offered, then stops until navigation, a URL change, web process termination, or a flag change. Reader Mode appears in the browsing menu above Find in Page. The reader is a full-screen, nonpersistent WKWebView with JavaScript disabled that applies the tab's tracker block lists and uses the article URL as its base, so site-specific rules match the original page.
- macOS extracts once when a main-frame navigation finishes. Reader Mode is available from the address bar button and View > Show Reader (Cmd-Shift-R), and replaces the tab's web view while active.

Links in the reader open in the original tab; in-page links stay in the reader.
