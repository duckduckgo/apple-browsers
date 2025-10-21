//
//  WinBackOfferService.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Subscription
import Core

/// Service to handle Win-back offer
/// 
/// Mainly responsible for setting up the coordinator and presenter.
final class WinBackOfferService {
    let presenter: WinBackOfferPresenting
    let visibilityManager: WinBackOfferVisibilityManaging
    private let coordinator: WinBackOfferCoordinating

    var shouldShowUrgencyMessage: Bool {
        visibilityManager.shouldShowUrgencyMessage
    }

    init(
        visibilityManager: WinBackOfferVisibilityManaging,
        isOnboardingCompletedProvider: @escaping () -> Bool
    ) {
        self.visibilityManager = visibilityManager

        coordinator = WinBackOfferCoordinator(
            visibilityManager: visibilityManager,
            isOnboardingCompleted: isOnboardingCompletedProvider
        )

        presenter = WinBackOfferPresenter(
            coordinator: coordinator
        )
    }
    
    /// Set the URL handler for the coordinator for opening the purchase flow.
    func setURLHandler(_ handler: URLHandling) {
        coordinator.urlHandler = handler
    }
}
