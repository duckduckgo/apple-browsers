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
import PixelKit

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
    private let pixelHandler: (SubscriptionPixel) -> Void
    private let urlOpener: @MainActor (URL) -> Void

    /// A set of cancellables for managing Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    init(winBackOfferVisibilityManager: WinBackOfferVisibilityManaging,
         pixelHandler: @escaping (SubscriptionPixel) -> Void = { PixelKit.fire($0) },
         urlOpener: @escaping @MainActor (URL) -> Void = { @MainActor url in
             Application.appDelegate.windowControllersManager.showTab(with: .subscription(url))
         }) {
        self.winBackOfferVisibilityManager = winBackOfferVisibilityManager
        self.pixelHandler = pixelHandler
        self.urlOpener = urlOpener

        setUpViewModelRefreshing()
        setInitialPromotionVisibilityState()
    }
}

extension WinBackOfferPromotionViewCoordinator {
    /// Action to be executed when the user proceeds with the promotion (e.g., opens win-back offer)
    var proceedAction: () async -> Void {
        { @MainActor [weak self] in
            guard let self else { return }

            // Open the win-back offer subscription page with proper attribution
            guard let url = WinBackOfferURL.subscriptionURL(for: .winBackNewTabPage) else { return }

            pixelHandler(.subscriptionWinBackOfferNewTabPageCTAClicked)

            urlOpener(url)

            // Dismiss the promotion after action
            dismissHomePagePromotion()
        }
    }

    /// Action to be executed when the user closes the promotion
    var closeAction: () -> Void {
        { [weak self] in
            guard let self else { return }

            pixelHandler(.subscriptionWinBackOfferNewTabPageDismissed)

            dismissHomePagePromotion()
        }
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

        pixelHandler(.subscriptionWinBackOfferNewTabPageShown)

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
