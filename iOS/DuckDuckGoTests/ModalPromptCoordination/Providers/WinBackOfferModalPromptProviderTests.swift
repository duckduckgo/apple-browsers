//
//  WinBackOfferModalPromptProviderTests.swift
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
@Suite("Modal Prompt Coordination - WinBack Offer Modal Prompt Provider")
final class WinBackOfferModalPromptProviderTests {
    
    @Test("Check No Prompt Configuration When Coordinator Says Not Eligible")
    func whenCoordinatorReturnsNotEligibleThenProvideModalPromptReturnsNil() {
        // GIVEN
        let mockCoordinator = MockWinBackOfferCoordinator(shouldPresentLaunchPrompt: false)
        let mockPresenter = MockWinBackOfferPresenter()
        let sut = WinBackOfferModalPromptProvider(presenter: mockPresenter, coordinator: mockCoordinator)
        
        // WHEN
        let result = sut.provideModalPrompt()
        
        // THEN
        #expect(result == nil)
        #expect(mockCoordinator.didCallShouldPresentLaunchPrompt)
        #expect(!mockPresenter.didCallMakeWinBackOfferPrompt)
    }
    
    @Test("Check Prompt Configuration When Coordinator Says Eligible")
    func whenCoordinatorReturnsEligibleThenProvideModalPromptReturnsConfiguration() {
        // GIVEN
        let mockCoordinator = MockWinBackOfferCoordinator(shouldPresentLaunchPrompt: true)
        let mockPresenter = MockWinBackOfferPresenter()
        let sut = WinBackOfferModalPromptProvider(presenter: mockPresenter, coordinator: mockCoordinator)
        
        // WHEN
        let result = sut.provideModalPrompt()
        
        // THEN
        #expect(result != nil)
        #expect(result?.viewController != nil)
        #expect(result?.animated == true)
        #expect(mockCoordinator.didCallShouldPresentLaunchPrompt)
        #expect(mockPresenter.didCallMakeWinBackOfferPrompt)
    }
    
    @Test("Check didPresentModal Marks Launch Prompt As Presented")
    func whenDidPresentModalIsCalledThenCoordinatorMarksPromptAsPresented() {
        // GIVEN
        let mockCoordinator = MockWinBackOfferCoordinator(shouldPresentLaunchPrompt: true)
        let mockPresenter = MockWinBackOfferPresenter()
        let sut = WinBackOfferModalPromptProvider(presenter: mockPresenter, coordinator: mockCoordinator)
        
        // WHEN
        sut.didPresentModal()
        
        // THEN
        #expect(mockCoordinator.didCallMarkLaunchPromptPresented)
    }
}
