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
    /// Offer New Chat and Chats, plus Ask About Page on web tabs.
    case menu
    /// Open the contextual sheet, restoring any chat already in progress.
    case contextualSheet
    /// Close whichever contextual surface is already showing.
    case dismissContextualSurface
    /// Open Duck.ai the way the button did before contextual mode.
    case legacyDuckAI

    /// Home tabs offer the menu when chat history is available. Web tabs retain contextual
    /// restoration and require floating input for the Ask About Page action.
    ///
    /// - Parameter isIPadChromeMenuButtonAvailable: iPad has no floating input, so its chrome menu
    ///   button brings the menu on its own; there, Ask About Page opens the sheet instead.
    /// - Parameter hasChatToReopen: A conversation this tab can go back to, whether it is still live
    ///   or was persisted by an earlier launch. Reopen this tab's conversation directly rather than
    ///   requiring the user to find it in Chats.
    static func resolve(isContextualModeAvailable: Bool,
                        isFloatingInputAvailable: Bool,
                        isIPadChromeMenuButtonAvailable: Bool = false,
                        isHomeTab: Bool,
                        isChatHistoryAvailable: Bool,
                        hasChatToReopen: Bool,
                        isContextualSurfacePresented: Bool) -> DuckAIAddressBarEntry {
        if isHomeTab {
            return isChatHistoryAvailable ? .menu : .legacyDuckAI
        }
        guard isContextualModeAvailable else { return .legacyDuckAI }
        guard !isContextualSurfacePresented else { return .dismissContextualSurface }
        guard isFloatingInputAvailable || isIPadChromeMenuButtonAvailable, !hasChatToReopen else { return .contextualSheet }
        return .menu
    }

    /// A surface is open, or this tab has a chat to come back to. Beside `resolve` and over the same
    /// inputs so the glyph can't contradict what a tap does.
    static func showsContextualGlyph(isContextualModeAvailable: Bool,
                                     isHomeTab: Bool,
                                     hasChatToReopen: Bool,
                                     isContextualSurfacePresented: Bool) -> Bool {
        guard isContextualModeAvailable, !isHomeTab else { return false }
        return hasChatToReopen || isContextualSurfacePresented
    }
}
