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

    func estimatedContentHeight(
        headerDataSource: BrowsingMenuHeaderDataSource,
        verticalSizeClass: UIUserInterfaceSizeClass?
    ) -> CGFloat {
        let isCompact = verticalSizeClass == .compact
        return estimatedContentHeight(
            includesWebsiteInfo: headerDataSource.isHeaderVisible,
            includesCloseButtonHeader: isCompact && !headerDataSource.isHeaderVisible
        )
    }

    private func estimatedContentHeight(includesWebsiteInfo: Bool, includesCloseButtonHeader: Bool) -> CGFloat {
        typealias Metrics = BrowsingMenuSheetView.Metrics

        let headerFont = UIFont.daxCaption()
        let rowFont = UIFont.daxBodyRegular()
        let iconHeight = Metrics.headerButtonIconSize

        let headerContentHeight = iconHeight + Metrics.headerButtonIconTextSpacing + headerFont.lineHeight
        let headerButtonsHeight = headerItems.isEmpty ? 0 : headerContentHeight + (Metrics.headerButtonVerticalPadding * 2)

        // Header height depends on whether website info is shown or just the close button
        let websiteHeaderHeight: CGFloat
        if includesWebsiteInfo {
            websiteHeaderHeight = Metrics.websiteHeaderHeight
        } else if includesCloseButtonHeader {
            websiteHeaderHeight = Metrics.closeButtonHeaderHeight
        } else {
            websiteHeaderHeight = 0
        }

        let minTotalVerticalPadding: CGFloat = 16
        let rowHeight = max(Metrics.defaultListRowHeight, rowFont.lineHeight + minTotalVerticalPadding)

        let itemCount = sections.reduce(0) { $0 + $1.items.count }
        let menuSectionCount = sections.count

        // When header section has content (header buttons), there's an additional gap
        // between it and the first menu section
        let hasHeaderSectionContent = !headerItems.isEmpty
        let sectionGapsCount = hasHeaderSectionContent ? menuSectionCount : max(0, menuSectionCount - 1)

        return websiteHeaderHeight
            + headerButtonsHeight
            + (CGFloat(itemCount) * rowHeight)
            + (CGFloat(sectionGapsCount) * Metrics.listSectionSpacing)
            + Metrics.listTopPadding
            + Metrics.grabberHeight
    }
}
