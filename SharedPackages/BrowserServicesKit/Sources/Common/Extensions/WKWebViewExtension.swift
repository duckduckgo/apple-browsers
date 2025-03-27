//
//  WKWebViewExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public extension WKWebView {

    /// Calling this method is equivalent to calling `evaluateJavaScript:inFrame:inContentWorld:completionHandler:` with:
    /// - A `frame` value of `nil` to represent the main frame
    /// - A `contentWorld` value of `WKContentWorld.pageWorld`
    @MainActor func evaluateJavaScript<T>(_ script: String) async throws -> T? {
        try await withUnsafeThrowingContinuation { c in
            evaluateJavaScript(script) { result, error in
                if let error {
                    c.resume(with: .failure(error))
                } else {
                    c.resume(with: .success(result as? T))
                }
            }
        }
    }

    // This is meant to cause the `Ambiguous use` error, because async `evaluateJavaScript(_) -> Any`
    // call will crash when its result is `nil`.
    // Use typed `try await evaluateJavaScript(script) as Void?` (or other type you need),
    // or even better `try await evaluateJavaScript(script, in: nil, in: .page|.defaultClient) -> Any?` (available in macOS 12/iOS 15)
    @available(*, deprecated, message: "Use `try await evaluateJavaScript(script) as Void?` instead.")
    @MainActor func evaluateJavaScript(_ script: String) async throws {
        assertionFailure("Use `try await evaluateJavaScript(script) as Void?` instead of `try await evaluateJavaScript(script)` as it will crash in runtime")
        try await evaluateJavaScript(script) as Void?
    }

}
