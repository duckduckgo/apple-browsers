//
//  NewAddressBarPickerModalPromptProviderTests.swift
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
import AIChat
import PersistenceTestingUtils
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - New Address Bar Picker Modal Prompt Provider")
final class NewAddressBarPickerModalPromptProviderTests {

    static let isOS26: Bool = {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }()

    @Test("Check No Prompt Configuration Is Returned When Validator Returns False")
    func whenValidatorReturnsFalseThenProvideModalPromptReturnsNil() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: false)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )

        // WHEN
        let result = sut.provideModalPrompt()

        // THEN
        #expect(result == nil)
        #expect(validator.didCallShouldDisplayNewAddressBarPicker)
    }

    @Test("Check Prompt Configuration Is Returned When Validator Returns True")
    func whenValidatorReturnsTrueThenProvideModalPromptReturnsConfiguration() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )

        // WHEN
        let result = sut.provideModalPrompt()

        // THEN
        #expect(validator.didCallShouldDisplayNewAddressBarPicker)
        #expect(result != nil)
    }

    @Test("Check Configuration Sets NewAddressBarPickerViewController")
    func whenValidatorReturnsTrueThenCreatesNewAddressBarPickerViewController() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController is NewAddressBarPickerViewController)
    }


    @Test("Check View Controller Sets Cover Vertical Transition Style")
    func whenProvideModalPromptCalledThenSetsCoverVerticalTransitionStyle() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalTransitionStyle == .coverVertical)
    }

    @Test("Check View Controller Sets Is Modal In Presentation To True")
    func whenProvideModalPromptCalledThenSetsIsModalInPresentationToTrue() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.isModalInPresentation == true)
    }

    @Test("Check Configuration Sets Animated To True")
    func whenProvideModalPromptCalledThenSetsAnimatedToTrue() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.animated == true)
    }

    @Test("Check View Controller Sets Page Sheet Presentation Style On iPhone")
    func whenIsIPadFalseThenUsesPageSheetPresentationStyle() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalPresentationStyle == .pageSheet)
    }

    @Test("Check View Controller Sets Page Sheet Presentation Style on iPad iOS < 26", .disabled(if: Self.isOS26))
    func whenIsIPadTrueAndIOSBelow26ThenUsesPageSheetPresentationStyle() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: true
        )

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalPresentationStyle == .pageSheet)
    }

    @available(iOS 26.0, *)
    @Test("Check View Controller Sets Form Sheet Presentation Style on iPad iOS 26+")
    func whenIsIPadTrueAndIOS26OrAboveThenUsesFormSheetPresentationStyle() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: true
        )

        // WHEN
        let configuration = sut.provideModalPrompt()

        // THEN
        #expect(configuration?.viewController.modalPresentationStyle == .formSheet)
    }

    @Test("Check Did Present Modal Calls Mark As Shown On The Store When Modal Is Presented")
    func whenDidPresentModalCalledThenCallsStoreMarkAsShown() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )
        #expect(!store.didCallMarkAsShown)

        // WHEN
        sut.didPresentModal()

        // THEN
        #expect(store.didCallMarkAsShown)
    }

    @Test("Check Mark As Shown Is Called Only When Did Present Modal Is Called")
    func whenProvideModalPromptCalledThenDoesNotMarkAsShownUntilDidPresentModal() {
        // GIVEN
        let validator = MockNewAddressBarPickerDisplayValidator(shouldDisplayPicker: true)
        let store = MockNewAddressBarPickerStorage()
        let aiChatSettings = MockAIChatSettingsProvider()
        let sut = NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: false
        )
        _ = sut.provideModalPrompt()
        #expect(!store.didCallMarkAsShown)

        // WHEN
        sut.didPresentModal()

        // THEN
        #expect(store.didCallMarkAsShown)
    }
    
}

@MainActor
@Suite("Modal Prompt Coordination - New Address Bar Picker Modal Prompt Provider Integration")
final class NewAddressBarPickerModalPromptProviderIntegrationTests {
    let testUserDefaults: UserDefaults
    let validator: NewAddressBarPickerDisplayValidator
    let pickerStorage: NewAddressBarPickerStore
    let mockAIChatSettings: MockAIChatSettingsProvider

    init() throws {
        testUserDefaults = try #require(UserDefaults(suiteName: String(describing: Self.self)))
        mockAIChatSettings = MockAIChatSettingsProvider()
        mockAIChatSettings.isAIChatEnabled = true
        mockAIChatSettings.isAIChatAddressBarUserSettingsEnabled = true
        let mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.showAIChatAddressBarChoiceScreen]
        let mockAppSettings = AppSettingsMock()
        let mockKeyValueStore = MockKeyValueStore()

        testUserDefaults.set(false, forKey: "experimentalAIChatSettingsEnabled")
        mockKeyValueStore.set(false, forKey: "aichat.storage.newAddressBarPickerShown")

        let experimentalAIChatManager = ExperimentalAIChatManager(
            featureFlagger: mockFeatureFlagger,
            userDefaults: testUserDefaults
        )
        pickerStorage = NewAddressBarPickerStore(keyValueStore: mockKeyValueStore)

        validator = NewAddressBarPickerDisplayValidator(
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            experimentalAIChatManager: experimentalAIChatManager,
            appSettings: mockAppSettings,
            pickerStorage: pickerStorage
        )
    }

    deinit {
        testUserDefaults.removePersistentDomain(forName: String(describing: Self.self))
    }

    @Test("Check Configuration Is Nil After Calling Mark As Shown", arguments: [true, false])
    func whenProvideModalPromptCalledThenDoesNotMarkAsShownUntilDidPresentModal(isIPad: Bool) {
        // GIVEN
        let sut = NewAddressBarPickerModalPromptProvider(validator: validator, store: pickerStorage, aiChatSettings: mockAIChatSettings, isIPad: isIPad)
        #expect(!pickerStorage.hasBeenShown)

        // WHEN we call provide modal prompt for the first time
        let result = sut.provideModalPrompt()

        // THEN the configuration is returned successfully but the flag in the store hasn't been written yet.
        #expect(result != nil)
        #expect(!pickerStorage.hasBeenShown)

        // Mark the modal seen
        sut.didPresentModal()
        #expect(pickerStorage.hasBeenShown)

        // WHEN a new prompt wanted to be shown
        let newResult = sut.provideModalPrompt()

        // THEN no modal should show
        #expect(newResult == nil)
    }
}
