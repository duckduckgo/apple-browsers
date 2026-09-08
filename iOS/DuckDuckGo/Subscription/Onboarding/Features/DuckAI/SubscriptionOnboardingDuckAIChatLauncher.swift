//
//  SubscriptionOnboardingDuckAIChatLauncher.swift
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

import UIKit

/// Hands the user off from the subscription onboarding flow into a Duck.ai chat.
@MainActor
struct SubscriptionOnboardingDuckAIChatLauncher {

    /// - Returns: whether a `MainViewController` was reachable, so a caller can recover if it wasn't.
    func launch(modelID: String?) -> Bool {
        guard let mainViewController = UIApplication.shared.firstKeyWindow?.rootViewController as? MainViewController else {
            assertionFailure("Expected MainViewController as rootViewController when launching Duck.ai from onboarding")
            return false
        }
        mainViewController.dismiss(animated: true) {
            mainViewController.openAIChat(source: .onboarding, flowType: .mobileAppOnboarding, modelId: modelID)
        }
        return true
    }
}
