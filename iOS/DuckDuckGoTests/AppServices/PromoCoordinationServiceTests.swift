//
//  PromoCoordinationServiceTests.swift
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
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Promo Coordination - Service")
final class PromoCoordinationServiceTests {
    private let launchSourceManagerMock: MockLaunchSourceManager
    private let contextualOnboardingMock: MockContextualOnboardingStatusProvider
    private let managerMock: MockModalPromptCoordinationManager
    private let presenterMock: MockModalPromptPresenter
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private let promoQueueCooldownPolicy: MockPromoQueueCooldownPolicy
    private var sut: PromoCoordinationService!

    init() {
        launchSourceManagerMock = MockLaunchSourceManager()
        contextualOnboardingMock = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        managerMock = MockModalPromptCoordinationManager()
        presenterMock = MockModalPromptPresenter()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
        promoQueueCooldownPolicy = MockPromoQueueCooldownPolicy()
    }

    // MARK: - Launch Source Checks

    @Test(
        "Check Modal Is Not Presented For Different Non-Standard Launch Sources",
        arguments: [
            LaunchSource.shortcut,
            .URL,
        ]
    )
    func whenDifferentNonStandardLaunchSourcesThenModalIsNotPresented(launchSource: LaunchSource) {
        // GIVEN
        launchSourceManagerMock.source = launchSource
        presenterMock.presentedViewController = nil
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            mode: .legacy,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            appRatingPromptCoordinator: MockAppRatingPromptCoordinator()
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Check Modal Is Presented When Launch Source Is Standard")
    func whenLaunchSourceIsStandardThenModalIsPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            mode: .legacy,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            appRatingPromptCoordinator: MockAppRatingPromptCoordinator()
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedPresenter === presenterMock)
    }

    // MARK: - Presented View Controller Checks

    @Test("Check Modal Is Not Presented When Another Modal Is Already Presented")
    func whenAnotherModalIsPresentedThenModalIsNotPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        let alreadyPresentedVC = UIViewController()
        presenterMock.presentedViewController = alreadyPresentedVC
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            mode: .legacy,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            appRatingPromptCoordinator: MockAppRatingPromptCoordinator()
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Check Modal Is Presented When No Modal Is Currently Presented")
    func whenNoModalIsPresentedThenModalIsPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            mode: .legacy,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            appRatingPromptCoordinator: MockAppRatingPromptCoordinator()
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Check Modal Is Presented When Presented Modal Is Being Dismissed")
    func whenPresentedModalIsBeingDismissedThenModalIsPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        let dismissingVC = MockDismissingViewController()
        dismissingVC.isBeingDismissed = true
        presenterMock.presentedViewController = dismissingVC
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            mode: .legacy,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            appRatingPromptCoordinator: MockAppRatingPromptCoordinator()
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Check Modal Is Not Presented When Multiple Conditions Fail")
    func whenMultipleConditionsFailThenModalIsNotPresented() {
        // GIVEN
        launchSourceManagerMock.source = .URL
        presenterMock.presentedViewController = UIViewController()
        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            mode: .legacy,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            appRatingPromptCoordinator: MockAppRatingPromptCoordinator()
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test(
        "Check Provider Priority Order",
        arguments: [
            ProviderPriority.winBackOffer,
            .subscriptionPromo,
            .subscriptionPromoExistingUser,
            .newAddressBarPicker,
            .defaultBrowser,
            .whatsNew,
            .cookiePopupProtectionOptIn
        ]
    )
    func whenHigherPriorityProvidersReturnNilThenCorrectProviderIsUsed(priority: ProviderPriority) throws {
        // GIVEN
        let providers = ModalPromptProviders(
            // Not eligible, so it cannot win ahead of the provider under test. Deferred ordering
            // is covered by ModalPromptCoordinationManagerDeferredTests.
            appRatingPrompt: MockModalPromptProvider(shouldReturnPrompt: false),
            newAddressBarPicker: MockModalPromptProvider(shouldReturnPrompt: priority == .newAddressBarPicker),
            defaultBrowser: MockModalPromptProvider(shouldReturnPrompt: priority == .defaultBrowser),
            winBackOffer: MockModalPromptProvider(shouldReturnPrompt: priority == .winBackOffer),
            subscriptionPromo: MockModalPromptProvider(shouldReturnPrompt: priority == .subscriptionPromo),
            subscriptionPromoExistingUser: MockModalPromptProvider(shouldReturnPrompt: priority == .subscriptionPromoExistingUser),
            whatsNew: MockModalPromptProvider(shouldReturnPrompt: priority == .whatsNew),
            cookiePopupProtectionOptIn: MockModalPromptProvider(shouldReturnPrompt: priority == .cookiePopupProtectionOptIn),
        )

        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let manager = ModalPromptCoordinationManager(
            providers: providers.ordered,
            cooldownManager: MockPromptCooldownManager(),
            onboardingStatusProvider: contextualOnboardingMock
        )

        sut = PromoCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: manager,
            mode: .legacy,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter,
            promoQueueCooldownPolicy: promoQueueCooldownPolicy,
            appRatingPromptCoordinator: MockAppRatingPromptCoordinator()
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN All providers up to and including the target should be checked
        for providerPriority in ProviderPriority.allCases {
            let provider = try #require(providers.provider(for: providerPriority) as? MockModalPromptProvider)
            if providerPriority.rawValue <= priority.rawValue {
                #expect(provider.didCallProvideModalPrompt, "Provider \(providerPriority) should be checked")
            } else {
                #expect(!provider.didCallProvideModalPrompt, "Provider \(providerPriority) should not be checked")
            }
        }
    }


}

extension ModalPromptProviders {

    func provider(for priority: ProviderPriority) -> ModalPromptProvider? {
        switch priority {
        case .winBackOffer: return winBackOffer
        case .subscriptionPromo: return subscriptionPromo
        case .subscriptionPromoExistingUser: return subscriptionPromoExistingUser
        case .defaultBrowser: return defaultBrowser
        case .newAddressBarPicker: return newAddressBarPicker
        case .whatsNew: return whatsNew
        case .cookiePopupProtectionOptIn: return cookiePopupProtectionOptIn
        }
    }

}

enum ProviderPriority: Int, CaseIterable, CustomStringConvertible {
    case winBackOffer = 0
    case subscriptionPromo = 1
    case subscriptionPromoExistingUser = 2
    case newAddressBarPicker = 3
    case defaultBrowser = 4
    case whatsNew = 5
    case cookiePopupProtectionOptIn = 6

    var index: Int { rawValue }

    var description: String {
        switch self {
        case .winBackOffer: return "WinBackOffer"
        case .subscriptionPromo: return "SubscriptionPromo"
        case .subscriptionPromoExistingUser: return "SubscriptionPromoExistingUser"
        case .newAddressBarPicker: return "NewAddressBarPicker"
        case .defaultBrowser: return "DefaultBrowser"
        case .whatsNew: return "WhatsNew"
        case .cookiePopupProtectionOptIn: return "CookiePopupProtectionOptIn"
        }
    }
}

private final class MockDismissingViewController: UIViewController {
    private var _isBeingDismissed = false

    override var isBeingDismissed: Bool {
        get { _isBeingDismissed }
        set { _isBeingDismissed = newValue }
    }
}
