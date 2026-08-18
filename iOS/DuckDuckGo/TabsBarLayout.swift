//
//  TabsBarLayout.swift
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

import CoreGraphics

/// Single source of truth for the tabs strip's per-tab width and add-tab-button placement, so the
/// two can never derive inconsistent thresholds from the same stripWidth/tabsCount independently.
struct TabsBarLayout {

    let itemWidth: CGFloat
    let isFloored: Bool
    let addTabButtonLeadingOffset: CGFloat
    let addTabButtonContentInsetRight: CGFloat

    init(stripWidth: CGFloat, tabsCount: Int, minItemWidth: CGFloat, maxItemWidth: CGFloat,
         buttonWidth: CGFloat, buttonGap: CGFloat) {
        guard stripWidth > 0 else {
            itemWidth = 0
            isFloored = false
            addTabButtonLeadingOffset = 0
            addTabButtonContentInsetRight = 0
            return
        }

        let reservedWidth = max(0, stripWidth - buttonWidth - buttonGap)
        itemWidth = Self.itemWidth(availableWidth: reservedWidth, visibleItems: tabsCount,
                                    minWidth: minItemWidth, maxWidth: maxItemWidth)
        isFloored = itemWidth > 0 && itemWidth <= minItemWidth

        let contentWidth = CGFloat(tabsCount) * itemWidth
        addTabButtonLeadingOffset = isFloored ? max(0, stripWidth - buttonWidth) : contentWidth + buttonGap
        addTabButtonContentInsetRight = isFloored ? buttonWidth + buttonGap : 0
    }

    /// Equal share of the strip, capped at `maxWidth` then floored at `minWidth` (floor wins).
    static func itemWidth(availableWidth: CGFloat, visibleItems: Int, minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard visibleItems > 0 else { return 0 }
        var width = availableWidth / CGFloat(visibleItems)
        width = min(width, maxWidth)
        width = max(width, minWidth)
        return width
    }
}
