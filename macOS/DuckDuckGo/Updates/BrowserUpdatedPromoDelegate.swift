//
//  BrowserUpdatedPromoDelegate.swift
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

/// Presents the "Browser updated" popover through the promo queue.
final class BrowserUpdatedPromoDelegate: InternalPromoDelegate, UpdateNotificationPromoDismissing {

    private let bridge: UpdateNotificationPromoBridge
    private let windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?

    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private weak var popover: PopoverMessageViewController?

    init(bridge: UpdateNotificationPromoBridge,
         windowControllersManager: WindowControllersManagerProtocol,
         featureFlagger: FeatureFlagger,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.bridge = bridge
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.promoQueueBrowserUpdatedPromo) && bridge.pendingApplicationUpdateStatus != .noChange
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .map { _ in () }
            .merge(with: bridge.pendingApplicationUpdateStatusPublisher.map { _ in () })
            .map { [weak self] _ in self?.isEligible ?? false }
            .prepend(isEligible)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let mainViewController = windowControllersManager.lastKeyMainWindowController?.mainViewController
                ?? windowControllersManager.mainWindowControllers.last?.mainViewController,
              let optionsButton = mainViewController.navigationBarViewController.optionsButton,
              mainViewController.view.window?.isKeyWindow == true,
              (mainViewController.presentedViewControllers ?? []).isEmpty,
              mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab.content != .releaseNotes else {
            return .noChange
        }

        let notificationText: String? = {
            switch bridge.pendingApplicationUpdateStatus {
            case .noChange: return nil
            case .updated: return UserText.browserUpdatedNotification
            case .downgraded: return UserText.browserDowngradedNotification
            }
        }()
        guard let notificationText else { return .noChange }

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation

            // Always temporarily dismiss the popover with no cooldown
            let noCooldown: PromoResult = .ignored(cooldown: 0)

            let popover = PopoverMessageViewController(
                message: notificationText,
                image: .successCheckmark,
                configuration: .updateNotification,
                autoDismissDuration: nil,
                shouldShowCloseButton: true,
                buttonText: UserText.viewDetails,
                buttonAction: { [weak self] in
                    self?.pixelFiring?.fire(UpdateFlowPixels.updateNotificationTapped)
                    self?.bridge.openUpdatesPage()
                    self?.resolve(with: noCooldown)
                },
                clickAction: { [weak self] in
                    self?.pixelFiring?.fire(UpdateFlowPixels.updateNotificationTapped)
                    self?.bridge.openUpdatesPage()
                    self?.resolve(with: noCooldown)
                },
                onDismiss: { [weak self] in
                    self?.resolve(with: noCooldown)
                }
            )
            if #available(macOS 26.0, *) {
                popover.view.prefersCompactControlSizeMetrics = true
            }
            popover.identifier = .updateNotificationPopover
            self.popover = popover
            popover.show(onParent: mainViewController, relativeTo: optionsButton)
        }
    }

    @MainActor
    func hide() {
        dismissPopoverUnlessHovering()
        bridge.acknowledgeApplicationUpdateStatus()
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

private extension BrowserUpdatedPromoDelegate {
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
