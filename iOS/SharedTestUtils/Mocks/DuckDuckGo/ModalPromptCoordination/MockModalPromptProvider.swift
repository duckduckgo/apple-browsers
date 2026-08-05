//
//  MockModalPromptProvider.swift
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
@testable import DuckDuckGo

@MainActor
final class MockModalPromptProvider: ModalPromptProvider {
    var modalConfigurationToReturn: ModalPromptConfiguration?
    var replacementModalConfigurationToReturn: ModalPromptConfiguration?
    var isEligibleToPresentResult: Bool?
    var isPreparedModalPromptStillValidResult = true
    var isRetainedPreparedModalPromptStillValidResult: Bool?

    private(set) var didCallProvideModalPrompt = false
    private(set) var didCallDidPresentModal = false
    private(set) var provideModalPromptCallCount = 0
    private(set) var didPresentModalCallCount = 0
    private(set) var isPreparedModalPromptStillValidCallCount = 0
    private(set) var isRetainedPreparedModalPromptStillValidCallCount = 0
    private(set) var provideReplacementModalPromptCallCount = 0
    private(set) var capturedIsOnboardingComplete: Bool?

    init(shouldReturnPrompt: Bool = true) {
        if shouldReturnPrompt {
            modalConfigurationToReturn = ModalPromptConfiguration(
                viewController: UIViewController(),
                animated: true
            )
        }
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        didCallProvideModalPrompt = true
        provideModalPromptCallCount += 1
        return modalConfigurationToReturn
    }

    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool {
        capturedIsOnboardingComplete = isOnboardingComplete
        return isEligibleToPresentResult ?? isOnboardingComplete
    }

    func isPreparedModalPromptStillValid(_ configuration: ModalPromptConfiguration) -> Bool {
        isPreparedModalPromptStillValidCallCount += 1
        guard configuration.viewController !== replacementModalConfigurationToReturn?.viewController else {
            return true
        }
        return isPreparedModalPromptStillValidResult
    }

    func isRetainedPreparedModalPromptStillValid(_ configuration: ModalPromptConfiguration) -> Bool {
        isRetainedPreparedModalPromptStillValidCallCount += 1
        return isRetainedPreparedModalPromptStillValidResult ?? isPreparedModalPromptStillValid(configuration)
    }

    func provideReplacementModalPrompt(for invalidConfiguration: ModalPromptConfiguration) -> ModalPromptConfiguration? {
        provideReplacementModalPromptCallCount += 1
        return replacementModalConfigurationToReturn
    }

    func didPresentModal() {
        didCallDidPresentModal = true
        didPresentModalCallCount += 1
    }

    func reset() {
        didCallProvideModalPrompt = false
        didCallDidPresentModal = false
        provideModalPromptCallCount = 0
        didPresentModalCallCount = 0
        isPreparedModalPromptStillValidCallCount = 0
        isRetainedPreparedModalPromptStillValidCallCount = 0
        provideReplacementModalPromptCallCount = 0
        capturedIsOnboardingComplete = nil
        isEligibleToPresentResult = nil
        isPreparedModalPromptStillValidResult = true
        isRetainedPreparedModalPromptStillValidResult = nil
        replacementModalConfigurationToReturn = nil
    }
}
