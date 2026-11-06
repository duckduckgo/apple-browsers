//
//  DefaultBrowserAndDockActionPerformerTests.swift
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

import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockActionPerformerTests: XCTestCase {

    private var dockCustomizer: DockCustomizerMock!
    private var defaultBrowserProvider: CapturingDefaultBrowserProvider!
    private var sut: DefaultBrowserAndDockActionPerformer!

    override func setUp() {
        super.setUp()
        dockCustomizer = DockCustomizerMock()
        defaultBrowserProvider = CapturingDefaultBrowserProvider()
        sut = DefaultBrowserAndDockActionPerformer(dockCustomization: dockCustomizer, defaultBrowserProvider: defaultBrowserProvider)
    }

    override func tearDown() {
        sut = nil
        defaultBrowserProvider = nil
        dockCustomizer = nil
        super.tearDown()
    }

    // MARK: - pendingPromptType

    func testWhenDockSupportedAndNeitherDoneThenPendingTypeIsBoth() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = false

        XCTAssertEqual(sut.pendingPromptType, .bothDefaultBrowserAndDockPrompt)
    }

    func testWhenDockSupportedAndDefaultOnlyThenPendingTypeIsAddToDock() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = true

        XCTAssertEqual(sut.pendingPromptType, .addToDockPrompt)
    }

    func testWhenDockSupportedAndInDockOnlyThenPendingTypeIsSetAsDefault() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = true
        defaultBrowserProvider.isDefault = false

        XCTAssertEqual(sut.pendingPromptType, .setAsDefaultPrompt)
    }

    func testWhenDockSupportedAndBothDoneThenPendingTypeIsNil() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = true
        defaultBrowserProvider.isDefault = true

        XCTAssertNil(sut.pendingPromptType)
    }

    func testWhenDockUnsupportedAndNotDefaultThenPendingTypeIsSetAsDefault() {
        dockCustomizer.supportsAddingToDock = false
        defaultBrowserProvider.isDefault = false

        XCTAssertEqual(sut.pendingPromptType, .setAsDefaultPrompt)
    }

    func testWhenDockUnsupportedAndDefaultThenPendingTypeIsNil() {
        dockCustomizer.supportsAddingToDock = false
        defaultBrowserProvider.isDefault = true

        XCTAssertNil(sut.pendingPromptType)
    }

    // MARK: - performPendingActions

    func testWhenBothPendingThenPerformAddsToDockAndPresentsPrompt() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = false

        sut.performPendingActions()

        XCTAssertTrue(dockCustomizer.wasAddToDockCalled)
        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    func testWhenAddToDockPendingThenPerformOnlyAddsToDock() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = true

        sut.performPendingActions()

        XCTAssertTrue(dockCustomizer.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    func testWhenPresentingPromptThrowsThenPerformOpensSystemPreferences() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = true
        defaultBrowserProvider.isDefault = false
        defaultBrowserProvider.throwError = true

        sut.performPendingActions()

        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertTrue(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    func testWhenNothingPendingThenPerformDoesNothing() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = true
        defaultBrowserProvider.isDefault = true

        sut.performPendingActions()

        XCTAssertFalse(dockCustomizer.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }
}
