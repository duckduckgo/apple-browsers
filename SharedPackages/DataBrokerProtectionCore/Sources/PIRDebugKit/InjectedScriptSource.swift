//
//  InjectedScriptSource.swift
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

/// Source of the injected `contentScopeIsolated.js` for a debug run.
///
/// `.bundled` uses the `ContentScopeScripts` SPM resource (via the cache). `.file(url)` is mapped
/// to the runner's `customContentScopeJSURL` seam, which reads the file fresh per init and bypasses
/// `JSFileCache` while applying the same replacements.
public enum InjectedScriptSource: Equatable {
    case bundled
    case file(URL)

    /// The URL passed to the `customContentScopeJSURL` seam (`nil` for `.bundled`).
    public var customContentScopeJSURL: URL? {
        switch self {
        case .bundled: return nil
        case .file(let url): return url
        }
    }
}
