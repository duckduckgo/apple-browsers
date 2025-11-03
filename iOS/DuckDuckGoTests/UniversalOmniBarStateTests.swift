//
//  UniversalOmniBarStateTests.swift
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

import Foundation
import XCTest
@testable import DuckDuckGo

final class UniversalOmniBarStateTests: XCTestCase {

    let enabledVoiceSearchHelper = MockVoiceSearchHelper(isSpeechRecognizerAvailable: true)
    let disabledVoiceSearchHelper = MockVoiceSearchHelper(isSpeechRecognizerAvailable: false)
    var mockFeatureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        super.tearDown()
    }

    // MARK: - AI Chat Mode State Tests

    func testWhenInAIChatModeStateThenCorrectPropertiesAreSet() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)

        // When
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // Then
        XCTAssertTrue(sut.showAIChatFullModeBranding)
        XCTAssertFalse(sut.showBackButton)
        XCTAssertFalse(sut.showForwardButton)
        XCTAssertFalse(sut.showBookmarksButton)
        XCTAssertFalse(sut.showClear)
        XCTAssertFalse(sut.showMenu)
        XCTAssertFalse(sut.showSettings)
        XCTAssertFalse(sut.showCancel)
        XCTAssertFalse(sut.showDismiss)
        XCTAssertFalse(sut.showSearchLoupe)
        XCTAssertFalse(sut.showVoiceSearch)
        XCTAssertFalse(sut.showRefresh)
        XCTAssertFalse(sut.showAbort)
        XCTAssertFalse(sut.showCustomizableButton)
        XCTAssertFalse(sut.isBrowsing)
    }

    func testWhenInAIChatModeThenTextIsNotCleared() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)

        // When
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // Then
        XCTAssertFalse(sut.clearTextOnStart)
    }

    func testWhenEditingStartsFromAIChatModeThenTransitionsToHomeEmptyEditingState() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onEditingStartedState

        // Then
        XCTAssertEqual(targetState.name, SmallOmniBarState.HomeEmptyEditingState(dependencies: dependencies, isLoading: false).name)
    }

    func testWhenEditingStartsFromAIChatModeWithLargeWidthThenTransitionsToLargeHomeEmptyEditingState() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = LargeOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onEditingStartedState

        // Then
        XCTAssertEqual(targetState.name, LargeOmniBarState.HomeEmptyEditingState(dependencies: dependencies, isLoading: false).name)
    }

    func testWhenTextIsEnteredFromAIChatModeThenTransitionsToHomeTextEditingState() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onTextEnteredState

        // Then
        XCTAssertEqual(targetState.name, SmallOmniBarState.HomeTextEditingState(dependencies: dependencies, isLoading: false).name)
    }

    func testWhenTextIsClearedFromAIChatModeThenTransitionsToHomeEmptyEditingState() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onTextClearedState

        // Then
        XCTAssertEqual(targetState.name, SmallOmniBarState.HomeEmptyEditingState(dependencies: dependencies, isLoading: false).name)
    }

    func testWhenBrowsingStartsFromAIChatModeThenTransitionsToBrowsingNonEditingState() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onBrowsingStartedState

        // Then
        XCTAssertEqual(targetState.name, SmallOmniBarState.BrowsingNonEditingState(dependencies: dependencies, isLoading: false).name)
    }

    func testWhenEditingStopsFromAIChatModeThenMaintainsAIChatMode() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onEditingStoppedState

        // Then
        XCTAssertTrue(targetState is UniversalOmniBarState.AIChatModeState)
    }

    func testWhenBrowsingStopsFromAIChatModeThenMaintainsAIChatMode() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onBrowsingStoppedState

        // Then
        XCTAssertTrue(targetState is UniversalOmniBarState.AIChatModeState)
    }

    func testWhenEnteringPadStateFromSmallAIChatModeThenTransitionsToLargeAIChatMode() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onEnterPadState

        // Then
        XCTAssertTrue(targetState is UniversalOmniBarState.AIChatModeState)
    }

    func testWhenEnteringPhoneStateFromLargeAIChatModeThenTransitionsToSmallAIChatMode() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = LargeOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onEnterPhoneState

        // Then
        XCTAssertTrue(targetState is UniversalOmniBarState.AIChatModeState)
    }

    func testWhenReloadingFromAIChatModeThenMaintainsAIChatMode() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // When
        let targetState = sut.onReloadState

        // Then
        XCTAssertTrue(targetState is UniversalOmniBarState.AIChatModeState)
    }

    func testWhenAIChatModeStateHasLargeWidthBaseThenHasLargeWidthIsTrue() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = LargeOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)

        // When
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // Then
        XCTAssertTrue(sut.hasLargeWidth)
    }

    func testWhenAIChatModeStateHasSmallWidthBaseThenHasLargeWidthIsFalse() {
        // Given
        let dependencies = MockOmnibarDependency(voiceSearchHelper: disabledVoiceSearchHelper, featureFlagger: mockFeatureFlagger)
        let baseState = SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)

        // When
        let sut = UniversalOmniBarState.AIChatModeState(baseState: baseState, dependencies: dependencies, isLoading: false)

        // Then
        XCTAssertFalse(sut.hasLargeWidth)
    }

}
