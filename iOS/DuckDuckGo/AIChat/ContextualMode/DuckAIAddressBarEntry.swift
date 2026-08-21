//
//  DuckAIAddressBarEntry.swift
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

/// What the address-bar Duck.ai button does for the current tab and session.
enum DuckAIAddressBarEntry: Equatable {
    /// Offer New Chat or Ask About Page.
    case menu
    /// Open the contextual sheet, restoring any chat already in progress.
    case contextualSheet
    /// Close whichever contextual surface is already showing.
    case dismissContextualSurface
    /// Open Duck.ai the way the button did before contextual mode.
    case legacyDuckAI

    /// The menu is only offered where the New Chat versus Ask About Page choice is meaningful: a web
    /// page with no chat to return to and nothing already open.
    ///
    /// - Parameter hasChatToReopen: A conversation this tab can go back to, whether it is still live
    ///   or was persisted by an earlier launch. Neither menu action reopens one, so offering the menu
    ///   here would strand it.
    static func resolve(isContextualModeAvailable: Bool,
                        isFloatingInputAvailable: Bool,
                        isHomeTab: Bool,
                        hasChatToReopen: Bool,
                        isContextualSurfacePresented: Bool) -> DuckAIAddressBarEntry {
        guard isContextualModeAvailable, !isHomeTab else { return .legacyDuckAI }
        guard !isContextualSurfacePresented else { return .dismissContextualSurface }
        guard isFloatingInputAvailable, !hasChatToReopen else { return .contextualSheet }
        return .menu
    }

    /// Whether the button wears its contextual glyph rather than the plain Duck.ai one: a surface is
    /// open, or this tab has a chat to come back to. Kept beside `resolve` and over the same inputs so
    /// the glyph can't contradict what a tap does — the enum alone can't answer it, because
    /// `.contextualSheet` covers both having a chat and the floating input being unavailable.
    static func showsContextualGlyph(isContextualModeAvailable: Bool,
                                     isHomeTab: Bool,
                                     hasChatToReopen: Bool,
                                     isContextualSurfacePresented: Bool) -> Bool {
        guard isContextualModeAvailable, !isHomeTab else { return false }
        return hasChatToReopen || isContextualSurfacePresented
    }
}
