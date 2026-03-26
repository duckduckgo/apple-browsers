//
//  NewTabPageFreemiumDBPBannerProvider.swift
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

import Combine
import Foundation
import NewTabPage

final class NewTabPageFreemiumDBPBannerProvider: NewTabPageFreemiumDBPBannerProviding {

    var bannerMessage: NewTabPageDataModel.FreemiumPIRBannerMessage? {
        guard shouldReturnBanner, let viewModel = model.viewModel else {
            return nil
        }
        return .init(viewModel)
    }

    var bannerMessagePublisher: AnyPublisher<NewTabPageDataModel.FreemiumPIRBannerMessage?, Never> {
        model.$viewModel.dropFirst()
            .map { [weak self] viewModel in
                guard let self, self.shouldReturnBanner, let viewModel else {
                    return nil
                }
                return NewTabPageDataModel.FreemiumPIRBannerMessage(viewModel)
            }
            .eraseToAnyPublisher()
    }

    func dismiss() async {
        model.viewModel?.closeAction()
    }

    func action() async {
        await model.viewModel?.proceedAction()
    }

    let model: FreemiumDBPPromotionViewCoordinator
    private let contextualDialogsManager: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater

    init(model: FreemiumDBPPromotionViewCoordinator,
         contextualDialogsManager: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater = Application.appDelegate.onboardingContextualDialogsManager) {
        self.model = model
        self.contextualDialogsManager = contextualDialogsManager
    }

    /// Determines whether the banner should be returned based on onboarding completion status.
    /// Returns `true` only when contextual onboarding has been completed.
    private var shouldReturnBanner: Bool {
        contextualDialogsManager.state == .onboardingCompleted
    }
}

extension NewTabPageDataModel.FreemiumPIRBannerMessage {
    init(_ promotionViewModel: PromotionViewModel) {

        self.init(
            titleText: promotionViewModel.title,
            descriptionText: promotionViewModel.description,
            actionText: promotionViewModel.proceedButtonText
        )
    }
}

final class FreemiumDBPPromoDelegate: PromoDelegate {

    private let coordinator: FreemiumDBPPromotionViewCoordinator
    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    var isEligible: Bool {
        coordinator.isFeatureAvailable
    }

    private let refreshSubject = PassthroughSubject<Void, Never>()

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        coordinator.$isFeatureAvailable
            .combineLatest(refreshSubject.prepend(()))
            .map { isAvailable, _ in isAvailable }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func refreshEligibility() {
        refreshSubject.send(())
    }

    init(coordinator: FreemiumDBPPromotionViewCoordinator) {
        self.coordinator = coordinator
        coordinator.onScanResultsUpdated = { [weak self] in
            self?.refreshEligibility()
        }
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        resumeContinuation(with: .noChange)

        // Honor legacy dismissals from before queue integration.
        if coordinator.hasLegacyDismissal && coordinator.firstScanResults == nil && !force {
            return .ignored()
        }

        // Display window: if the promo has been shown for 7+ days, enter cooldown.
        if let promoShownDate = history.lastShown,
           Date().timeIntervalSince(promoShownDate) >= .days(7) {
            return .ignored(cooldown: .days(28))
        }

        coordinator.refreshViewModel()

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
            coordinator.onUserAction = { [weak self] result in
                self?.resumeContinuation(with: result)
            }
        }
    }

    @MainActor
    func hide() {
        resumeContinuation(with: .noChange)
        coordinator.clearViewModel()
    }

    @MainActor
    private func resumeContinuation(with result: PromoResult) {
        showContinuation?.resume(returning: result)
        showContinuation = nil
        coordinator.onUserAction = nil
    }
}
