//
//  DroppedContentPolicy.swift
//  DuckDuckGo
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

/// A policy that determines which drag-and-drop content the browser can load.
///
/// Use this policy to filter out dropped content with a script scheme, such as `javascript:`,
/// before loading it, so that a web page can't use a drop to run script on another site.
enum DroppedContentPolicy {

    /// The schemes whose URLs run script instead of navigating.
    private static let scriptSchemes = ["javascript:"]

    /// Returns a Boolean value that indicates whether the browser can load the specified dropped URL.
    ///
    /// - Parameter url: The URL that the user dropped.
    /// - Returns: `true` if the browser can load `url`; otherwise, `false`.
    static func allows(_ url: URL) -> Bool {
        allows(url.absoluteString)
    }

    /// Returns a Boolean value that indicates whether the browser can load the specified dropped text.
    ///
    /// The browser loads dropped text in the current tab as a search query or an address. This method rejects text that begins with a script scheme.
    ///
    /// - Parameter text: The text that the user dropped.
    /// - Returns: `true` if the browser can load `text`; otherwise, `false`.
    static func allows(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !scriptSchemes.contains { value.hasPrefix($0) }
    }
}
