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

    private var currentFaviconTaskDomain: String?
    private var currentFaviconTask: Task<Void, Error>?

    func update(
        dataSource: BrowsingMenuHeaderDataSource,
        isFeatureEnabled: Bool,
        isNewTabPage: Bool = false,
        isAITab: Bool = false,
        isError: Bool,
        hasLink: Bool,
        url: URL? = nil,
        title: String? = nil,
        easterEggLogoURL: String? = nil
    ) {
        let isHeaderVisible = isFeatureEnabled && !isNewTabPage && !isAITab && hasLink
        let isAIHeaderVisible = isFeatureEnabled && isAITab

        if isAIHeaderVisible {
            cancelRunningFaviconTask()
            dataSource.update(forAITab: UserText.duckAiFeatureName)
        } else if isHeaderVisible {

            let serpLogoURL = easterEggLogoURL.flatMap { URL(string: $0) }
            dataSource.update(title: isError ? nil : title, url: url, easterEggLogoURL: serpLogoURL)

            if serpLogoURL == nil {
                // No custom SERP logo - load regular favicon
                loadFavicon(for: url, into: dataSource)
            } else {
                cancelRunningFaviconTask()
            }
        } else {
            cancelRunningFaviconTask()
            dataSource.reset()
        }
    }

    private func cancelRunningFaviconTask() {
        currentFaviconTask?.cancel()
        currentFaviconTask = nil

        currentFaviconTaskDomain = nil
    }


    private func loadFavicon(for url: URL?, into dataSource: BrowsingMenuHeaderDataSource) {

        guard let domain = url?.host else {
            cancelRunningFaviconTask()
            return
        }

        // If there's already a running task for this same domain, let it continue.
        if let existingTask = currentFaviconTask, !existingTask.isCancelled, domain == currentFaviconTaskDomain {
            return
        }

        cancelRunningFaviconTask()
        currentFaviconTaskDomain = domain

        currentFaviconTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let result = FaviconsHelper.loadFaviconSync(
                forDomain: domain,
                usingCache: .tabs,
                useFakeFavicon: false
            )

            try Task.checkCancellation()

            await MainActor.run { [weak self] in
                if let favicon = result.image, !result.isFake {
                    dataSource.update(favicon: favicon)
                }

                self?.currentFaviconTask = nil
                self?.currentFaviconTaskDomain = nil
            }
        }
    }
}
