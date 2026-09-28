//
//  WebKitTestBootstrap.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

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
