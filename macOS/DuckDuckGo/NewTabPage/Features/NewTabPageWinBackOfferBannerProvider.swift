//
//  NewTabPageWinBackOfferBannerProvider.swift
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

import Combine
import NewTabPage
import Subscription

final class NewTabPageWinBackOfferBannerProvider: NewTabPageWinBackOfferBannerProviding {

    var bannerMessage: NewTabPageDataModel.WinBackOfferBannerMessage? {
        guard shouldReturnBanner, let viewModel = model.viewModel else {
            return nil
        }
        return .init(viewModel)
    }

    var bannerMessagePublisher: AnyPublisher<NewTabPageDataModel.WinBackOfferBannerMessage?, Never> {
        model.$viewModel.dropFirst()
            .map { [weak self] viewModel in
                guard let self, self.shouldReturnBanner, let viewModel else {
                    return nil
                }
                return NewTabPageDataModel.WinBackOfferBannerMessage(viewModel)
            }
            .eraseToAnyPublisher()
    }

    func dismiss() async {
        model.viewModel?.closeAction()
    }

    func action() async {
        await model.viewModel?.proceedAction()
    }

    let model: WinBackOfferPromotionViewCoordinator
    private let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging

    init(model: WinBackOfferPromotionViewCoordinator,
         winBackOfferVisibilityManager: WinBackOfferVisibilityManaging = Application.appDelegate.winBackOfferVisibilityManager) {
        self.model = model
        self.winBackOfferVisibilityManager = winBackOfferVisibilityManager
    }

    /// Determines whether the banner should be returned based Win-back offer availability.
    /// Returns `true` only on the last day of the Win-back offer.
    private var shouldReturnBanner: Bool {
        winBackOfferVisibilityManager.shouldShowUrgencyMessage
    }
}

extension NewTabPageDataModel.WinBackOfferBannerMessage {
    init(_ promotionViewModel: PromotionViewModel) {

        self.init(
            titleText: promotionViewModel.title,
            descriptionText: promotionViewModel.description,
            actionText: promotionViewModel.proceedButtonText
        )
    }
}
