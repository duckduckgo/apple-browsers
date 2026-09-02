//
//  BrokenSitePromoDelegate.swift
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

import BrokenSitePrompt
import Combine
import FeatureFlags_macOS
import Foundation
import PixelKit
import PrivacyConfig

/// Presents the "Site not working?" popover from the privacy dashboard button after the user refreshes
/// a page three times within 20 seconds, offering to open the Privacy Dashboard's breakage report.
final class BrokenSitePromoDelegate: InternalPromoDelegate {

    /// Resolves at most once, for exactly one `show()` call. A fresh instance is created per
    /// presentation and captured by that presentation's popover closures, instead of checking a
    /// single `isResolved` flag shared across the delegate's whole lifetime — a flag like that
    /// stays `true` forever after the very first resolution, silently breaking every show after
    /// the first for what is a recurring promo. Scoping resolution to the session also means a
    /// closure left over from a previous (already-torn-down) popover can never resolve or otherwise
    /// affect the show that replaced it.
    private final class ShowSession {
        private(set) var isResolved = false
        private let continuation: CheckedContinuation<PromoResult, Never>

        init(continuation: CheckedContinuation<PromoResult, Never>) {
            self.continuation = continuation
        }

        func resolve(with result: PromoResult) {
            guard !isResolved else { return }
            isResolved = true
            continuation.resume(returning: result)
        }
    }

    private let featureFlagger: FeatureFlagger
    private let limiter: BrokenSitePromptLimiter
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: PixelFiring?

    private var currentSession: ShowSession?
    private weak var popover: PopoverMessageViewController?

    init(featureFlagger: FeatureFlagger,
         limiter: BrokenSitePromptLimiter,
         windowControllersManager: WindowControllersManagerProtocol,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.featureFlagger = featureFlagger
        self.limiter = limiter
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.promoQueueBrokenSitePromo) && limiter.shouldShowToast()
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .map { [weak self] _ in self?.isEligible ?? false }
            .prepend(isEligible)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let navigationBarViewController,
              let addressBarButtonsViewController,
              navigationBarViewController.view.window?.isKeyWindow == true else {
            return .noChange
        }

        // The prompt is about the page the user was refreshing, so it makes no sense on our own SERP.
        if !force {
            guard let url = windowControllersManager.selectedTab?.url, !url.isDuckDuckGo else {
                return .noChange
            }
        }

        let cooldown = limiter.coolDownInterval

        return await withCheckedContinuation { continuation in
            let session = ShowSession(continuation: continuation)
            currentSession = session

            let popover = PopoverMessageViewController(
                message: UserText.BrokenSitePrompt.title,
                autoDismissDuration: nil,
                shouldShowCloseButton: true,
                buttonText: UserText.BrokenSitePrompt.buttonTitle,
                buttonAction: { [weak self] in
                    guard let self else { return }
                    if !force {
                        self.limiter.didOpenReport()
                        self.pixelFiring?.fire(GeneralPixel.siteNotWorkingWebsiteIsBroken)
                    }
                    addressBarButtonsViewController.openPrivacyDashboardPopover(entryPoint: .prompt)
                    // Recurring promo: `.actioned` would retire it permanently for the users who engaged.
                    self.resolve(session, with: force ? .noChange : .ignored(cooldown: cooldown))
                },
                onDismiss: { [weak self] in
                    guard let self, !session.isResolved else { return }
                    if !force {
                        self.limiter.didDismissToast()
                    }
                    self.resolve(session, with: force ? .noChange : .ignored(cooldown: cooldown))
                }
            )

            self.popover = popover
            popover.show(onParent: navigationBarViewController,
                         relativeTo: addressBarButtonsViewController.privacyDashboardButton,
                         behavior: .semitransient)

            // `present(_:asPopoverRelativeTo:...)` can silently decline to show anything — a window
            // torn down between the guard above and this call, or a detached anchor view. When that
            // happens `viewDidDisappear` never fires, so `onDismiss` never runs either: without this
            // check the continuation — and the promo queue session waiting on it — would be stuck
            // forever. Side effects are recorded only once presentation is confirmed, so a prompt
            // that never appeared never counts as shown.
            guard popover.presentingViewController != nil else {
                self.popover = nil
                self.resolve(session, with: .noChange)
                return
            }

            if !force {
                self.limiter.didShowToast()
                self.pixelFiring?.fire(GeneralPixel.siteNotWorkingShown)
            }
        }
    }

    @MainActor
    func hide() {
        // Resolve before tearing down: dismissing the popover fires its `onDismiss` via `viewDidDisappear`,
        // and a retraction must not be recorded as a user dismissal that advances the dismiss streak.
        if let currentSession {
            resolve(currentSession, with: .noChange)
        }

        if let popover {
            self.popover = nil
            popover.presentingViewController?.dismiss(popover)
        }
    }
}

private extension BrokenSitePromoDelegate {

    @MainActor
    var navigationBarViewController: NavigationBarViewController? {
        windowControllersManager
            .lastKeyMainWindowController?
            .mainViewController
            .navigationBarViewController
    }

    @MainActor
    var addressBarButtonsViewController: AddressBarButtonsViewController? {
        navigationBarViewController?
            .addressBarViewController?
            .addressBarButtonsViewController
    }

    /// Single funnel for every resolution path, so `onDismiss` firing after the CTA or after a
    /// programmatic teardown cannot record a second, contradictory result. Only clears
    /// `currentSession` when it is still this session — a stale reference from a prior,
    /// already-resolved show can't clobber the session that replaced it.
    @MainActor
    private func resolve(_ session: ShowSession, with result: PromoResult) {
        session.resolve(with: result)
        if session === currentSession {
            currentSession = nil
        }
    }
}
