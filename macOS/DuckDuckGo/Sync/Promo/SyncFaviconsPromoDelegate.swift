//
//  SyncFaviconsPromoDelegate.swift
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

import AppKit
import Combine
import DDGSync
import Foundation
import PrivacyConfig
import SyncUI_macOS

/// Presents the "Download Missing Icons?" dialog through the promo queue, offering to turn on
/// automatic favicon fetching for bookmarks synced from other devices.
///
/// Shown only while the promo's feature flag is on, Sync UI is enabled, favicons fetching isn't
/// already on, and the user is syncing with 2+ devices; confirming or dismissing both permanently
/// retire the promo (there is no legacy "remind me later" behavior to preserve).
final class SyncFaviconsPromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing?
    private let syncBookmarksAdapter: SyncBookmarksAdapter?
    private let windowControllersManager: WindowControllersManagerProtocol

    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var viewModel: FaviconsFetcherOnboardingViewModel?
    private var windowController: NSWindowController?
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)

    init(featureFlagger: FeatureFlagger,
         syncService: DDGSyncing?,
         syncBookmarksAdapter: SyncBookmarksAdapter?,
         windowControllersManager: WindowControllersManagerProtocol) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.syncBookmarksAdapter = syncBookmarksAdapter
        self.windowControllersManager = windowControllersManager
        refreshEligibility()
    }

    var isEligible: Bool { computeEligibility() }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func refreshEligibility() {
        isEligibleSubject.send(computeEligibility())
    }

    private func computeEligibility() -> Bool {
        guard featureFlagger.isFeatureOn(.promoQueueSyncFaviconsPromo) else { return false }
        guard let syncService, let syncBookmarksAdapter else { return false }
        return syncService.featureFlags.contains(.userInterface)
            && !syncBookmarksAdapter.isFaviconsFetchingEnabled
            && syncBookmarksAdapter.isEligibleForFaviconsFetcherOnboarding
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        // Migration: retire for anyone who already saw (and dismissed, either way) the pre-Promo-Queue
        // "Download Missing Icons?" dialog, recorded by this now-read-only legacy flag.
        if !force, UserDefaultsWrapper(key: .syncDidPresentFaviconsFetcherOnboarding, defaultValue: false).wrappedValue {
            return .retired
        }

        guard let parentWindow = windowControllersManager.lastKeyMainWindowController?.window else {
            return .noChange
        }

        let viewModel = FaviconsFetcherOnboardingViewModel()
        let windowController = FaviconsFetcherOnboardingViewController(viewModel).wrappedInWindowController()

        guard let window = windowController.window else {
            return .noChange
        }

        self.viewModel = viewModel
        self.windowController = windowController

        return await withCheckedContinuation { continuation in
            showContinuation = continuation

            viewModel.onDismiss = { [weak self] in
                guard let self else { return }
                self.resolve(with: self.dismissResult(enableFaviconsFetching: viewModel.isFaviconsFetchingEnabled))
            }

            Task { @MainActor in
                parentWindow.beginSheet(window)
            }
        }
    }

    @MainActor
    func hide() {
        resolve(with: .noChange)
    }

    /// Applies the "Keep Bookmarks Icons Updated" side effect (if chosen) and returns the result the
    /// session should resolve with. Internal (rather than private) so the one-shot resolution semantics
    /// can be tested directly without driving the actual sheet.
    func dismissResult(enableFaviconsFetching: Bool) -> PromoResult {
        guard enableFaviconsFetching else { return .ignored() }
        syncBookmarksAdapter?.isFaviconsFetchingEnabled = true
        syncService?.scheduler.notifyDataChanged()
        return .actioned
    }

    private func resolve(with result: PromoResult) {
        guard let continuation = showContinuation else { return }
        showContinuation = nil
        tearDown()
        continuation.resume(returning: result)
    }

    private func tearDown() {
        if let window = windowController?.window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        }
        viewModel = nil
        windowController = nil
    }
}
