//
//  AppStoreDockRolloutMonitor.swift
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
import PixelKit

/// Measures the App Store combined "Set as Default & Add to Dock" prompt rollout, for users who
/// are neither default nor in the Dock. Temporary: remove with the rest of `AppStoreDockRollout/`.
protocol AppStoreDockRolloutMonitoring: AnyObject {
    /// `promptID` identifies one prompt, so a banner shown again on every window focus counts once.
    func promptShown(_ type: DefaultBrowserAndDockPromptType, promptID: String)
    func setAsDefaultRequested()
}

final class AppStoreDockRolloutMonitor: AppStoreDockRolloutMonitoring {

    static let dockCheckDelay: TimeInterval = .days(7)

    private let store: AppStoreDockRolloutStoring
    private let dockCustomization: DockCustomization
    private let dateProvider: () -> Date
    private let pixelFiring: PixelFiring?

    /// The arm of the prompt on screen, kept from when it was shown: a user who adds the app to the
    /// Dock while watching the video still counts in the combined arm when they click Next.
    private var currentArm: AppStoreDockRolloutPixel.Arm?
    private var appActiveCancellable: AnyCancellable?

    init(store: AppStoreDockRolloutStoring,
         dockCustomization: DockCustomization,
         notificationCenter: NotificationCenter = .default,
         dateProvider: @escaping () -> Date = Date.init,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.store = store
        self.dockCustomization = dockCustomization
        self.dateProvider = dateProvider
        self.pixelFiring = pixelFiring

        appActiveCancellable = notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkDockStatusIfDue()
            }
    }

    func promptShown(_ type: DefaultBrowserAndDockPromptType, promptID: String) {
        currentArm = arm(for: type)
        guard let currentArm else { return }

        let shownPromptID = "\(currentArm.rawValue)-\(promptID)"
        guard shownPromptID != store.lastShownPromptID else { return }

        store.lastShownPromptID = shownPromptID
        fire(.promptShown(currentArm))

        checkDockStatusIfDue()
        if store.pendingCheck == nil {
            store.pendingCheck = AppStoreDockRolloutPendingCheck(arm: currentArm, shownDate: dateProvider())
        }
    }

    func setAsDefaultRequested() {
        guard let currentArm else { return }
        self.currentArm = nil
        fire(.setAsDefaultRequested(currentArm))
    }

    /// Runs a check that came due while the app was closed. Later checks run when the app becomes
    /// active or the next prompt is shown.
    func resume() {
        checkDockStatusIfDue()
    }

    func cancel() {
        currentArm = nil
        store.pendingCheck = nil
        store.lastShownPromptID = nil
    }

    // MARK: - Checks

    private func checkDockStatusIfDue() {
        guard let pending = store.pendingCheck,
              dateProvider() >= pending.shownDate.addingTimeInterval(Self.dockCheckDelay) else { return }

        store.pendingCheck = nil
        fire(dockCustomization.isAddedToDock ? .inDockAfterSevenDays(pending.arm) : .notInDockAfterSevenDays(pending.arm))
    }

    private func arm(for type: DefaultBrowserAndDockPromptType) -> AppStoreDockRolloutPixel.Arm? {
        guard !dockCustomization.supportsAddingToDock, !dockCustomization.isAddedToDock else { return nil }

        switch type {
        case .bothDefaultBrowserAndDockPrompt:
            return .combined
        case .setAsDefaultPrompt:
            return .setAsDefault
        case .addToDockPrompt:
            return nil
        }
    }

    private func fire(_ pixel: AppStoreDockRolloutPixel) {
        pixelFiring?.fire(pixel, frequency: .standard)
    }
}
