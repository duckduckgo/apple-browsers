//
//  URL+AppUpdater.swift
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

/// URL constants for the AppUpdater package.
public extension URL {

    /// The App Store listing URL for DuckDuckGo Privacy Browser.
    ///
    /// Used by App Store update flow to direct users to download updates.
    static var appStore: URL {
        URL(string: "https://apps.apple.com/app/duckduckgo-privacy-browser/id663592361")!
    }

    /// The internal release notes page URL.
    ///
    /// Used by Sparkle update flow to display release notes in a dedicated tab.
    /// This is a custom `duck://` scheme URL handled by `DuckURLSchemeHandler`.
    static var releaseNotes: URL {
        URL(string: "duck://release-notes")!
    }
}
