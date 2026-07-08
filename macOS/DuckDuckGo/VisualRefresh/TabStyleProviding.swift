//
//  TabStyleProviding.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

protocol TabStyleProviding {
    var separatorColor: NSColor { get }
    var separatorHeight: CGFloat { get }

    var tabsScrollViewHeight: CGFloat { get }
    var pinnedTabsContainerViewHeight: CGFloat { get }
    var standardTabHeight: CGFloat { get }
    var pinnedTabHeight: CGFloat { get }
    var pinnedTabWidth: CGFloat { get }

    var shouldShowSShapedTab: Bool { get }
    var shouldShowTabSeparators: Bool { get }
    var selectedTabColor: NSColor { get }
    var hoverTabColor: NSColor { get }
    var isRoundedBackgroundPresentOnHover: Bool { get }
    var tabSpacing: CGFloat { get }
    var applyTabShadow: Bool { get }
    var standardTabCornerRadius: CGFloat { get }
    var tabButtonActionsSelectedCornerRadius: CGFloat { get }
    var tabButtonActionsHighlightedCornerRadius: CGFloat { get }
}

final class TabAnimationsStyleProvider: TabStyleProviding {
    private let palette: ThemeColors

    var separatorColor: NSColor { palette.surfaceDecorationTertiary }
    var selectedTabColor: NSColor { palette.surfacePrimary }
    var hoverTabColor: NSColor { palette.controlsFillPrimary }

    let separatorHeight: CGFloat = 16
    let tabsScrollViewHeight: CGFloat = 38
    let pinnedTabsContainerViewHeight: CGFloat = 38
    let standardTabHeight: CGFloat = 38
    let pinnedTabWidth: CGFloat = 38
    let pinnedTabHeight: CGFloat = 38
    let shouldShowSShapedTab = true
    let shouldShowTabSeparators = true
    let isRoundedBackgroundPresentOnHover = true
    let tabSpacing: CGFloat = 0
    let applyTabShadow: Bool = false
    let standardTabCornerRadius: CGFloat = 10.0
    let tabButtonActionsSelectedCornerRadius: CGFloat = 6
    let tabButtonActionsHighlightedCornerRadius: CGFloat = 4

    init(palette: ThemeColors) {
        self.palette = palette
    }
}

struct TabStyleProvidingFactory {

    static func buildStyleProvider(palette: ThemeColors) -> TabStyleProviding {
        TabAnimationsStyleProvider(palette: palette)
    }
}
