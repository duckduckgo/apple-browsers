//
//  UpdatePromptModalPromptProvider.swift
//  DuckDuckGo
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

import Common
import Core
import FeatureFlags_iOS
import Foundation
import Persistence
import PixelKit
import PrivacyConfig
import UIKit

/// Asks people on an outdated version to update, on the schedule in `UpdatePromptSchedule`.
final class UpdatePromptModalPromptProvider: ModalPromptProvider {

    private let storage: any ThrowingKeyedStoring<UpdatePromptKeys>
    private let featureFlagger: FeatureFlagger
    private let installedVersion: String
    private let osVersion: String
    private let pixelFiring: PixelKitFiring?
    private let openURL: (URL) -> Void
    private let now: () -> Date
    private var pendingStep: UpdatePromptStep?

    init(storage: any ThrowingKeyedStoring<UpdatePromptKeys>,
         featureFlagger: FeatureFlagger,
         installedVersion: String = AppVersion.shared.versionNumber,
         osVersion: String = UIDevice.current.systemVersion,
         pixelFiring: PixelKitFiring? = PixelKit.shared,
         openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) },
         now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.featureFlagger = featureFlagger
        self.installedVersion = installedVersion
        self.osVersion = osVersion
        self.pixelFiring = pixelFiring
        self.openURL = openURL
        self.now = now
    }

    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool {
        isOnboardingComplete && featureFlagger.isFeatureOn(.updatePrompt)
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        let evaluation = UpdatePromptSchedule.evaluate(installedVersion: installedVersion,
                                                       osVersion: osVersion,
                                                       release: try? storage.latestRelease,
                                                       state: try? storage.state,
                                                       now: now())
        try? storage.set(evaluation.state, for: \.state)
        pendingStep = evaluation.step
        guard let step = evaluation.step else { return nil }

        let pixelFiring = pixelFiring
        let openURL = openURL
        let controller = UpdatePromptHostingController(step: step, onUpdate: {
            pixelFiring?.fire(UpdatePromptPixel.updateTapped(step))
            openURL(.appStore)
        }, onNotNow: {
            pixelFiring?.fire(UpdatePromptPixel.dismissed(step))
        })
        return ModalPromptConfiguration(exposureID: .updatePrompt, viewController: controller)
    }

    /// The step counts as shown only once it is on screen, so a prompt that lost its slot stays due.
    func didPresentModal() {
        guard let step = pendingStep, let state = try? storage.state else { return }
        pendingStep = nil
        try? storage.set(state.recordingShown(step, at: now()), for: \.state)
        pixelFiring?.fire(UpdatePromptPixel.shown(step))
    }
}
