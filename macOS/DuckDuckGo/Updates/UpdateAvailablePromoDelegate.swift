//
//  UpdateAvailablePromoDelegate.swift
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
import AppUpdaterShared
import Combine
import FeatureFlags_macOS
import PixelKit
import PrivacyConfig

/// Presents the "Update available" popover through the promo queue, migrated from
/// `UpdateNotificationPresenter`. Covers both regular and critical updates with the same id and
/// cooldown — `SparkleUpdateController`'s existing `NotificationDelay` scheduling already fires
/// critical updates immediately, so no separate critical-update promo is needed here.
final class UpdateAvailablePromoDelegate: InternalPromoDelegate, UpdateNotificationPromoDismissing {

    private let updateController: (any UpdateController)?
    private let windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?

    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private weak var popover: PopoverMessageViewController?

    init(updateController: (any UpdateController)?,
         windowControllersManager: WindowControllersManagerProtocol,
         featureFlagger: FeatureFlagger,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.updateController = updateController
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.promoQueueUpdateAvailablePromo) && (updateController?.hasPendingUpdate ?? false)
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        guard let updateController else {
            return Just(false).eraseToAnyPublisher()
        }
        return featureFlagger.updatesPublisher
            .map { _ in () }
            .merge(with: updateController.hasPendingUpdatePublisher.map { _ in () })
            .map { [weak self] _ in self?.isEligible ?? false }
            .prepend(isEligible)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let updateController, let latestUpdate = updateController.latestUpdate else {
            return .noChange
        }

        guard let mainViewController = windowControllersManager.lastKeyMainWindowController?.mainViewController
                ?? windowControllersManager.mainWindowControllers.last?.mainViewController,
              let optionsButton = mainViewController.navigationBarViewController.optionsButton,
              mainViewController.view.window?.isKeyWindow == true,
              (mainViewController.presentedViewControllers ?? []).isEmpty else {
            return .noChange
        }

        let manualActionText = StandardApplicationBuildType().isAppStoreBuild
            ? UserText.manualUpdateAppStoreAction
            : UserText.manualUpdateAction
        let action = updateController.areAutomaticUpdatesEnabled ? UserText.autoUpdateAction : manualActionText

        let icon: NSImage
        let text: String
        switch latestUpdate.type {
        case .critical:
            icon = .criticalUpdateNotificationInfo
            text = "\(UserText.criticalUpdateNotification) \(action)"
        case .regular:
            icon = .updateNotificationInfo
            text = "\(UserText.updateAvailableNotification) \(action)"
        }

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation

            // There is no genuine "conversion" event for an update notification — only "shown and
            // not clicked away in some way." All three paths below (CTA tap, message click, close/
            // dismiss) must resolve `.ignored(cooldown: .days(7))`, never `.actioned`. This can't be
            // covered by a unit test: presenting a real popover trips `TestRunHelper`'s
            // `NSWindowDidOrderOnScreenAndFinishAnimatingNotification` guard ("Unit Tests should not
            // present UI"), which is a deliberate, unconditional fatalError in this test target — the
            // same limitation applies to every other promo delegate that presents a real popover
            // (e.g. `AutoplayDiscoverabilityPromoDelegate`), none of which test past this point either.
            let popover = PopoverMessageViewController(
                message: text,
                image: icon,
                configuration: .default,
                autoDismissDuration: nil,
                shouldShowCloseButton: true,
                presentMultiline: true,
                buttonAction: { [weak self] in
                    self?.pixelFiring?.fire(UpdateFlowPixels.updateNotificationTapped)
                    self?.updateController?.openUpdatesPage()
                    self?.resolve(with: .ignored(cooldown: .days(7)))
                },
                clickAction: { [weak self] in
                    self?.pixelFiring?.fire(UpdateFlowPixels.updateNotificationTapped)
                    self?.updateController?.openUpdatesPage()
                    self?.resolve(with: .ignored(cooldown: .days(7)))
                },
                onDismiss: { [weak self] in
                    self?.resolve(with: .ignored(cooldown: .days(7)))
                }
            )
            if #available(macOS 26.0, *) {
                popover.view.prefersCompactControlSizeMetrics = true
            }
            popover.identifier = .updateNotificationPopover
            self.popover = popover
            popover.show(onParent: mainViewController, relativeTo: optionsButton)
            pixelFiring?.fire(UpdateFlowPixels.updateNotificationShown)
        }
    }

    @MainActor
    func hide() {
        dismissPopoverUnlessHovering()
        resolve(with: .noChange)
    }

    @MainActor
    func dismissIfPresented() {
        guard let popover, let presenter = popover.presentingViewController else { return }
        presenter.dismiss(popover)
        self.popover = nil
        resolve(with: .noChange)
    }
}

private extension UpdateAvailablePromoDelegate {
    @MainActor
    func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }

    /// `PromoService`'s own timeout timer can't be paused, so when it fires (`hide()` is called)
    /// while the pointer is over the popover, this leaves it open rather than forcing it closed
    /// out from under the user — mirroring `PermissionCenterViewModel.allowsAutodismiss` (the
    /// mechanism `AutoplayDiscoverabilityPromoDelegate` relies on), via a live hit-test instead of
    /// a permanent flag, so no change to `PopoverMessageViewController` is needed.
    @MainActor
    func dismissPopoverUnlessHovering() {
        guard let popover, let presenter = popover.presentingViewController else { return }
        if let window = popover.view.window, window.frame.contains(NSEvent.mouseLocation) {
            return
        }
        presenter.dismiss(popover)
        self.popover = nil
    }
}
