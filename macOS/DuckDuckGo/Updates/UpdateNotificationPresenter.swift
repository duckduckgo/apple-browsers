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

import AppUpdaterShared
import Cocoa
import Common
import FoundationExtensions
import os.log
import PixelKit
import SwiftUI

final class UpdateNotificationPresenter: UpdateNotificationPresenting {

    static let presentationTimeInterval: TimeInterval = 10

    private let pixelFiring: PixelFiring?
    private let shouldSuppressPostUpdateNotification: () -> Bool
    private let showNotificationPopover: @MainActor (PopoverMessageViewController) -> Bool
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var currentPopover: PopoverMessageViewController?

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    init(pixelFiring: PixelFiring?,
         shouldSuppressPostUpdateNotification: @escaping () -> Bool = { false },
         notificationCenter: NotificationCenter = .default,
         showNotificationPopover: @escaping @MainActor (PopoverMessageViewController) -> Bool) {
        self.pixelFiring = pixelFiring
        self.shouldSuppressPostUpdateNotification = shouldSuppressPostUpdateNotification
        self.notificationCenter = notificationCenter
        self.showNotificationPopover = showNotificationPopover

        startListeningToNotifications(notificationCenter: notificationCenter)
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
        Task { @MainActor [weak self] in
            guard let self, !self.shouldSuppressPostUpdateNotification() else { return }

            switch updateStatus {
            case .noChange: break
            case .updated:
                self.showUpdateNotification(icon: .successCheckmark, text: UserText.browserUpdatedNotification, buttonText: UserText.viewDetails)
            case .downgraded:
                self.showUpdateNotification(icon: .successCheckmark, text: UserText.browserDowngradedNotification, buttonText: UserText.viewDetails)
            }
        }
    }

    private func showUpdateNotification(icon: NSImage, text: String, buttonText: String? = nil, presentMultiline: Bool = false) {
        Logger.updates.log("Notification presented: \(text, privacy: .public)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let viewController = PopoverMessageViewController(message: text,
                                                              image: icon,
                                                              autoDismissDuration: Self.presentationTimeInterval,
                                                              shouldShowCloseButton: true,
                                                              presentMultiline: presentMultiline,
                                                              buttonText: buttonText,
                                                              buttonAction: { [weak self] in
                self?.openUpdatesPage()
            },
                                                              clickAction: { [weak self] in
                self?.openUpdatesPage()
            },
                                                              onDismiss: { [weak self] in
                self?.currentPopover = nil
            })

            viewController.identifier = .updateNotificationPopover

            if self.showNotificationPopover(viewController) {
                self.currentPopover = viewController
            }
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

private extension UpdateNotificationPresenter {

    /// Set-up Notifications Listeners
    func startListeningToNotifications(notificationCenter: NotificationCenter) {
        observers = [
            notificationCenter.addObserver(forName: .suggestionWindowDidShow, object: nil, queue: .main) { [weak self] _ in
                self?.dismissIfPresented()
            }
        ]
    }
}

extension NSUserInterfaceItemIdentifier {
    /// Tags the update-notification toast's content view controller so the address bar's
    /// `childWindows` observer can allow-list its window instead of treating it as a competing panel.
    static let updateNotificationPopover = NSUserInterfaceItemIdentifier("updateNotificationPopover")
}
