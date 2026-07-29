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
///
/// Onboarding is presented modally over the browser, so this dismisses onboarding and opens Duck.ai,
/// optionally preselecting a model in the input before the user sends a prompt.
@MainActor
struct SubscriptionOnboardingDuckAIChatLauncher {

    func launch(from presentingViewController: UIViewController, modelID: String?) {
        guard let mainViewController = presentingViewController.view.window?.rootViewController as? MainViewController else { return }
        mainViewController.dismiss(animated: true) {
            mainViewController.openAIChat(flowType: .mobileAppOnboarding, modelId: modelID)
        }
    }
}
