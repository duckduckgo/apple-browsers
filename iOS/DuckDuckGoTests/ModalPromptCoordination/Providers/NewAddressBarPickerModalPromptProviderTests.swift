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


    @Test("Check Configuration Sets Cover Vertical Transition Style")
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
        #expect(configuration?.transitionStyle == .coverVertical)
    }

    @Test("Check Configuration Sets Should Disable Pull Down To Dismiss True")
    func whenProvideModalPromptCalledThenSetsShouldDisablePullDownToDismissToTrue() {
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
        #expect(configuration?.shouldDisablePullDownToDismiss == true)
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

    @Test("Check Configuration Sets Page Sheet Presentation Style On iPhone")
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
        #expect(configuration?.presentationStyle == .pageSheet)
    }

    @Test("Check Configuration Sets Page Sheet Presentation Style on iPad iOS < 26", .disabled(if: Self.isOS26))
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
        #expect(configuration?.presentationStyle == .pageSheet)
    }

    @available(iOS 26.0, *)
    @Test("Check Configuration Sets Form Sheet Presentation Style on iPad iOS 26+")
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
        #expect(configuration?.presentationStyle == .formSheet)
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
