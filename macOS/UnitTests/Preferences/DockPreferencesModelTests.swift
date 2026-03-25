//
//  DockPreferencesModelTests.swift
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

import Combine
import FeatureFlags
import PixelKitTestingUtilities
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DockPreferencesModelTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockDockCustomizer: MockDockCustomization!
    private var windowControllersManager: WindowControllersManagerMock!
    private var mockPixelFiring: PixelKitMock!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockFeatureFlagger = MockFeatureFlagger()
        mockDockCustomizer = MockDockCustomization()
        mockDockCustomizer.supportsAddingToDock = true
        windowControllersManager = WindowControllersManagerMock()
        mockPixelFiring = PixelKitMock()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockDockCustomizer = nil
        windowControllersManager = nil
        mockPixelFiring = nil
        super.tearDown()
    }

    // MARK: - canAddToDock

    func testWhenSupportsAddingToDockIsTrueThenCanAddToDockIsTrue() {
        mockDockCustomizer.supportsAddingToDock = true
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        XCTAssertTrue(model.canAddToDock)
    }

    func testWhenSupportsAddingToDockIsFalseThenCanAddToDockIsFalse() {
        mockDockCustomizer.supportsAddingToDock = false
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        XCTAssertFalse(model.canAddToDock)
    }

    // MARK: - canShowDockInstructions

    func testWhenAddToDockAppStoreFeatureIsOnThenCanShowDockInstructionsIsTrue() {
        mockFeatureFlagger.enabledFeatureFlags = [.addToDockAppStore]
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        XCTAssertTrue(model.canShowDockInstructions)
    }

    func testWhenAddToDockAppStoreFeatureIsOffThenCanShowDockInstructionsIsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        XCTAssertFalse(model.canShowDockInstructions)
    }

    // MARK: - isAddedToDock

    func testWhenNotAddedToDockAndCustomizerReportsFalseThenIsAddedToDockIsFalse() {
        mockDockCustomizer.isAddedToDock = false
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        XCTAssertFalse(model.isAddedToDock)
    }

    func testWhenCustomizerReportsTrueThenIsAddedToDockIsTrue() {
        mockDockCustomizer.isAddedToDock = true
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        XCTAssertTrue(model.isAddedToDock)
    }

    func testWhenAddToDockCalledThenIsAddedToDockIsTrue() {
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        model.addToDock(from: .defaultBrowser)
        XCTAssertTrue(mockDockCustomizer.addToDockCalled)
        XCTAssertTrue(model.isAddedToDock)
    }

    // MARK: - addToDock(from:)

    func testWhenAddToDockCalledFromDefaultBrowserThenDockCustomizerAddToDockIsCalled() {
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        model.addToDock(from: .defaultBrowser)
        XCTAssertTrue(mockDockCustomizer.addToDockCalled)
        XCTAssertTrue(model.isAddedToDock)
    }

    func testWhenAddToDockCalledFromGeneralThenDockCustomizerAddToDockIsCalled() {
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        model.addToDock(from: .general)
        XCTAssertTrue(mockDockCustomizer.addToDockCalled)
        XCTAssertTrue(model.isAddedToDock)
    }

    func testWhenSupportsAddingToDockIsFalseThenAddToDockDoesNothing() {
        mockDockCustomizer.supportsAddingToDock = false
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: nil
        )
        model.addToDock(from: .defaultBrowser)
        XCTAssertFalse(mockDockCustomizer.addToDockCalled)
        XCTAssertFalse(model.isAddedToDock)
    }

    // MARK: - Pixels

    func testWhenAddToDockCalledFromDefaultBrowserSettingsThenExpectedPixelIsFired() {
        mockPixelFiring.expectedFireCalls = [
            ExpectedFireCall(pixel: GeneralPixel.userAddedToDockFromDefaultBrowserSection,
                             frequency: .standard,
                             includeAppVersionParameter: false)
        ]
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: mockPixelFiring
        )
        model.addToDock(from: .defaultBrowser)
        mockPixelFiring.verifyExpectations()
    }

    func testWhenAddToDockCalledFromGeneralSettingsThenExpectedPixelIsFired() {
        mockPixelFiring.expectedFireCalls = [
            ExpectedFireCall(pixel: GeneralPixel.userAddedToDockFromSettings,
                             frequency: .standard,
                             includeAppVersionParameter: false)
        ]
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: mockPixelFiring
        )
        model.addToDock(from: .general)
        mockPixelFiring.verifyExpectations()
    }

    func testWhenLearnMoreClickedThenExpectedPixelIsFired() {
        mockPixelFiring.expectedFireCalls = [ExpectedFireCall(pixel: GeneralPixel.settingsAddToDockLearnMoreClicked, frequency: .dailyAndCount)]
        mockDockCustomizer.supportsAddingToDock = false
        let model = DockPreferencesModel(
            featureFlagger: mockFeatureFlagger,
            dockCustomizer: mockDockCustomizer,
            windowControllersManager: windowControllersManager,
            pixelFiring: mockPixelFiring
        )
        model.openAddToDockHelpURL()
        mockPixelFiring.verifyExpectations()
    }
}

// MARK: - MockDockCustomization

private final class MockDockCustomization: DockCustomization {
    var supportsAddingToDock: Bool = true
    var isAddedToDock: Bool = false
    var addToDockCalled: Bool = false

    var shouldShowNotification: Bool { false }
    var shouldShowNotificationPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }

    @discardableResult
    func addToDock() -> Bool {
        guard supportsAddingToDock else { return false }
        addToDockCalled = true
        return true
    }

    func didCloseMoreOptionsMenu() {}
    func resetData() {}
}
