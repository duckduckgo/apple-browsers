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
import Persistence
import PrivacyConfig
import SyncUI_macOS

struct SyncFaviconsPromoSettings: StoringKeys {
    let didPresentLegacyDialog = StorageKey<Bool>(UserDefaultsKeys.syncDidPresentFaviconsFetcherOnboarding,
                                                  assertionHandler: { _ in })
}

/// Presents the "Download Missing Icons?" dialog through the promo queue, offering to turn on
/// automatic favicon fetching for bookmarks synced from other devices.
final class SyncFaviconsPromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let syncService: DDGSyncing?
    private let syncBookmarksAdapter: SyncBookmarksAdapter?
    private let windowControllersManager: WindowControllersManagerProtocol
    private let storage: KeyedStorage<SyncFaviconsPromoSettings>

    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var viewModel: FaviconsFetcherOnboardingViewModel?
    private var windowController: NSWindowController?
    private var windowCloseObservers: [NSObjectProtocol] = []
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)

    init(featureFlagger: FeatureFlagger,
         syncService: DDGSyncing?,
         syncBookmarksAdapter: SyncBookmarksAdapter?,
         windowControllersManager: WindowControllersManagerProtocol,
         storage: KeyedStorage<SyncFaviconsPromoSettings>? = nil) {
        self.featureFlagger = featureFlagger
        self.syncService = syncService
        self.syncBookmarksAdapter = syncBookmarksAdapter
        self.windowControllersManager = windowControllersManager
        self.storage = storage ?? KeyedStorage(storage: UserDefaults.standard)
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
        if !force, storage.didPresentLegacyDialog == true {
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

            observeWindowClose([parentWindow, window])

            Task { @MainActor in
                parentWindow.beginSheet(window)
            }
        }
    }

    @MainActor
    func hide() {
        resolve(with: .noChange)
    }

    func dismissResult(enableFaviconsFetching: Bool) -> PromoResult {
        guard enableFaviconsFetching else { return .ignored() }
        syncBookmarksAdapter?.isFaviconsFetchingEnabled = true
        syncService?.scheduler.notifyDataChanged()
        return .actioned
    }

    private func observeWindowClose(_ windows: [NSWindow]) {
        windowCloseObservers = windows.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                   object: window,
                                                   queue: .main) { [weak self] _ in
                // Closing the window is declining, not a retraction.
                self?.resolve(with: .ignored())
            }
        }
    }

    private func resolve(with result: PromoResult) {
        guard let continuation = showContinuation else { return }
        showContinuation = nil
        tearDown()
        continuation.resume(returning: result)
    }

    private func tearDown() {
        windowCloseObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowCloseObservers = []
        if let window = windowController?.window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        }
        viewModel = nil
        windowController = nil
    }
}
