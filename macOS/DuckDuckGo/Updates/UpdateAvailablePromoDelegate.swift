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

/// Presents the "Update available" popover through the promo queue.
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

            // Always apply a cooldown (not a permanent dismissal) when the popover is dismissed
            let cooldown: PromoResult = .ignored(cooldown: .days(7))

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
                    self?.resolve(with: cooldown)
                },
                clickAction: { [weak self] in
                    self?.pixelFiring?.fire(UpdateFlowPixels.updateNotificationTapped)
                    self?.updateController?.openUpdatesPage()
                    self?.resolve(with: cooldown)
                },
                onDismiss: { [weak self] in
                    self?.resolve(with: cooldown)
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
