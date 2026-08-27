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

/// Presents the "Show Bookmarks Bar?" popover through the promo queue, offering to turn on the
/// bookmarks bar after the user creates their first bookmark or imports bookmarks.
///
/// Shown at most once ever, regardless of outcome (matches the legacy popover's behavior); a user
/// who already saw the pre-Promo-Queue popover (recorded by the legacy `bookmarksBarPromptShown`
/// flag) is retired without presenting anything.
final class BookmarkToolbarPromoDelegate: InternalPromoDelegate {

    private let windowControllersManager: WindowControllersManagerProtocol

    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private var popover: BookmarksBarPromptPopover?

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    var isEligible: Bool { true }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        Just(true).eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        if !force, UserDefaultsWrapper(key: .bookmarksBarPromptShown, defaultValue: false).wrappedValue {
            return .retired
        }

        guard let mainViewController = windowControllersManager.lastKeyMainWindowController?.mainViewController else {
            return .noChange
        }

        if let result = Self.precheckResult(for: mainViewController) {
            return result
        }

        mainViewController.updateBookmarksBarViewVisibility(visible: true)

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation

            // This won't work until the bookmarks bar is actually visible, which it isn't until the next UI cycle.
            DispatchQueue.main.asyncAfter(deadline: .now() + NSAnimationContext.current.duration) { [weak self] in
                guard let self else { return }
                self.popover = mainViewController.bookmarksBarViewController.showBookmarksBarPrompt { [weak self] accepted in
                    self?.popover = nil
                    self?.resolve(with: Self.resolutionResult(accepted: accepted))
                }
            }
        }
    }

    @MainActor
    func hide() {
        if let popover {
            // Suppress the popover's own implicit "user rejected" side effect (flipping the
            // showBookmarksBar preference) — a force-hide isn't a user dismissal.
            popover.viewController.rootView.model.userDidDismiss = true
            popover.close()
        }
        popover = nil
        resolve(with: .noChange)
    }

    /// Mirrors the legacy popover's own upfront checks. Returns `nil` when presentation should
    /// proceed; otherwise the promo resolves immediately without ever showing anything.
    static func precheckResult(for mainViewController: MainViewController) -> PromoResult? {
        if mainViewController.isInPopUpWindow {
            return .noChange
        }
        if mainViewController.mainView.isBookmarksBarShown {
            // Don't show this to users who obviously know about the bookmarks bar already.
            return .ignored()
        }
        return nil
    }

    /// One-shot resolution: engaging keeps the bar on and permanently retires the promo;
    /// dismissing also permanently retires it (matches the legacy popover's "shown at most once
    /// ever" behavior, regardless of the user's choice).
    static func resolutionResult(accepted: Bool) -> PromoResult {
        accepted ? .actioned : .ignored()
    }

    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }
}
