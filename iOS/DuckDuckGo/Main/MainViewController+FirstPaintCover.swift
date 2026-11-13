//
//  MainViewController+FirstPaintCover.swift
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

import UIKit
import Bookmarks
import Core
import FeatureFlags_iOS
import PrivacyConfig
import Suggestions

extension MainViewController {

    /// Takes over from the input panel before it hides, so the previous page never shows after a typed submit.
    func prepareFirstPaintCover(forQuery query: String) {
        guard let url = URL.makeSearchURL(query: query, useUnifiedLogic: isUnifiedURLPredictionEnabled, queryContext: currentTab?.url) else { return }
        prepareFirstPaintCover(forSubmitting: url)
    }

    func prepareFirstPaintCover(forSuggestion suggestion: Suggestion) {
        switch suggestion {
        case .phrase(let phrase):
            guard let url = URL.makeSearchURL(query: phrase, useUnifiedLogic: isUnifiedURLPredictionEnabled, forceSearchQuery: true) else { return }
            prepareFirstPaintCover(forSubmitting: url)
        case .website(let url) where !url.isBookmarklet():
            prepareFirstPaintCover(forSubmitting: url)
        default:
            return
        }
    }

    /// Reads the results page colour from the tab preview it already renders; once per appearance.
    func learnSearchPageColorIfNeeded(from tab: TabViewController, preview: UIImage) {
        let style = traitCollection.userInterfaceStyle
        guard Self.coversSearchSubmit(isLargeWidth: AppWidthObserver.shared.isLargeWidth, featureFlagger: featureFlagger),
              tab === currentTab,
              tab.url?.isDuckDuckGoSearch == true,
              searchPageColorMemory.needsSample(for: style) else { return }
        searchPageColorMemory.record(preview: preview, for: style)
    }

    /// Keeps the header of the results page just shown, to stand in for the next one while it loads.
    func learnSearchPageHeader(from tab: TabViewController) {
        let style = traitCollection.userInterfaceStyle
        guard tab === currentTab,
              let url = tab.url,
              Self.learnsSearchPageHeader(from: url, isFireTab: tab.tabModel.fireTab, isLargeWidth: AppWidthObserver.shared.isLargeWidth, featureFlagger: featureFlagger) else { return }
        let generation = searchPageHeaderMemory.generation
        tab.captureSearchPageHeader { [weak self] header in
            guard let self, let header, self.traitCollection.userInterfaceStyle == style else { return }
            self.searchPageHeaderMemory.record(header, for: style, capturedIn: generation)
        }
    }

    /// iPhone layout only, which includes narrow iPad windows; the large-width iPad layout keeps the plain submit.
    static func coversSearchSubmit(isLargeWidth: Bool, featureFlagger: FeatureFlagger) -> Bool {
        !isLargeWidth && featureFlagger.isFeatureOn(.searchSubmitPageCover)
    }

    /// Websites keep the plain cover; only the results page has a known shape.
    static func showsSearchResultsSkeleton(for url: URL) -> Bool {
        url.isDuckDuckGoSearch
    }

    /// Fire tabs are meant to leave no trace, so their results never teach the header.
    static func learnsSearchPageHeader(from url: URL, isFireTab: Bool, isLargeWidth: Bool, featureFlagger: FeatureFlagger) -> Bool {
        !isFireTab
            && coversSearchSubmit(isLargeWidth: isLargeWidth, featureFlagger: featureFlagger)
            && showsSearchResultsSkeleton(for: url)
            && isAllResultsPage(url)
    }

    /// Other verticals, such as Images, select a different tab and drop the filters.
    static func isAllResultsPage(_ url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let vertical = items.first { $0.name == "ia" }?.value
        return (vertical == nil || vertical == "web") && !items.contains { $0.name == "iax" || $0.name == "iaxm" }
    }

    private func prepareFirstPaintCover(forSubmitting url: URL) {
        // Other schemes, such as mailto:, never load in the tab.
        guard Self.coversSearchSubmit(isLargeWidth: AppWidthObserver.shared.isLargeWidth, featureFlagger: featureFlagger),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let tab = currentTab, tab.link != nil, !tab.isAITab,
              !Self.isSameDocument(url, as: tab.url),
              aiBoundaryDecision(for: url) == .loadInPlace else { return }

        var handoff = FirstPaintCover.Handoff()
        let panel: UIView? = viewCoordinator.unifiedInputContentContainer
        if let panel, panel.window != nil, !panel.isHidden, panel.alpha > 0,
           let snapshot = panel.snapshotView(afterScreenUpdates: false) {
            handoff.exitSnapshot = snapshot
            handoff.exitSnapshotWindowFrame = panel.convert(panel.bounds, to: nil)
        }
        handoff.destinationColor = expectedPageBackgroundColor(for: url)
        handoff.showsSearchResultsSkeleton = Self.showsSearchResultsSkeleton(for: url)
        if handoff.showsSearchResultsSkeleton {
            handoff.searchResultsHeader = searchPageHeaderMemory.header(for: traitCollection.userInterfaceStyle,
                                                                        width: tab.webView?.bounds.width ?? 0)
            // Holding for the first result keeps the half-built tabs row from flashing in over the remembered one.
            handoff.isContentReady = { [weak tab] completion in
                guard let tab else { return completion(true) }
                tab.checkSearchResultsShowing(completion: completion)
            }
        }
        tab.coverPageUntilFirstPaint(handoff: handoff)
    }

    /// A fragment change on the current page scrolls in place and loads nothing.
    static func isSameDocument(_ url: URL, as current: URL?) -> Bool {
        guard url.fragment != nil, let current,
              var target = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var page = URLComponents(url: current, resolvingAgainstBaseURL: false) else { return false }
        target.fragment = nil
        page.fragment = nil
        return target.url == page.url
    }

    private func expectedPageBackgroundColor(for url: URL) -> UIColor? {
        guard url.isDuckDuckGoSearch else { return nil }
        return searchPageColorMemory.color(for: traitCollection.userInterfaceStyle)
    }
}
