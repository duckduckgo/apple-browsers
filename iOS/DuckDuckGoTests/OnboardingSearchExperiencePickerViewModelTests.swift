//
//  OnboardingSearchExperiencePickerViewModelTests.swift
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

import XCTest
@testable import DuckDuckGo

final class OnboardingSearchExperiencePickerViewModelTests: XCTestCase {
    private var mockSearchExperienceProvider: ObservingMockOnboardingSearchExperienceProvider!
    private var sut: OnboardingSearchExperiencePickerViewModel!
    
    override func setUp() {
        super.setUp()
        mockSearchExperienceProvider = ObservingMockOnboardingSearchExperienceProvider()
        sut = OnboardingSearchExperiencePickerViewModel(searchExperienceProvider: mockSearchExperienceProvider)
    }
    
    override func tearDown() {
        mockSearchExperienceProvider = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: - isSearchAndAIChatEnabled Binding Tests
    
    func testWhenSettingIsSearchAndAIChatEnabledToTrueThenStoreAIChatSearchInputDuringOnboardingChoiceIsCalled() {
        // Given
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = false
        XCTAssertFalse(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        
        // When
        sut.isSearchAndAIChatEnabled.wrappedValue = true
        
        // Then
        XCTAssertTrue(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        XCTAssertEqual(mockSearchExperienceProvider.lastEnableValue, true)
    }
    
    func testWhenSettingIsSearchAndAIChatEnabledToFalseThenStoreAIChatSearchInputDuringOnboardingChoiceIsCalled() {
        // Given
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        XCTAssertFalse(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        
        // When
        sut.isSearchAndAIChatEnabled.wrappedValue = false
        
        // Then
        XCTAssertTrue(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        XCTAssertEqual(mockSearchExperienceProvider.lastEnableValue, false)
    }
    
    func testWhenGettingIsSearchAndAIChatEnabledThenReturnsProviderValue() {
        // Given
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        
        // When
        let result = sut.isSearchAndAIChatEnabled.wrappedValue
        
        // Then
        XCTAssertTrue(result)
    }
    
    // MARK: - confirmChoice Tests
    
    func testWhenConfirmChoiceIsCalledThenStoresCurrentChoice() {
        // Given
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        XCTAssertFalse(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        
        // When
        sut.confirmChoice()
        
        // Then
        XCTAssertTrue(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        XCTAssertEqual(mockSearchExperienceProvider.lastEnableValue, true)
    }
    
    func testWhenConfirmChoiceIsCalledWithDefaultValueThenStoresChoice() {
        // Given
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = false
        XCTAssertFalse(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        
        // When
        sut.confirmChoice()
        
        // Then
        XCTAssertTrue(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        XCTAssertEqual(mockSearchExperienceProvider.lastEnableValue, false)
    }
}

// MARK: - ObservingMockOnboardingSearchExperienceProvider

private final class ObservingMockOnboardingSearchExperienceProvider: OnboardingSearchExperienceProvider {
    var didEnableAIChatSearchInputDuringOnboarding = false
    var didMakeChoiceDuringOnboarding = false
    var didApplyOnboardingChoiceSettings = false
    
    var storeAIChatSearchInputDuringOnboardingChoiceCalled = false
    var lastEnableValue: Bool?
    
    func storeAIChatSearchInputDuringOnboardingChoice(enable: Bool) {
        storeAIChatSearchInputDuringOnboardingChoiceCalled = true
        lastEnableValue = enable
    }
}
