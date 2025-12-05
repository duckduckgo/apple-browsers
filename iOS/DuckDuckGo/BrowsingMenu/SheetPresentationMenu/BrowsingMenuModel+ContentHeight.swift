//
//  BrowsingMenuModel+ContentHeight.swift
//  DuckDuckGo
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

import UIKit
import DesignResourcesKit

extension BrowsingMenuModel {

    var estimatedContentHeight: CGFloat {
        typealias Metrics = BrowsingMenuSheetView.Metrics

        let headerFont = UIFont.daxFootnoteRegular()
        let rowFont = UIFont.daxBodyRegular()
        let iconHeight: CGFloat = 24

        let headerContentHeight = iconHeight + Metrics.headerButtonIconTextSpacing + headerFont.lineHeight
        let headerHeight = headerItems.isEmpty ? 0 : headerContentHeight + (Metrics.headerButtonVerticalPadding * 2)

        let minTotalVerticalPadding: CGFloat = 16
        let rowHeight = max(Metrics.defaultListRowHeight, rowFont.lineHeight + minTotalVerticalPadding)

        // Footer text labels are only shown when there's fewer than 2 footer items
        let footerShowsLabels = footerItems.count < 2

        // `max` is used here because labels and icons are in HStack
        let footerContentHeight = max(iconHeight, (footerShowsLabels ? rowFont.lineHeight : 0))
        let footerHeight = footerContentHeight + (Metrics.footerButtonVerticalPadding * 2)

        let itemCount = sections.reduce(0) { $0 + $1.items.count }
        let menuSectionCount = sections.count

        // When header items are present, there's an additional
        // gap between the header section and the first menu section
        let sectionGapsCount = headerItems.isEmpty ? max(0, menuSectionCount - 1) : menuSectionCount

        return headerHeight
            + (CGFloat(itemCount) * rowHeight)
            + (CGFloat(sectionGapsCount) * Metrics.listSectionSpacing)
            + (footerItems.isEmpty ? 0 : footerHeight)
            + Metrics.listTopPadding
            + Metrics.grabberHeight
    }
}
