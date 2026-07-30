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
    /// page with no chat under way and nothing already open. With a chat going, the button reopens it.
    static func resolve(isContextualModeAvailable: Bool,
                        isFloatingInputAvailable: Bool,
                        isHomeTab: Bool,
                        hasActiveChat: Bool,
                        isContextualSurfacePresented: Bool) -> DuckAIAddressBarEntry {
        guard isContextualModeAvailable, !isHomeTab else { return .legacyDuckAI }
        guard !isContextualSurfacePresented else { return .dismissContextualSurface }
        guard isFloatingInputAvailable, !hasActiveChat else { return .contextualSheet }
        return .menu
    }
}
