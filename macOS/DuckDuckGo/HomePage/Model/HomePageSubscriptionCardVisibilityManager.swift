//
//  HomePageSubscriptionCardVisibilityManager.swift
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
import Subscription
import Combine

protocol HomePageSubscriptionCardVisibilityManaging {
    var shouldShowSubscriptionCardPublisher: Published<Bool>.Publisher { get }
    var shouldShowSubscriptionCard: Bool { get }
    func dismissSubscriptionCard()
}

final class HomePageSubscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging {
    private let subscriptionManager: any SubscriptionManager
    private var persistor: HomePageSubscriptionCardPersisting

    private let hasSubscriptionSubject = CurrentValueSubject<Bool, Never>(false)
    // Setting the default value to true will allow the card to be shown by default. This optimizes the experience for new users.
    private let canUserPurchaseSubject = CurrentValueSubject<Bool, Never>(true)
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var shouldShowSubscriptionCard: Bool = true
    var shouldShowSubscriptionCardPublisher: Published<Bool>.Publisher {
        $shouldShowSubscriptionCard
    }

    init(subscriptionManager: any SubscriptionManager, persistor: HomePageSubscriptionCardPersisting) {
        self.subscriptionManager = subscriptionManager
        self.persistor = persistor

        Task { @MainActor in
            await setup()
        }
    }

    func dismissSubscriptionCard() {
        persistor.shouldShowSubscriptionSetting = false
        updateVisibility()
    }

    private func setup() async {
        let userHasCachedSubscription = await hasCachedSubscription()
        if userHasCachedSubscription {
            // Prevent card from showing again, even if user removes subscription from device.
            persistor.userHadSubscription = true
        }

        // Avoid setting up the observers if the user has already had a subscription.
        guard !persistor.userHadSubscription else {
            updateVisibility()
            return
        }

        Publishers.CombineLatest(canUserPurchaseSubject, hasSubscriptionSubject)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, hasSubscription in
                guard let self else { return }
                // Prevent card from showing again if the user has any kind of subscription.
                if hasSubscription {
                    persistor.userHadSubscription = true
                    // Stop observing as we don't want to show the card again.
                    cancellables.removeAll()
                }
                updateVisibility()
            }
            .store(in: &cancellables)

        // Observe eligibility conditions
        observeSubscriptionChanges()
        checkPurchaseEligibility()

        hasSubscriptionSubject.send(userHasCachedSubscription)
    }

    private func hasCachedSubscription() async -> Bool {
        let currentSubscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
        return currentSubscription != nil
    }

    private func observeSubscriptionChanges() {
        return NotificationCenter.default
            .publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hasSubscriptionSubject.send(true)
            }
            .store(in: &cancellables)
    }

    private func checkPurchaseEligibility() {
        switch subscriptionManager.currentEnvironment.purchasePlatform {
        case .appStore:
            subscriptionManager.hasAppStoreProductsAvailablePublisher
                .sink { [weak self] canPurchase in
                    self?.canUserPurchaseSubject.send(canPurchase)
                }
                .store(in: &cancellables)
        case .stripe:
            canUserPurchaseSubject.send(true)
        }
    }

    private func updateVisibility() {
        shouldShowSubscriptionCard = canUserPurchaseSubject.value && !hasSubscriptionSubject.value && persistor.shouldShowSubscriptionSetting && !persistor.userHadSubscription
    }
}
