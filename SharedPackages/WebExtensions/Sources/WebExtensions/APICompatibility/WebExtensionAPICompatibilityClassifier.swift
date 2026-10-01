//
//  WebExtensionAPICompatibilityClassifier.swift
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

/// Reduces what a page reports to a kind and an API path. Whatever cannot be reduced to an API path
/// is dropped, so nothing else (URLs, error text, arguments) can reach the log.
enum WebExtensionAPICompatibilityClassifier {

    struct Issue: Equatable {
        let kind: WebExtensionAPICompatibilityKind
        let api: String
    }

    private static let identifier = "[A-Za-z_$][A-Za-z0-9_$]*"
    private static let maximumPathLength = 128
    /// Values WebKit legitimately leaves undefined, so reading off them is not a missing API.
    private static let undefinedByDesign = "chrome.runtime.lastError"
    private static let apiRoots: Set<String> = ["chrome", "browser"]
    private static let globalObjects: Set<String> = ["globalThis", "self", "window"]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    // The messages JavaScriptCore and WebKit produce. WebKit rejects a call with "Invalid call to
    // <api>(). The '<parameter>' value is invalid, ..."; other "Invalid call to" errors are not about
    // the arguments, so they are not matched.
    private static let invalidCall = regex("Invalid call to (\\w[\\w$.]*)\\(\\)\\. The '[^']*' value is invalid")
    private static let undefinedObject = regex("undefined is not an object \\(evaluating '([^']+)'\\)")
    private static let notAFunction = regex("(\(identifier)(?:\\.\(identifier))+) is not a function\\. \\(In ")
    private static let pathPattern = regex("^\(identifier)(\\.\(identifier))*$")
    private static let permissionNamePattern = regex("^[A-Za-z][A-Za-z0-9_.-]{0,63}$")

    /// Classifies an error message; the message is not kept.
    static func classify(errorMessage: String) -> Issue? {
        if let path = firstCapture(of: invalidCall, in: errorMessage) {
            return chromePath(from: path, requiresRoot: false).map { Issue(kind: .invalidArgs, api: $0) }
        }
        if let chain = firstCapture(of: undefinedObject, in: errorMessage) {
            // The last segment is the one read off the undefined object, so the object is what is missing.
            guard let parent = chromePath(from: chain, requiresRoot: true, droppingLastSegment: true),
                  !isUndefinedByDesign(parent) else { return nil }
            return Issue(kind: .missing, api: parent)
        }
        if let chain = firstCapture(of: notAFunction, in: errorMessage) {
            guard let path = chromePath(from: chain, requiresRoot: true), !isUndefinedByDesign(path) else { return nil }
            return Issue(kind: .missing, api: path)
        }
        return nil
    }

    /// `chrome.runtime.lastError` is undefined unless the last call failed, so `lastError.message`
    /// throwing says nothing about the API.
    private static func isUndefinedByDesign(_ path: String) -> Bool {
        path == undefinedByDesign || path.hasPrefix(undefinedByDesign + ".")
    }

    /// Validates the API a page named itself: a permission (`permission:<name>`) or a path relative to `chrome`.
    static func issue(kind: WebExtensionAPICompatibilityKind, reportedAPI: String) -> Issue? {
        if reportedAPI.hasPrefix(permissionPrefix) {
            let name = String(reportedAPI.dropFirst(permissionPrefix.count))
            guard matches(permissionNamePattern, name) else { return nil }
            return Issue(kind: kind, api: reportedAPI)
        }
        return chromePath(from: reportedAPI, requiresRoot: false).map { Issue(kind: kind, api: $0) }
    }

    static let permissionPrefix = "permission:"

    /// Normalizes `browser.x.y`, `globalThis.chrome.x.y` and (without a root) `x.y` to `chrome.x.y`.
    private static func chromePath(from chain: String, requiresRoot: Bool, droppingLastSegment: Bool = false) -> String? {
        guard chain.count <= maximumPathLength, matches(pathPattern, chain) else { return nil }

        var segments = chain.split(separator: ".").map(String.init)
        if segments.count > 1, globalObjects.contains(segments[0]) {
            segments.removeFirst()
        }
        if let first = segments.first, apiRoots.contains(first) {
            segments.removeFirst()
        } else if requiresRoot {
            return nil
        }
        if droppingLastSegment {
            segments.removeLast()
        }
        guard !segments.isEmpty else { return nil }
        return (["chrome"] + segments).joined(separator: ".")
    }

    private static func matches(_ expression: NSRegularExpression, _ string: String) -> Bool {
        expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    private static func firstCapture(of expression: NSRegularExpression, in string: String) -> String? {
        guard let match = expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }

    /// Permissions the stub script provides itself, so a manifest asking for them lacks nothing.
    private static let permissionsProvidedByShims: Set<String> = ["privacy", "offscreen", "idle"]

    /// Permissions a manifest asks for that WebKit dropped because it does not implement them.
    /// Host patterns are not API permissions and are skipped, as are the ones the stub script provides.
    static func droppedPermissions(inManifest manifest: [String: Any], webKitPermissions: Set<String>) -> [String] {
        let declared = ["permissions", "optional_permissions"]
            .flatMap { manifest[$0] as? [String] ?? [] }
            .filter { !isHostPattern($0) && matches(permissionNamePattern, $0) }
        return Set(declared).subtracting(webKitPermissions).subtracting(permissionsProvidedByShims).sorted()
    }

    private static func isHostPattern(_ permission: String) -> Bool {
        permission == "<all_urls>" || permission.contains("://") || permission.hasPrefix("*")
    }
}
