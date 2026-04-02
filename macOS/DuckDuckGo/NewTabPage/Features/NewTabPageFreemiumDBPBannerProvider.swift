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
    private let historyProvider: PromoHistoryProviding?
    private let promoId: String?
    private let dateProvider: () -> Date
    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    var isEligible: Bool {
        let record: PromoHistoryRecord? = if let historyProvider, let promoId {
            currentHistoryRecord(from: historyProvider, promoId: promoId)
        } else {
            nil
        }
        return computeEligibility(isFeatureAvailable: coordinator.isFeatureAvailable, historyRecord: record)
    }

    private let refreshSubject = PassthroughSubject<Void, Never>()

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        let historyPublisher: AnyPublisher<PromoHistoryRecord?, Never> = if let historyProvider, let promoId {
            historyProvider.historyPublisher(for: promoId)
        } else {
            Just(nil).eraseToAnyPublisher()
        }

        return coordinator.$isFeatureAvailable
            .combineLatest(refreshSubject.prepend(()), historyPublisher)
            .map { [weak self] isAvailable, _, record in
                self?.computeEligibility(isFeatureAvailable: isAvailable, historyRecord: record) ?? false
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Single source of truth for eligibility logic.
    private func computeEligibility(isFeatureAvailable: Bool, historyRecord: PromoHistoryRecord?) -> Bool {
        if coordinator.hasLegacyDismissal && coordinator.firstScanResults == nil { return false }
        if isFeatureAvailable { return true }

        // Fast-path: if the promo was shown within the last 7 days, consider
        // it eligible even before async product availability settles. This
        // avoids missing the NTP trigger on app restart during a display window.
        guard coordinator.isFeatureFlagEnabled else { return false }
        guard let lastShown = historyRecord?.lastShown else { return false }
        return dateProvider().timeIntervalSince(lastShown) < .days(7)
    }

    func refreshEligibility() {
        refreshSubject.send(())
    }

    init(coordinator: FreemiumDBPPromotionViewCoordinator,
         historyProvider: PromoHistoryProviding? = nil,
         promoId: String? = nil,
         dateProvider: @escaping () -> Date = Date.init) {
        self.coordinator = coordinator
        self.historyProvider = historyProvider
        self.promoId = promoId
        self.dateProvider = dateProvider
        coordinator.onScanResultsUpdated = { [weak self] in
            self?.refreshEligibility()
        }
    }

    /// Reads the current history record synchronously from the publisher's cached value.
    private func currentHistoryRecord(from provider: PromoHistoryProviding, promoId: String) -> PromoHistoryRecord? {
        var record: PromoHistoryRecord?
        // historyPublisher is backed by a CurrentValueSubject, so the first
        // emission is synchronous and available immediately on subscription.
        let cancellable = provider.historyPublisher(for: promoId)
            .first()
            .sink { record = $0 }
        cancellable.cancel()
        return record
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        resumeContinuation(with: .noChange)

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
