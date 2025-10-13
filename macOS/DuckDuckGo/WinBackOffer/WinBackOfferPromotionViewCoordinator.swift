//
//  WinBackOfferPromotionViewCoordinator.swift
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

import Foundation
import Combine
import OSLog
import Common
import Subscription

final class WinBackOfferPromotionViewCoordinator: ObservableObject {

    /// Published property that determines whether the promotion is visible on the home page.
    @Published var isHomePagePromotionVisible: Bool = false

    /// The view model representing the promotion, which updates based on the user's state. Returns `nil` if the feature is not enabled
    @Published
    private(set) var viewModel: PromotionViewModel?

    /// Stores whether the user has dismissed the home page promotion.
    private var didDismissHomePagePromotion: Bool {
        get {
            return winBackOfferVisibilityManager.didDismissUrgencyMessage
        }
        set {
            winBackOfferVisibilityManager.didDismissUrgencyMessage = newValue
            isHomePagePromotionVisible = !newValue
        }
    }

    private var winBackOfferVisibilityManager: WinBackOfferVisibilityManaging

    /// A set of cancellables for managing Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    init(winBackOfferVisibilityManager: WinBackOfferVisibilityManaging) {
        self.winBackOfferVisibilityManager = winBackOfferVisibilityManager

        setUpViewModelRefreshing()
        setInitialPromotionVisibilityState()
    }
}

private extension WinBackOfferPromotionViewCoordinator {
    var proceedAction: () async -> Void {
        { }
    }

    var closeAction: () -> Void {
        { }
    }

    /// Dismisses the home page promotion and updates the user state to reflect this.
    func dismissHomePagePromotion() {
        didDismissHomePagePromotion = true
    }

    /// Sets the initial visibility state based on the Win-back offer availability.
    func setInitialPromotionVisibilityState() {
        isHomePagePromotionVisible = (!didDismissHomePagePromotion && winBackOfferVisibilityManager.shouldShowUrgencyMessage)
    }

    func createViewModel() -> PromotionViewModel? {
        guard winBackOfferVisibilityManager.shouldShowUrgencyMessage, isHomePagePromotionVisible else {
            return nil
        }

        return PromotionViewModel(image: .subscriptionClock96,
                                  title: UserText.winBackCampaignLastDayMessageTitle,
                                  description: UserText.winBackCampaignLastDayMessageText,
                                  proceedButtonText: UserText.winBackCampaignLastDayMessageCTA,
                                  proceedAction: proceedAction,
                                  closeAction: closeAction)
    }

    /// This method defines the entry point to updating `viewModel` which is every change to `isHomePagePromotionVisible`.
    func setUpViewModelRefreshing() {
        $isHomePagePromotionVisible.dropFirst().asVoid()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.viewModel = self?.createViewModel()
            }
            .store(in: &cancellables)
    }
}
