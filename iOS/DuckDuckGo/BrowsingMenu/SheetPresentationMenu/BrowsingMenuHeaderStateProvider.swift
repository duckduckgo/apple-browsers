//
//  BrowsingMenuHeaderStateProvider.swift
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
import UIKit
import Core

/// Provides header state updates for the browsing menu.
/// Reads already-computed values from OmniBar and Tab, then updates the data source.
final class BrowsingMenuHeaderStateProvider {

    private var currentFaviconRequestID: UUID?

    func update(
        dataSource: BrowsingMenuHeaderDataSource,
        isFeatureEnabled: Bool,
        isNewTabPage: Bool = false,
        isAITab: Bool = false,
        hasLink: Bool,
        url: URL? = nil,
        title: String? = nil,
        easterEggLogoURL: String? = nil
    ) {
        let isHeaderVisible = isFeatureEnabled && !isNewTabPage && !isAITab && hasLink
        let isAIHeaderVisible = isFeatureEnabled && isAITab

        dataSource.reset()

        if isAIHeaderVisible {
            dataSource.update(forAITab: UserText.duckAiFeatureName)
        } else if isWebsiteHeaderVisible {
            let logoURL = easterEggLogoURL.flatMap { URL(string: $0) }
            dataSource.update(title: title, url: url, easterEggLogoURL: logoURL)
            if logoURL == nil {
                loadFavicon(for: url, into: dataSource)
            }
        } else {
            currentFaviconRequestID = nil
        }
    }

    private func loadFavicon(for url: URL?, into dataSource: BrowsingMenuHeaderDataSource) {
        let requestID = UUID()
        currentFaviconRequestID = requestID

        guard let domain = url?.host else {
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = FaviconsHelper.loadFaviconSync(
                forDomain: domain,
                usingCache: .tabs,
                useFakeFavicon: false
            )

            await MainActor.run {
                guard self?.currentFaviconRequestID == requestID else { return }
                if let favicon = result.image, !result.isFake {
                    dataSource.update(favicon: favicon)
                }
            }
        }
    }
}
