//
//  UnifiedInputActiveStateTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

final class UnifiedInputActiveStateTests: XCTestCase {

    private var dependencies: MockOmnibarDependency!

    override func setUp() {
        super.setUp()
        let voiceSearch = MockVoiceSearchHelper(isSpeechRecognizerAvailable: false)
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        dependencies = MockOmnibarDependency(voiceSearchHelper: voiceSearch, featureFlagger: featureFlagger)
    }

    override func tearDown() {
        dependencies = nil
        super.tearDown()
    }

    private func makeBrowsingState() -> SmallOmniBarState.BrowsingNonEditingState {
        SmallOmniBarState.BrowsingNonEditingState(dependencies: dependencies, isLoading: false)
    }

    private func makeHomeState() -> SmallOmniBarState.HomeNonEditingState {
        SmallOmniBarState.HomeNonEditingState(dependencies: dependencies, isLoading: false)
    }

    private func makeActiveState(wrapping base: OmniBarState) -> UniversalOmniBarState.UnifiedInputActiveState {
        UniversalOmniBarState.UnifiedInputActiveState(baseState: base, dependencies: dependencies, isLoading: false)
    }

    // MARK: - Properties

    func testHidesOmniBarIsTrue() {
        let sut = makeActiveState(wrapping: makeBrowsingState())
        XCTAssertTrue(sut.hidesOmniBar)
    }

    func testAllButtonVisibilityIsFalse() {
        let sut = makeActiveState(wrapping: makeBrowsingState())
        XCTAssertFalse(sut.showBackButton)
        XCTAssertFalse(sut.showForwardButton)
        XCTAssertFalse(sut.showBookmarksButton)
        XCTAssertFalse(sut.showAIChatButton)
        XCTAssertFalse(sut.showSearchLoupe)
        XCTAssertFalse(sut.showCancel)
        XCTAssertFalse(sut.showPrivacyIcon)
        XCTAssertFalse(sut.showBackground)
        XCTAssertFalse(sut.showClear)
        XCTAssertFalse(sut.showRefresh)
        XCTAssertFalse(sut.showCustomizableButton)
        XCTAssertFalse(sut.showMenu)
        XCTAssertFalse(sut.showSettings)
        XCTAssertFalse(sut.showVoiceSearch)
        XCTAssertFalse(sut.showAbort)
        XCTAssertFalse(sut.showDismiss)
        XCTAssertFalse(sut.isBrowsing)
        XCTAssertFalse(sut.allowCustomization)
        XCTAssertFalse(sut.clearTextOnStart)
        XCTAssertFalse(sut.allowsTrackersAnimation)
    }

    func testBaseStateHidesOmniBarIsFalse() {
        let base = makeBrowsingState()
        XCTAssertFalse(base.hidesOmniBar)
    }

    // MARK: - Transitions that exit the wrapper (delegate to base)

    func testOnBrowsingStartedExitsWrapper() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onBrowsingStartedState
        XCTAssertFalse(next.hidesOmniBar)
    }

    func testOnBrowsingStoppedExitsWrapper() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onBrowsingStoppedState
        XCTAssertFalse(next.hidesOmniBar)
    }

    func testOnEditingStoppedExitsWrapper() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEditingStoppedState
        XCTAssertFalse(next.hidesOmniBar)
    }

    func testOnEditingStartedExitsWrapper() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEditingStartedState
        XCTAssertFalse(next.hidesOmniBar)
    }

    func testOnTextClearedRestoresBase() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onTextClearedState
        XCTAssertFalse(next.hidesOmniBar)
        XCTAssertEqual(next.name, base.name)
    }

    func testOnTextEnteredRestoresBase() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onTextEnteredState
        XCTAssertFalse(next.hidesOmniBar)
        XCTAssertEqual(next.name, base.name)
    }

    // MARK: - Transitions that stay wrapped (forward through base, re-wrap)

    func testOnEnterPhoneStateStaysWrapped() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEnterPhoneState
        XCTAssertTrue(next.hidesOmniBar)
    }

    func testOnEnterPadStateStaysWrapped() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEnterPadState
        XCTAssertTrue(next.hidesOmniBar)
    }

    func testOnReloadStateStaysWrapped() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onReloadState
        XCTAssertTrue(next.hidesOmniBar)
    }

    func testOnEnterAIChatStateStaysWrapped() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEnterAIChatState
        XCTAssertTrue(next.hidesOmniBar)
    }

    func testOnEditingSuspendedStaysWrapped() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEditingSuspendedState
        XCTAssertTrue(next.hidesOmniBar)
    }

    // MARK: - Base state forwarding updates the wrapped state

    func testOnEnterPhoneStateForwardsThroughBase() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEnterPhoneState
        guard let wrapped = next as? UniversalOmniBarState.UnifiedInputActiveState else {
            return XCTFail("Expected UnifiedInputActiveState, got \(type(of: next))")
        }
        XCTAssertEqual(wrapped.baseState.name, base.onEnterPhoneState.name)
    }

    func testOnEnterPadStateForwardsThroughBase() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEnterPadState
        guard let wrapped = next as? UniversalOmniBarState.UnifiedInputActiveState else {
            return XCTFail("Expected UnifiedInputActiveState, got \(type(of: next))")
        }
        XCTAssertEqual(wrapped.baseState.name, base.onEnterPadState.name)
    }

    func testOnEnterAIChatStateForwardsThroughBase() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let next = sut.onEnterAIChatState
        guard let wrapped = next as? UniversalOmniBarState.UnifiedInputActiveState else {
            return XCTFail("Expected UnifiedInputActiveState, got \(type(of: next))")
        }
        XCTAssertEqual(wrapped.baseState.name, base.onEnterAIChatState.name)
    }

    // MARK: - Loading

    func testWithLoadingPreservesWrapper() {
        let sut = makeActiveState(wrapping: makeBrowsingState())
        let loaded = sut.withLoading()
        XCTAssertTrue(loaded.hidesOmniBar)
        XCTAssertTrue(loaded.isLoading)
    }

    func testWithoutLoadingPreservesWrapper() {
        let sut = UniversalOmniBarState.UnifiedInputActiveState(
            baseState: makeBrowsingState(), dependencies: dependencies, isLoading: true
        )
        let unloaded = sut.withoutLoading()
        XCTAssertTrue(unloaded.hidesOmniBar)
        XCTAssertFalse(unloaded.isLoading)
    }

    // MARK: - Different base states

    func testWrappingHomeStatePreservesBaseOnExit() {
        let base = makeHomeState()
        let sut = makeActiveState(wrapping: base)
        let restored = sut.onTextClearedState
        XCTAssertEqual(restored.name, base.name)
    }

    func testWrappingBrowsingStatePreservesBaseOnExit() {
        let base = makeBrowsingState()
        let sut = makeActiveState(wrapping: base)
        let restored = sut.onTextClearedState
        XCTAssertEqual(restored.name, base.name)
    }
}
