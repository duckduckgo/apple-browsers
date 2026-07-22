import WebKit

/// `WKScriptMessage()`'s designated initializer is `@MainActor`-isolated, and — more importantly —
/// its `dealloc` schedules teardown onto WebKit's main run loop, machinery that isn't safely set up
/// until some real WebKit object (e.g. a `WKWebView`) has already been created in the process.
/// Deallocating a bare `WKScriptMessage()` before that bootstrap has happened crashes with `SIGSEGV`
/// inside `-[WKScriptMessage dealloc]` (`WebCoreObjCScheduleDeallocateOnMainRunLoop`) — exactly what
/// happens when these `async` swift-testing tests construct one, since the test body runs on the
/// Swift concurrency cooperative thread pool rather than the app's main thread.
///
/// Call `bootstrapWebKitForTesting()` once before constructing any bare `WKScriptMessage()` in a test.
@MainActor
private enum WebKitTestBootstrap {
    static let didBootstrap: Void = { _ = WKWebView(frame: .zero) }()
}

func bootstrapWebKitForTesting() async {
    await MainActor.run { _ = WebKitTestBootstrap.didBootstrap }
}
