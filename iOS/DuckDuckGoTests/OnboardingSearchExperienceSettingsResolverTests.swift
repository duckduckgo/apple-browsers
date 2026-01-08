//
//  OnboardingSearchExperienceSettingsResolverTests.swift
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
@testable import Core

final class OnboardingSearchExperienceSettingsResolverTests: XCTestCase {
    private var sut: OnboardingSearchExperienceSettingsResolver!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockOnboardingProvider: MockOnboardingSearchExperienceProvider!
    private var mockDaxDialogsStatusProvider: MockContextualOnboardingStatusProvider!
    
    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockOnboardingProvider = MockOnboardingSearchExperienceProvider()
        mockDaxDialogsStatusProvider = MockContextualOnboardingStatusProvider(hasSeenOnboarding: false)
    }
    
    override func tearDown() {
        sut = nil
        mockFeatureFlagger = nil
        mockOnboardingProvider = nil
        mockDaxDialogsStatusProvider = nil
        super.tearDown()
    }
    
    private func createSUT() {
        sut = OnboardingSearchExperienceSettingsResolver(
            featureFlagger: mockFeatureFlagger,
            onboardingProvider: mockOnboardingProvider,
            daxDialogsStatusProvider: mockDaxDialogsStatusProvider
        )
    }
    
    // MARK: - shouldUseDeferredOnboardingChoice Tests
    
    func testShouldUseDeferredOnboardingChoice_WhenAllConditionsMet_ReturnsTrue() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // Then
        XCTAssertTrue(sut.shouldUseDeferredOnboardingChoice)
    }
    
    func testShouldUseDeferredOnboardingChoice_WhenFeatureFlagDisabled_ReturnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // Then
        XCTAssertFalse(sut.shouldUseDeferredOnboardingChoice)
    }
    
    func testShouldUseDeferredOnboardingChoice_WhenNoChoiceMadeDuringOnboarding_ReturnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = false
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // Then
        XCTAssertFalse(sut.shouldUseDeferredOnboardingChoice)
    }
    
    func testShouldUseDeferredOnboardingChoice_WhenSettingsAlreadyApplied_ReturnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = true
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // Then
        XCTAssertFalse(sut.shouldUseDeferredOnboardingChoice)
    }
    
    func testShouldUseDeferredOnboardingChoice_WhenOnboardingComplete_ReturnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockDaxDialogsStatusProvider.hasSeenOnboarding = true
        createSUT()
        
        // Then
        XCTAssertFalse(sut.shouldUseDeferredOnboardingChoice)
    }
    
    // MARK: - deferredValue Tests
    
    func testDeferredValue_WhenInDeferredMode_ReturnsOnboardingChoice() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = true
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // Then
        XCTAssertEqual(sut.deferredValue, true)
    }
    
    func testDeferredValue_WhenInDeferredModeWithFalseChoice_ReturnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = false
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // Then
        XCTAssertEqual(sut.deferredValue, false)
    }
    
    func testDeferredValue_WhenNotInDeferredMode_ReturnsNil() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = true
        createSUT()
        
        // Then
        XCTAssertNil(sut.deferredValue)
    }
    
    // MARK: - storeIfDeferred Tests
    
    func testStoreIfDeferred_WhenInDeferredMode_ChangesFromFalseToTrue_StoresValueAndReturnsTrue() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = false
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // When
        let result = sut.storeIfDeferred(true)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertTrue(mockOnboardingProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        XCTAssertEqual(mockOnboardingProvider.lastStoredValue, true)
    }
    
    func testStoreIfDeferred_WhenInDeferredMode_ChangesFromTrueToFalse_StoresValueAndReturnsTrue() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = true
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // When
        let result = sut.storeIfDeferred(false)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertTrue(mockOnboardingProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        XCTAssertEqual(mockOnboardingProvider.lastStoredValue, false)
    }
    
    func testStoreIfDeferred_WhenNotInDeferredMode_DoesNotStoreAndReturnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        createSUT()
        
        // When
        let result = sut.storeIfDeferred(true)
        
        // Then
        XCTAssertFalse(result)
        XCTAssertFalse(mockOnboardingProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
    }
    
    func testStoreIfDeferred_WhenValueUnchanged_DoesNotStoreAndReturnsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = true
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        // When
        let result = sut.storeIfDeferred(true) // Same value as current
        
        // Then
        XCTAssertFalse(result)
        XCTAssertFalse(mockOnboardingProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
    }
    
    // MARK: - Transition Tests
    
    func testTransitionFromDeferredToNonDeferred_WhenOnboardingCompletes() {
        // Given - Start in deferred mode
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = true
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        XCTAssertTrue(sut.shouldUseDeferredOnboardingChoice)
        XCTAssertEqual(sut.deferredValue, true)
        
        // When - Onboarding completes
        mockDaxDialogsStatusProvider.hasSeenOnboarding = true
        
        // Then - Should no longer be in deferred mode
        XCTAssertFalse(sut.shouldUseDeferredOnboardingChoice)
        XCTAssertNil(sut.deferredValue)
    }
    
    func testTransitionFromDeferredToNonDeferred_WhenSettingsApplied() {
        // Given - Start in deferred mode
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockOnboardingProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingProvider.didEnableAIChatSearchInputDuringOnboarding = true
        mockDaxDialogsStatusProvider.hasSeenOnboarding = false
        createSUT()
        
        XCTAssertTrue(sut.shouldUseDeferredOnboardingChoice)
        
        // When - Settings are applied
        mockOnboardingProvider.didApplyOnboardingChoiceSettings = true
        
        // Then - Should no longer be in deferred mode
        XCTAssertFalse(sut.shouldUseDeferredOnboardingChoice)
        XCTAssertNil(sut.deferredValue)
    }
}
