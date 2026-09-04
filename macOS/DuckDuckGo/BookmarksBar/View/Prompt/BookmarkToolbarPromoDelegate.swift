//
//  BookmarkToolbarPromoDelegate.swift
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
import Foundation
import Persistence
import PrivacyConfig

struct BookmarkToolbarPromoSettings: StoringKeys {
    let didShowLegacyPopover = StorageKey<Bool>(UserDefaultsKeys.bookmarksBarPromptShown, assertionHandler: { _ in })
}

/// Presents the "Show Bookmarks Bar?" popover through the promo queue, offering to turn on the
/// bookmarks bar after the user creates their first bookmark or imports bookmarks.
final class BookmarkToolbarPromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let windowControllersManager: WindowControllersManagerProtocol
    private let storage: KeyedStorage<BookmarkToolbarPromoSettings>

    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private weak var presentedMainViewController: MainViewController?
    private var pendingPresentation: DispatchWorkItem?

    init(featureFlagger: FeatureFlagger,
         windowControllersManager: WindowControllersManagerProtocol,
         storage: KeyedStorage<BookmarkToolbarPromoSettings>? = nil) {
        self.featureFlagger = featureFlagger
        self.windowControllersManager = windowControllersManager
        self.storage = storage ?? KeyedStorage(storage: UserDefaults.standard)
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.promoQueueBookmarkToolbarPromo)
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .map { [featureFlagger] _ in
                featureFlagger.isFeatureOn(.promoQueueBookmarkToolbarPromo)
            }
            .prepend(isEligible)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        if !force, storage.didShowLegacyPopover == true {
            return .retired
        }

        guard let mainViewController = windowControllersManager.lastKeyMainWindowController?.mainViewController,
              !mainViewController.isInPopUpWindow else {
            return .noChange
        }

        if mainViewController.mainView.isBookmarksBarShown {
            // Don't show this to users who obviously know about the bookmarks bar already.
            return .retired
        }

        presentedMainViewController = mainViewController
        mainViewController.updateBookmarksBarViewVisibility(visible: true)

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation

            // This won't work until the bookmarks bar is actually visible, which it isn't until the next UI cycle.
            let presentation = DispatchWorkItem { [weak mainViewController, weak self] in
                guard let mainViewController else {
                    self?.resume(with: .noChange)
                    return
                }
                mainViewController.bookmarksBarViewController.showBookmarksBarPrompt { result in
                    self?.resume(with: result)
                }
            }
            pendingPresentation = presentation
            DispatchQueue.main.asyncAfter(deadline: .now() + NSAnimationContext.current.duration, execute: presentation)
        }
    }

    @MainActor
    func hide() {
        presentedMainViewController?.bookmarksBarViewController.retractBookmarksBarPromptIfNeeded()

        // A pending continuation means the queue retracts the promo before the user makes a choice.
        // We need to undo the visibility that show() forced on.
        //
        // Do not hide the bar in the same runloop turn as the animated close of the popover. The bar
        // holds the positioning view of the popover. If you remove that view during the close, AppKit
        // keeps the popover and its content view controller in memory. The user-dismiss path hides
        // the bar one turn later, through receive(on: DispatchQueue.main); we do the same here.
        if resultContinuation != nil, let mainViewController = presentedMainViewController {
            DispatchQueue.main.async {
                mainViewController.updateBookmarksBarViewVisibility(visible: mainViewController.shouldShowBookmarksBar)
            }
        }

        resume(with: .noChange)
    }

    private func resume(with result: PromoResult) {
        pendingPresentation?.cancel()
        pendingPresentation = nil
        presentedMainViewController = nil

        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }
}
