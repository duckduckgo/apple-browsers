//
//  UTIViewConfig.swift
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

/// Composable description of which card components are visible at any given time. Replaces the
/// previous boolean soup (`isExpanded` + `showToggle` + `alwaysShowToolbar`) with a single value
/// callers compose explicitly.
enum UnifiedToggleInputCardLayout: Equatable {
    /// Single-line slim pill with no surrounding accessories. Today its dimensions
    /// (44pt tall, 16pt corner radius, leading-aligned placeholder) mimic the regular
    /// omnibar, so the snap between the two reads as one continuous pill.
    case collapsed
    /// Single-line pill flanked by accessory buttons on either side (fire / voice on
    /// Duck.ai today). Slightly taller (48pt capsule) to match the accessory height.
    case flanked
    /// Multi-line card. Each component independently visible.
    case expanded(showsToggle: Bool, showsToolbar: Bool)

    var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    var showsToggle: Bool {
        if case .expanded(let showsToggle, _) = self { return showsToggle }
        return false
    }

    var showsToolbar: Bool {
        if case .expanded(_, let showsToolbar) = self { return showsToolbar }
        return false
    }
}

struct UTIViewConfig: Equatable {
    var cardLayout: UnifiedToggleInputCardLayout
    var cardPosition: UnifiedToggleInputCardPosition
    var usesOmnibarMargins: Bool
    var isToolbarSubmitHidden: Bool
    var inactiveAppearance: Bool
    var inputMode: TextEntryMode
    var isTopBarPosition: Bool
    /// True when the UTI is hosted by a Duck.ai tab.
    var isAITab: Bool
}
