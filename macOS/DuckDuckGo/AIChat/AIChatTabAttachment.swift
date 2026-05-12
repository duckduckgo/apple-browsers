//
//  AIChatTabAttachment.swift
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

import AppKit
import Foundation

/// A tab the user has attached as page-content context to the duck.ai omnibar prompt.
/// `id` is the tab's UUID (matching `AIChatTabMetadata.tabId`); on submit the duck.ai web
/// app uses this to fetch the page contents via the existing `getAIChatTabContent` bridge.
struct AIChatTabAttachment: Identifiable {
    /// The tab's UUID. Stable while the tab is open; lost when the tab is closed.
    let id: String
    let title: String
    let url: URL
    /// Resolved favicon for native rendering. `nil` when unavailable; the UI falls back to a
    /// generic page glyph in that case.
    let favicon: NSImage?
}

extension AIChatTabAttachment: Equatable {
    /// Compares attachments by id/title/url and uses *identity* for the favicon image.
    /// `NSImage` doesn't conform to `Equatable`, and the persistence layer needs to detect
    /// "did this list actually change" to skip redundant publisher emissions; identity is
    /// sufficient because we never mutate an `NSImage` instance once attached.
    static func == (lhs: AIChatTabAttachment, rhs: AIChatTabAttachment) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.url == rhs.url
            && lhs.favicon === rhs.favicon
    }
}
