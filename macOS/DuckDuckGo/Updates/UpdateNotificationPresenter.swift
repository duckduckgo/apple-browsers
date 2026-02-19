//
//  UpdateNotificationPresenter.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Cocoa
import Common
import os.log
import PixelKit
import SwiftUI

final class UpdateNotificationPresenter: UpdateNotificationPresenting {

    static let presentationTimeInterval: TimeInterval = 10

    private let pixelFiring: PixelFiring?
    private var currentPopover: PopoverMessageViewController?

    init(pixelFiring: PixelFiring?) {
        self.pixelFiring = pixelFiring
    }

    func showUpdateNotification(for updateType: Update.UpdateType, areAutomaticUpdatesEnabled: Bool) {
        let manualActionText: String
        if StandardApplicationBuildType().isAppStoreBuild {
            manualActionText = UserText.manualUpdateAppStoreAction
        } else {
            manualActionText = UserText.manualUpdateAction
        }

        let action = areAutomaticUpdatesEnabled ? UserText.autoUpdateAction : manualActionText

        switch updateType {
        case .critical:
            showUpdateNotification(
                icon: NSImage.criticalUpdateNotificationInfo,
                text: "\(UserText.criticalUpdateNotification) \(action)",
                presentMultiline: true
            )
        case .regular:
            showUpdateNotification(
                icon: NSImage.updateNotificationInfo,
                text: "\(UserText.updateAvailableNotification) \(action)",
                presentMultiline: true
            )
        }

        // Track update notification shown
        pixelFiring?.fire(UpdateFlowPixels.updateNotificationShown)
    }

    func showUpdateNotification(for updateStatus: AppUpdateStatus) {
        switch updateStatus {
        case .noChange: break
        case .updated:
            showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserUpdatedNotification, buttonText: UserText.viewDetails)
        case .downgraded:
            showUpdateNotification(icon: NSImage.successCheckmark, text: UserText.browserDowngradedNotification, buttonText: UserText.viewDetails)
        }
    }

    private func showUpdateNotification(icon: NSImage, text: String, buttonText: String? = nil, presentMultiline: Bool = false) {
        Logger.updates.log("Notification presented: \(text, privacy: .public)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            guard let windowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController ?? Application.appDelegate.windowControllersManager.mainWindowControllers.last,
                  let button = windowController.mainViewController.navigationBarViewController.optionsButton else {
                return
            }

            let parentViewController = windowController.mainViewController

            guard parentViewController.view.window?.isKeyWindow == true, (parentViewController.presentedViewControllers ?? []).isEmpty else {
                return
            }

            let buttonAction: (() -> Void)? = { [weak self] in
                self?.openUpdatesPage()
            }

            let viewController = PopoverMessageViewController(message: text,
                                                              image: icon,
                                                              autoDismissDuration: Self.presentationTimeInterval,
                                                              shouldShowCloseButton: true,
                                                              presentMultiline: presentMultiline,
                                                              buttonText: buttonText,
                                                              buttonAction: buttonAction,
                                                              clickAction: { [weak self] in
                self?.openUpdatesPage()
            },
                                                              onDismiss: { [weak self] in
                self?.currentPopover = nil
            })

            self.currentPopover = viewController
            viewController.show(onParent: parentViewController, relativeTo: button)
        }
    }

    /// Dismisses the update popover if currently presented. Safe no-op otherwise.
    public func dismissIfPresented() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let popover = self.currentPopover,
                  let presenter = popover.presentingViewController else { return }
            presenter.dismiss(popover)
            self.currentPopover = nil
        }
    }

    /// Opens the appropriate page for viewing update information.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Opens Mac App Store app to DuckDuckGo's store page
    /// - **Sparkle**: Opens internal Release Notes tab in browser with update details
    ///
    /// **Usage**: Called when user wants to see update details, release notes, or manually update.
    /// Provides access to detailed update information and manual update path.
    func openUpdatesPage() {
        pixelFiring?.fire(UpdateFlowPixels.updateNotificationTapped)
        DispatchQueue.main.async {
            Application.appDelegate.updateController?.openUpdatesPage()
        }
    }
}
