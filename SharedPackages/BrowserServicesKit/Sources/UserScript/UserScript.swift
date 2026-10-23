//
//  UserScript.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import CryptoKit

public struct WKUserScriptBox: @unchecked Sendable {
    public let wkUserScript: WKUserScript
}

/// When a script that runs in subframes starts in a blank subframe: one with no `src` (or `about:blank`) and no `srcdoc`,
/// including frames the page writes into. Pages can create hundreds of these, and most never touch anything a script
/// protects, so holding a script back in them saves the memory it would keep in each.
public enum BlankFrameStart: Sendable {
    /// As soon as the frame is created, as in any other frame.
    case immediately
    /// When the frame first reads an API that Content Scope Scripts protects, or its document is opened or written to.
    /// The read that starts it gets the value from the protected API. For page-world Content Scope Scripts.
    case onProtectedAPIAccess
    /// When the frame's document has content.
    case onContent
    /// When the frame's document has a form field.
    case onFormField
}

public protocol UserScript: WKScriptMessageHandler {

    var source: String { get }
    var injectionTime: WKUserScriptInjectionTime { get }
    var forMainFrameOnly: Bool { get }
    var requiresRunInPageContentWorld: Bool { get }
    var blankFrameStart: BlankFrameStart { get }

    var messageNames: [String] { get }

    func makeWKUserScript() async -> WKUserScriptBox

}

extension UserScript {

    static public var requiresRunInPageContentWorld: Bool {
        return false
    }

    public var requiresRunInPageContentWorld: Bool {
        return false
    }

    public var blankFrameStart: BlankFrameStart {
        return .immediately
    }

    @available(macOS 11.0, iOS 14.0, *)
    @MainActor
    static func getContentWorld(_ requiresRunInPageContentWorld: Bool) -> WKContentWorld {
        if requiresRunInPageContentWorld {
            return .page
        }
        return .defaultClient
    }

    @available(macOS 11.0, iOS 14.0, *)
    @MainActor
    public func getContentWorld() -> WKContentWorld {
        return Self.getContentWorld(requiresRunInPageContentWorld)
    }

    /// Loads a JavaScript file from the given bundle and applies placeholder replacements.
    ///
    /// The raw file content is cached in memory for the process lifetime.
    /// Only suitable for immutable bundle resources. Replacements are applied
    /// fresh on each call against the cached template.
    public static func loadJS(_ jsFile: String, from bundle: Bundle, withReplacements replacements: [String: String] = [:]) throws -> String {
        let js = try JSFileCache.content(forFile: jsFile, in: bundle)

        return js.applyingReplacements(replacements)
    }

    fileprivate nonisolated static func prepareScriptSource(from source: String, blankFrameStart: BlankFrameStart = .immediately) -> String {
        let hash = SHA256.hash(data: Data(source.utf8)).hashValue

        // This prevents the script being executed twice which appears to be a WKWebKit issue for about:blank frames when the location changes
        guard blankFrameStart != .immediately else {
            return """
            (() => {
                if (window.navigator._duckduckgoloader_ && window.navigator._duckduckgoloader_.includes('\(hash)')) {return}
                \(source)
                window.navigator._duckduckgoloader_ = window.navigator._duckduckgoloader_ || [];
                window.navigator._duckduckgoloader_.push('\(hash)')
            })()
            """
        }

        // In a blank subframe the source is held as an unrun function: JavaScriptCore only pre-parses it, so it creates
        // nothing in the frame until something starts it
        return """
        (() => {
            const isLoaded = () => Boolean(window.navigator._duckduckgoloader_ && window.navigator._duckduckgoloader_.includes('\(hash)'));
            const markLoaded = () => {
                window.navigator._duckduckgoloader_ = window.navigator._duckduckgoloader_ || [];
                window.navigator._duckduckgoloader_.push('\(hash)');
            };
            if (isLoaded()) {return}
            const run = () => {
                \(source)
            };
            \(BlankFrameDeferral.isBlankSubframe)
            if (!isBlankSubframe) {
                run();
                markLoaded();
                return;
            }
            \(BlankFrameDeferral.start(blankFrameStart))
        })()
        """
    }

    @MainActor
    fileprivate static func makeWKUserScript(from source: String,
                                             injectionTime: WKUserScriptInjectionTime,
                                             forMainFrameOnly: Bool,
                                             requiresRunInPageContentWorld: Bool = false) -> WKUserScriptBox {
        if #available(macOS 11.0, iOS 14.0, *) {
            let contentWorld = getContentWorld(requiresRunInPageContentWorld)
            return .init(wkUserScript: WKUserScript(source: source,
                                                    injectionTime: injectionTime,
                                                    forMainFrameOnly: forMainFrameOnly,
                                                    in: contentWorld))
        } else {
            return .init(wkUserScript: WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly))
        }
    }

    public func makeWKUserScript() async -> WKUserScriptBox {
        let source = await Task.detached { [source, blankFrameStart] in Self.prepareScriptSource(from: source, blankFrameStart: blankFrameStart) }.result.get()
        return await Self.makeWKUserScript(from: source,
                                           injectionTime: injectionTime,
                                           forMainFrameOnly: forMainFrameOnly,
                                           requiresRunInPageContentWorld: requiresRunInPageContentWorld)
    }

    @MainActor
    public func makeWKUserScriptSync() -> WKUserScript {
        return Self.makeWKUserScript(from: Self.prepareScriptSource(from: source, blankFrameStart: blankFrameStart),
                                     injectionTime: injectionTime,
                                     forMainFrameOnly: forMainFrameOnly,
                                     requiresRunInPageContentWorld: requiresRunInPageContentWorld).wkUserScript
    }

}

extension StaticUserScript {

    @MainActor
    public static func makeWKUserScript() -> WKUserScript {
        return makeWKUserScript(from: prepareScriptSource(from: source),
                                injectionTime: injectionTime,
                                forMainFrameOnly: forMainFrameOnly).wkUserScript
    }

}

public enum UserScriptError: LocalizedError {
    case failedToLoadJS(jsFile: String, error: Error)

    public var errorDescription: String? {
        switch self {
        case let .failedToLoadJS(jsFile, error):
            return "Failed to load \(jsFile).js: \(error as NSError)"
        }
    }
}
