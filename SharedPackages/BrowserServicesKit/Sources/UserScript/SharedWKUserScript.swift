//
//  SharedWKUserScript.swift
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

import Foundation
import WebKit

/// A user script source with one `WKUserScript` that every `WKUserContentController` installing it shares.
///
/// Wrapping a source for injection copies and hashes it, and each `WKUserScript` keeps its own copy of the source,
/// which adds up for sources around 1 MB that every tab installs. `WKUserScript` is immutable, and each
/// `WKUserContentController` keeps its own list of the scripts added to it, so one instance can be added to,
/// and removed from, any number of controllers independently.
public final class SharedWKUserScript: @unchecked Sendable {

    public let source: String
    private let injectionTime: WKUserScriptInjectionTime
    private let forMainFrameOnly: Bool
    private let requiresRunInPageContentWorld: Bool

    private let lock = NSLock()
    /// The wrapped source, kept only until `wkUserScript` holds it.
    private var preparedSource: String?
    private var wkUserScript: WKUserScript?

    public init(source: String,
                injectionTime: WKUserScriptInjectionTime,
                forMainFrameOnly: Bool,
                requiresRunInPageContentWorld: Bool) {
        self.source = source
        self.injectionTime = injectionTime
        self.forMainFrameOnly = forMainFrameOnly
        self.requiresRunInPageContentWorld = requiresRunInPageContentWorld
    }

    /// Wraps the source for injection now, so that making the `WKUserScript` later on the main thread only creates it.
    ///
    /// Call this from a background thread.
    public func prepare() {
        guard lock.withLock({ wkUserScript == nil && preparedSource == nil }) else { return }
        // Wrapping hashes the whole source, so keep it outside the lock the main thread may be waiting on
        let preparedSource = UserScriptSourcePreparation.prepare(source)
        lock.withLock {
            if wkUserScript == nil, self.preparedSource == nil {
                self.preparedSource = preparedSource
            }
        }
    }

    /// The shared `WKUserScript`, wrapping the source off the main thread first if that hasn't happened yet.
    public func makeWKUserScript() async -> WKUserScriptBox {
        await Task.detached(priority: .userInitiated) { [self] in prepare() }.value
        return await WKUserScriptBox(wkUserScript: makeWKUserScriptSync())
    }

    /// The shared `WKUserScript`, wrapping the source on the calling thread if that hasn't happened yet.
    @MainActor
    public func makeWKUserScriptSync() -> WKUserScript {
        lock.withLock {
            if let wkUserScript {
                return wkUserScript
            }
            let preparedSource = preparedSource ?? UserScriptSourcePreparation.prepare(source)
            let wkUserScript = UserScriptSourcePreparation.makeWKUserScript(from: preparedSource,
                                                                            injectionTime: injectionTime,
                                                                            forMainFrameOnly: forMainFrameOnly,
                                                                            requiresRunInPageContentWorld: requiresRunInPageContentWorld).wkUserScript
            self.wkUserScript = wkUserScript
            self.preparedSource = nil
            return wkUserScript
        }
    }
}
