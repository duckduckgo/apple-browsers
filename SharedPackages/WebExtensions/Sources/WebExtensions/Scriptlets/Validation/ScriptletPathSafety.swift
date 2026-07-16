//
//  ScriptletPathSafety.swift
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

/// Path-traversal guardrails for scriptlet names.
///
/// Scriptlet names originate from a remote manifest and are used as relative
/// filesystem paths. Without validation, a crafted name such as `../../evil.js`
/// or `/etc/passwd` would cause writes to escape the intended directory.
enum ScriptletPathSafety {

    /// Rejects names that are empty, absolute, contain `.` / `..` segments, or contain a NUL byte.
    static func validateName(_ name: String) throws {
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              !name.contains("\0") else {
            throw ScriptletError.invalidName(name: name)
        }

        let segments = name.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.allSatisfy({ $0 != ".." && $0 != "." }) else {
            throw ScriptletError.invalidName(name: name)
        }
    }

    /// Verifies that `url`, after standardization, resolves inside `base`.
    /// Catches traversal that survives syntactic checks (e.g. via symlinks or
    /// edge-case URL behavior) and acts as a second line of defense.
    static func ensureContained(_ url: URL, within base: URL, name: String) throws {
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedBase = base.standardizedFileURL.resolvingSymlinksInPath()
        let urlPath = resolvedURL.path
        let basePath = resolvedBase.path
        guard urlPath == basePath || urlPath.hasPrefix(basePath + "/") else {
            throw ScriptletError.pathEscapesBase(name: name)
        }
    }
}
