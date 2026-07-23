//
//  ModalPromptCoordinationServiceTests.swift
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
import Foundation
import Combine
import Testing
import PersistenceTestingUtils
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Service")
final class ModalPromptCoordinationServiceTests {
    private let launchSourceManagerMock: MockLaunchSourceManager
    private let contextualOnboardingMock: MockContextualOnboardingStatusProvider
    private let managerMock: MockModalPromptCoordinationManager
    private let presenterMock: MockModalPromptPresenter
    private let featureFlaggerMock: MockFeatureFlagger
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbiter
    private var sut: ModalPromptCoordinationService!

    init() {
        launchSourceManagerMock = MockLaunchSourceManager()
        contextualOnboardingMock = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        managerMock = MockModalPromptCoordinationManager()
        presenterMock = MockModalPromptPresenter()
        featureFlaggerMock = MockFeatureFlagger()
        promoQueueLeaseArbiter = PromoQueueLeaseArbiter()
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
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
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
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
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
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
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
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
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
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Check Modal Is Presented When OmniBarEditingStateViewController Is Presented")
    func whenOmniBarEditingStateIsPresentedThenModalIsPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = OmniBarEditingStateViewController(
            switchBarHandler: MockSwitchBarHandler()
        )
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
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
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
    }

    // MARK: - Promo Queue Admission

    @Test("Enabled Modal Evaluation Acquires Lease Before Calling Manager")
    func whenPromoQueueIsEnabledThenManagerReceivesAcquiredLease() {
        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.capturedModalLease != nil)
        #expect(promoQueueLeaseArbiter.snapshot.hasModalLease)
    }

    @Test("Visible Promo Denial Does Not Reach Modal Manager")
    func whenVisiblePromoOwnsSlotThenModalManagerIsNotCalled() throws {
        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let visibleIdentity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "rmf"
        )
        guard case .acquired = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: visibleIdentity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoIdentities == [visibleIdentity])
    }

    @Test("Visible Promo Denial Never Queries A Real Provider Chain")
    func whenVisiblePromoOwnsSlotThenProvidersAreNotQueried() throws {
        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        let provider = MockModalPromptProvider()
        let providers = ModalPromptProviders(
            newAddressBarPicker: provider,
            defaultBrowser: provider,
            winBackOffer: provider,
            subscriptionPromo: provider,
            subscriptionPromoExistingUser: provider,
            whatsNew: provider,
            cookiePopupProtectionOptIn: provider
        )
        let visibleIdentity = VisiblePromoIdentity(
            surfaceID: UUID(),
            promoType: .remoteMessage,
            promoID: "rmf"
        )
        guard case .acquired = promoQueueLeaseArbiter.acquireVisiblePromoLease(for: visibleIdentity) else {
            Issue.record("Expected visible promo lease acquisition")
            return
        }
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            keyValueStore: try MockKeyValueFileStore(),
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            privacyConfigManager: MockPrivacyConfigurationManager(),
            providers: providers,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(!provider.didCallProvideModalPrompt)
        #expect(!presenterMock.didCallPresent)
    }

    @Test("Disabled Modal Evaluation Uses Legacy Manager Path Without Lease")
    func whenPromoQueueIsDisabledThenLegacyManagerPathIsUnchanged() {
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedModalLease == nil)
        #expect(!promoQueueLeaseArbiter.snapshot.hasModalLease)
        #expect(managerMock.reconcilePresentedModalCallCount == 0)
    }

    @Test("Released Modal Lease Retries Two Active Registrations Once Without Recursion")
    func whenManagerReleasesModalLeaseThenActiveRegistrationsRetryOnce() {
        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil
        managerMock.coordinatedPresentationDisposition = .released
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let firstSurfaceID = UUID()
        let secondSurfaceID = UUID()
        let firstTarget = MockNewTabPagePromoRetryTarget()
        let secondTarget = MockNewTabPagePromoRetryTarget()
        firstTarget.isActiveForPromoRetry = false
        secondTarget.isActiveForPromoRetry = false
        managerMock.onPresentCoordinated = {
            firstTarget.isActiveForPromoRetry = true
            secondTarget.isActiveForPromoRetry = true
        }
        firstTarget.onRetry = { [weak self] in
            guard let self else { return }
            _ = sut.admitVisiblePromo(
                VisiblePromoIdentity(surfaceID: firstSurfaceID, promoType: .remoteMessage, promoID: "first")
            )
        }
        secondTarget.onRetry = { [weak self] in
            guard let self else { return }
            _ = sut.admitVisiblePromo(
                VisiblePromoIdentity(surfaceID: secondSurfaceID, promoType: .remoteMessage, promoID: "second")
            )
        }
        let firstRegistration = sut.registerVisiblePromoRetry(for: firstSurfaceID, target: firstTarget)
        let secondRegistration = sut.registerVisiblePromoRetry(for: secondSurfaceID, target: secondTarget)
        _ = (firstRegistration, secondRegistration)

        sut.presentModalPromptIfNeeded(from: presenterMock)

        #expect(firstTarget.retryCount == 1)
        #expect(secondTarget.retryCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 2)
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Visible Admission Checkpoint Admits Triggering Surface Before Retrying Other Surface")
    func whenVisibleAdmissionReleasesDetachedModalThenTriggeringSurfaceWinsBeforeRetrySnapshot() {
        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        guard case .acquired(let modalLease) = promoQueueLeaseArbiter.acquireModalLease() else {
            Issue.record("Expected modal lease acquisition")
            return
        }
        managerMock.reconcilePresentedModalResult = true
        managerMock.onReconcilePresentedModal = {
            modalLease.release()
        }
        let triggeringSurfaceID = UUID()
        let otherSurfaceID = UUID()
        let triggeringTarget = MockNewTabPagePromoRetryTarget()
        let otherTarget = MockNewTabPagePromoRetryTarget()
        otherTarget.onRetry = { [weak self] in
            guard let self else { return }
            _ = sut.admitVisiblePromo(
                VisiblePromoIdentity(surfaceID: otherSurfaceID, promoType: .remoteMessage, promoID: "other")
            )
        }
        let triggeringRegistration = sut.registerVisiblePromoRetry(
            for: triggeringSurfaceID,
            target: triggeringTarget
        )
        let otherRegistration = sut.registerVisiblePromoRetry(
            for: otherSurfaceID,
            target: otherTarget
        )
        _ = (triggeringRegistration, otherRegistration)

        let result = sut.admitVisiblePromo(
            VisiblePromoIdentity(surfaceID: triggeringSurfaceID, promoType: .remoteMessage, promoID: "trigger")
        )

        guard case .acquired = result else {
            Issue.record("Expected triggering visible promo to acquire before retries")
            return
        }
        #expect(triggeringTarget.retryCount == 0)
        #expect(otherTarget.retryCount == 1)
        #expect(promoQueueLeaseArbiter.snapshot.visiblePromoCount == 2)
    }

    @Test("Stale Registration Cannot Remove Or Invoke Its Replacement")
    func whenRegistrationIsReplacedThenOldTokenCannotRemoveReplacement() {
        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let surfaceID = UUID()
        let firstTarget = MockNewTabPagePromoRetryTarget()
        let replacementTarget = MockNewTabPagePromoRetryTarget()
        let firstRegistration = sut.registerVisiblePromoRetry(for: surfaceID, target: firstTarget)
        let replacementRegistration = sut.registerVisiblePromoRetry(for: surfaceID, target: replacementTarget)

        firstRegistration.deregister()
        launchSourceManagerMock.source = .URL
        presenterMock.presentedViewController = nil
        sut.presentModalPromptIfNeeded(from: presenterMock)
        _ = replacementRegistration

        #expect(firstTarget.retryCount == 0)
        #expect(replacementTarget.retryCount == 1)
    }

    // MARK: - Promo Queue Feature State

    @Test("Initial Promo Queue State Is Seeded Before Subscription Updates")
    func whenPromoQueueIsInitiallyEnabledThenInitialStateIsEnabled() {
        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        #expect(sut.promoQueueFeatureState == .enabled)
        #expect(managerMock.promoQueueWillTransitionTargets.isEmpty)
        #expect(managerMock.promoQueueDidTransitionTargets.isEmpty)
        #expect(featureFlaggerMock.updatesPublisherAccessCount == 1)
    }

    @Test("Promo Queue Feature Updates Are Deduplicated")
    func whenFeatureFlagPublishesDuplicateValuesThenOnlyEffectiveChangesTransition() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        let initialGeneration = promoQueueLeaseArbiter.snapshot.generation

        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()
        #expect(managerMock.promoQueueWillTransitionTargets.isEmpty)
        #expect(promoQueueLeaseArbiter.snapshot.generation == initialGeneration)

        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()
        let enabledGeneration = promoQueueLeaseArbiter.snapshot.generation
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(managerMock.promoQueueWillTransitionTargets == [.enabled])
        #expect(managerMock.promoQueueDidTransitionTargets == [.enabled])
        #expect(sut.promoQueueFeatureState == .enabled)
        #expect(featureFlaggerMock.updatesPublisherAccessCount == 1)
        #expect(enabledGeneration != initialGeneration)
        #expect(promoQueueLeaseArbiter.snapshot.generation == enabledGeneration)
    }

    @Test("Promo Queue Feature Subscription Is Cancelled With Service")
    func whenServiceIsReleasedThenFeatureUpdatesStop() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        weak var weakService = sut

        sut = nil
        #expect(weakService == nil)

        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(managerMock.promoQueueWillTransitionTargets.isEmpty)
        #expect(managerMock.promoQueueDidTransitionTargets.isEmpty)
    }

    @Test("Promo Queue Transition Barrier Rejects Reentrant Modal Evaluation In Both Directions")
    func whenTransitionCallbacksReenterModalEvaluationThenEvaluationWaitsForBarrier() async {
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            modalPromptCoordinationManager: managerMock,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
        launchSourceManagerMock.source = .standard
        presenterMock.presentedViewController = nil

        var statesObservedDuringCallbacks = [PromoQueueFeatureState]()
        managerMock.onPromoQueueWillTransition = { [weak self] _ in
            guard let self else { return }
            statesObservedDuringCallbacks.append(sut.promoQueueFeatureState)
            sut.presentModalPromptIfNeeded(from: presenterMock)
        }
        managerMock.onPromoQueueDidTransition = { [weak self] _ in
            guard let self else { return }
            statesObservedDuringCallbacks.append(sut.promoQueueFeatureState)
            sut.presentModalPromptIfNeeded(from: presenterMock)
        }

        featureFlaggerMock.enabledFeatureFlags = [.promoQueue]
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()
        featureFlaggerMock.enabledFeatureFlags = []
        featureFlaggerMock.triggerUpdate()
        await waitForFeatureFlagUpdateDelivery()

        #expect(managerMock.callCount == 0)
        #expect(
            statesObservedDuringCallbacks == [
                .transitioning(to: .enabled),
                .transitioning(to: .enabled),
                .transitioning(to: .disabled),
                .transitioning(to: .disabled),
            ]
        )
        #expect(sut.promoQueueFeatureState == .disabled)
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
        let keyValueStore = try MockKeyValueFileStore()
        let privacyConfigManager = MockPrivacyConfigurationManager()

        let providers = ModalPromptProviders(
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

        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            keyValueStore: keyValueStore,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            privacyConfigManager: privacyConfigManager,
            providers: providers,
            featureFlagger: featureFlaggerMock,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
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

    private func waitForFeatureFlagUpdateDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
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

@MainActor
private final class MockNewTabPagePromoRetryTarget: NewTabPagePromoRetrying {
    var isActiveForPromoRetry = true
    var onRetry: (@MainActor () -> Void)?
    private(set) var retryCount = 0

    func retryVisiblePromoAdmission() {
        retryCount += 1
        onRetry?()
    }
}

private final class MockSwitchBarHandler: SwitchBarHandling {
    var currentText: String = ""
    var currentToggleState: TextEntryMode = .search
    var isVoiceSearchEnabled: Bool = false
    var hasUserInteractedWithText: Bool = false
    var isCurrentTextValidURL: Bool = false
    var buttonState: SwitchBarButtonState = .noButtons
    var isTopBarPosition: Bool = true
    var isToggleEnabled: Bool = false
    var isFireTab: Bool = false
    var hidesVoiceButton: Bool = false
    var isUsingExpandedBottomBarHeight: Bool = false
    var isUsingFadeOutAnimation: Bool = false
    var shouldDisableAutocorrectOnEmpty: Bool = false
    var hasSubmittedPrompt: Bool = false
    let isAIVoiceChatEnabled: Bool = false
    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { Empty().eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { Empty().eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { Empty().eraseToAnyPublisher() }
    var modeParameters: [String: String] { [:] }
    func updateCurrentText(_ text: String) {}
    func submitText(_ text: String) {}
    func setToggleState(_ state: TextEntryMode) {}
    func clearText() {}
    func microphoneButtonTapped() {}
    func markUserInteraction() {}
    func clearButtonTapped() {}
    func stopGeneratingButtonTapped() {}
    func updateBarPosition(isTop: Bool) {}
}
