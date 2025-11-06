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
    private var sut: ModalPromptCoordinationService!

    init() {
        launchSourceManagerMock = MockLaunchSourceManager()
        contextualOnboardingMock = MockContextualOnboardingStatusProvider(hasSeenOnboarding: true)
        managerMock = MockModalPromptCoordinationManager()
        presenterMock = MockModalPromptPresenter()
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
        contextualOnboardingMock.hasSeenOnboarding = true
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
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
        contextualOnboardingMock.hasSeenOnboarding = true
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
        #expect(managerMock.capturedPresenter === presenterMock)
    }

    // MARK: - Onboarding Checks

    @Test("Check Modal Is Not Presented When Onboarding Is Not Completed")
    func whenOnboardingNotCompletedThenModalIsNotPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        contextualOnboardingMock.hasSeenOnboarding = false
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Check Modal Is Presented When Onboarding Is Completed")
    func whenOnboardingCompletedThenModalIsPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        contextualOnboardingMock.hasSeenOnboarding = true
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(managerMock.didCallPresentModalPromptIfNeeded)
    }

    // MARK: - Presented View Controller Checks

    @Test("Check Modal Is Not Presented When Another Modal Is Already Presented")
    func whenAnotherModalIsPresentedThenModalIsNotPresented() {
        // GIVEN
        launchSourceManagerMock.source = .standard
        contextualOnboardingMock.hasSeenOnboarding = true
        let alreadyPresentedVC = UIViewController()
        presenterMock.presentedViewController = alreadyPresentedVC
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
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
        contextualOnboardingMock.hasSeenOnboarding = true
        presenterMock.presentedViewController = nil
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
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
        contextualOnboardingMock.hasSeenOnboarding = true
        let dismissingVC = MockDismissingViewController()
        dismissingVC.isBeingDismissed = true
        presenterMock.presentedViewController = dismissingVC
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
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
        contextualOnboardingMock.hasSeenOnboarding = false
        presenterMock.presentedViewController = UIViewController()
        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            modalPromptCoordinationManager: managerMock
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(!managerMock.didCallPresentModalPromptIfNeeded)
    }

    @Test("Check Priority Order For First Item")
    func whenFirstPriorityProviderCanPresentModalThenFirstProviderReturnsModal() throws {
        // GIVEN
        let keyValueStore = try MockKeyValueFileStore()
        let privacyConfigManager = MockPrivacyConfigurationManager()
        let newAddressBarPickerProvider = MockModalPromptProvider()
        let defaultBrowserProvider = MockModalPromptProvider()
        let winBackOfferProvider = MockModalPromptProvider()
        let providers = ModalPromptProviders(
            newAddressBarPicker: newAddressBarPickerProvider,
            defaultBrowser: defaultBrowserProvider,
            winBackOffer: winBackOfferProvider
        )
        launchSourceManagerMock.source = .standard
        contextualOnboardingMock.hasSeenOnboarding = true
        presenterMock.presentedViewController = nil

        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            keyValueStore: keyValueStore,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            privacyConfigManager: privacyConfigManager,
            providers: providers
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(winBackOfferProvider.didCallProvideModalPrompt)
        #expect(!newAddressBarPickerProvider.didCallProvideModalPrompt)
        #expect(!defaultBrowserProvider.didCallProvideModalPrompt)
    }

    @Test("Check Priority Order For Second Item")
    func whenFirstPriorityProviderCannotPresentModalThenSecondProviderReturnsModal() throws {
        // GIVEN
        let keyValueStore = try MockKeyValueFileStore()
        let privacyConfigManager = MockPrivacyConfigurationManager()
        let newAddressBarPickerProvider = MockModalPromptProvider()
        let defaultBrowserProvider = MockModalPromptProvider()
        let winBackOfferProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let providers = ModalPromptProviders(
            newAddressBarPicker: newAddressBarPickerProvider,
            defaultBrowser: defaultBrowserProvider,
            winBackOffer: winBackOfferProvider
        )
        launchSourceManagerMock.source = .standard
        contextualOnboardingMock.hasSeenOnboarding = true
        presenterMock.presentedViewController = nil

        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            keyValueStore: keyValueStore,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            privacyConfigManager: privacyConfigManager,
            providers: providers
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(winBackOfferProvider.didCallProvideModalPrompt)
        #expect(newAddressBarPickerProvider.didCallProvideModalPrompt)
        #expect(!defaultBrowserProvider.didCallProvideModalPrompt)
    }

    @Test("Check Priority Order For Third Item")
    func whenSecondPriorityProviderCannotPresentModalThenThirdProviderReturnsModal() throws {
        // GIVEN
        let keyValueStore = try MockKeyValueFileStore()
        let privacyConfigManager = MockPrivacyConfigurationManager()
        let newAddressBarPickerProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let defaultBrowserProvider = MockModalPromptProvider()
        let winBackOfferProvider = MockModalPromptProvider(shouldReturnPrompt: false)
        let providers = ModalPromptProviders(
            newAddressBarPicker: newAddressBarPickerProvider,
            defaultBrowser: defaultBrowserProvider,
            winBackOffer: winBackOfferProvider
        )
        launchSourceManagerMock.source = .standard
        contextualOnboardingMock.hasSeenOnboarding = true
        presenterMock.presentedViewController = nil

        sut = ModalPromptCoordinationService(
            launchSourceManager: launchSourceManagerMock,
            keyValueStore: keyValueStore,
            contextualOnboardingStatusProvider: contextualOnboardingMock,
            privacyConfigManager: privacyConfigManager,
            providers: providers
        )

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(winBackOfferProvider.didCallProvideModalPrompt)
        #expect(newAddressBarPickerProvider.didCallProvideModalPrompt)
        #expect(defaultBrowserProvider.didCallProvideModalPrompt)
    }

}

private final class MockDismissingViewController: UIViewController {
    private var _isBeingDismissed = false

    override var isBeingDismissed: Bool {
        get { _isBeingDismissed }
        set { _isBeingDismissed = newValue }
    }
}
