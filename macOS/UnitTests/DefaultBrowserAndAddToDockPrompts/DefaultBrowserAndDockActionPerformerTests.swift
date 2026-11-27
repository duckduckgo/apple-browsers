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

import FeatureFlags_macOS
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockActionPerformerTests: XCTestCase {

    private var dockCustomizer: DockCustomizerMock!
    private var defaultBrowserProvider: CapturingDefaultBrowserProvider!
    private var videoPresenter: CapturingAddToDockVideoPresenter!
    private var featureFlagger: MockFeatureFlagger!
    private var sut: DefaultBrowserAndDockActionPerformer!

    @MainActor
    override func setUp() {
        super.setUp()
        dockCustomizer = DockCustomizerMock()
        defaultBrowserProvider = CapturingDefaultBrowserProvider()
        videoPresenter = CapturingAddToDockVideoPresenter()
        featureFlagger = MockFeatureFlagger()
        sut = DefaultBrowserAndDockActionPerformer(dockCustomization: dockCustomizer,
                                                   defaultBrowserProvider: defaultBrowserProvider,
                                                   featureFlagger: featureFlagger,
                                                   videoPresenter: videoPresenter)
    }

    override func tearDown() {
        sut = nil
        featureFlagger = nil
        videoPresenter = nil
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

    @MainActor
    func testWhenBothPendingThenPerformAddsToDockAndPresentsPrompt() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = false

        sut.performPendingActions(from: .popover)

        XCTAssertTrue(dockCustomizer.wasAddToDockCalled)
        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor
    func testWhenAddToDockPendingThenPerformOnlyAddsToDock() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = true

        sut.performPendingActions(from: .popover)

        XCTAssertTrue(dockCustomizer.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor
    func testWhenPresentingPromptThrowsThenPerformOpensSystemPreferences() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = true
        defaultBrowserProvider.isDefault = false
        defaultBrowserProvider.throwError = true

        sut.performPendingActions(from: .popover)

        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertTrue(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor
    func testWhenNothingPendingThenPerformDoesNothing() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = true
        defaultBrowserProvider.isDefault = true

        sut.performPendingActions(from: .popover)

        XCTAssertFalse(dockCustomizer.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    // MARK: - App Store Add to Dock video

    private func setAppStoreBuild(addToDockOnlyCTA: Bool = false, bothDefaultBrowserAndDockCTA: Bool = false, isDefault: Bool, isInDock: Bool) {
        dockCustomizer.supportsAddingToDock = false
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = addToDockOnlyCTA
        featureFlagger.featuresStub[FeatureFlag.appStoreBothDefaultBrowserAndDockCTA.rawValue] = bothDefaultBrowserAndDockCTA
        dockCustomizer.dockStatus = isInDock
        defaultBrowserProvider.isDefault = isDefault
    }

    func testWhenAppStoreCanShowVideoAndNeitherDoneThenPendingTypeIsBoth() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .bothDefaultBrowserAndDockPrompt)
    }

    func testWhenAppStoreCanShowVideoAndDefaultOnlyThenPendingTypeIsAddToDock() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: true, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .addToDockPrompt)
    }

    func testWhenAppStoreCanShowVideoAndInDockOnlyThenPendingTypeIsSetAsDefault() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: true)
        XCTAssertEqual(sut.pendingPromptType, .setAsDefaultPrompt)
    }

    func testWhenAppStoreCanShowVideoAndBothDoneThenPendingTypeIsNil() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: true, isInDock: true)
        XCTAssertNil(sut.pendingPromptType)
    }

    func testWhenAppStoreCannotShowVideoThenPendingTypeIgnoresDock() {
        setAppStoreBuild(isDefault: false, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .setAsDefaultPrompt)

        defaultBrowserProvider.isDefault = true
        XCTAssertNil(sut.pendingPromptType)
    }

    func testWhenAppStoreVideoFlagTurnsOffThenPendingTypeFallsBack() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .bothDefaultBrowserAndDockPrompt)

        featureFlagger.featuresStub[FeatureFlag.appStoreBothDefaultBrowserAndDockCTA.rawValue] = false

        XCTAssertEqual(sut.pendingPromptType, .setAsDefaultPrompt)
    }

    func testWhenAppStoreOnlyDockOnlyCTAOnAndDefaultNotInDockThenPendingTypeIsAddToDock() {
        setAppStoreBuild(addToDockOnlyCTA: true, isDefault: true, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .addToDockPrompt)
    }

    func testWhenAppStoreOnlyCombinedCTAOnAndDefaultNotInDockThenPendingTypeIsNil() {
        setAppStoreBuild(bothDefaultBrowserAndDockCTA: true, isDefault: true, isInDock: false)
        XCTAssertNil(sut.pendingPromptType)
    }

    func testWhenAppStoreOnlyCombinedCTAOnAndNeitherDoneThenPendingTypeIsBoth() {
        setAppStoreBuild(bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .bothDefaultBrowserAndDockPrompt)
    }

    func testWhenAppStoreOnlyDockOnlyCTAOnAndNeitherDoneThenPendingTypeIsSetAsDefault() {
        setAppStoreBuild(addToDockOnlyCTA: true, isDefault: false, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .setAsDefaultPrompt)
    }

    func testWhenDockOnlyFlagTurnsOffAtRuntimeThenAddToDockPromptIsNoLongerPending() {
        setAppStoreBuild(addToDockOnlyCTA: true, isDefault: true, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .addToDockPrompt)
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = false
        XCTAssertNil(sut.pendingPromptType)
    }

    @MainActor
    func testWhenCombinedFlagTurnsOffBeforeConfirmThenPerformPresentsDefaultBrowserPromptWithoutVideo() {
        setAppStoreBuild(bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        XCTAssertEqual(sut.pendingPromptType, .bothDefaultBrowserAndDockPrompt)
        featureFlagger.featuresStub[FeatureFlag.appStoreBothDefaultBrowserAndDockCTA.rawValue] = false

        sut.performPendingActions(from: .popover)

        XCTAssertTrue(videoPresenter.presentations.isEmpty)
        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
    }

    @MainActor
    func testWhenDockOnlyFlagTurnsOffBeforeConfirmThenPerformDoesNothing() {
        setAppStoreBuild(addToDockOnlyCTA: true, isDefault: true, isInDock: false)
        featureFlagger.featuresStub[FeatureFlag.appStoreAddToDockOnlyCTA.rawValue] = false

        sut.performPendingActions(from: .popover)

        XCTAssertTrue(videoPresenter.presentations.isEmpty)
        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
    }

    @MainActor
    func testWhenAppStoreAddToDockPendingThenPerformPresentsVideoWithCancelAndDone() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: true, isInDock: false)

        sut.performPendingActions(from: .popover)

        XCTAssertEqual(videoPresenter.presentations, [.init(entryPoint: .popover, primaryAction: .done)])
        XCTAssertFalse(dockCustomizer.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)

        videoPresenter.complete(with: .done)

        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
    }

    @MainActor
    func testWhenAppStoreBothPendingThenPerformPresentsVideoBeforeDefaultBrowserPrompt() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)

        sut.performPendingActions(from: .inactiveModal)

        XCTAssertEqual(videoPresenter.presentations, [.init(entryPoint: .inactiveModal, primaryAction: .next)])
        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(dockCustomizer.wasAddToDockCalled)
    }

    @MainActor
    func testWhenAppStoreBothPendingAndNextClickedThenDefaultBrowserPromptIsPresented() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)

        sut.performPendingActions(from: .banner)
        videoPresenter.complete(with: .next)

        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor
    func testWhenAppStoreBothPendingAndCancelClickedThenDefaultBrowserPromptIsNotPresented() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)

        sut.performPendingActions(from: .banner)
        videoPresenter.complete(with: .cancel)

        XCTAssertFalse(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertFalse(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor
    func testWhenAppStoreBothPendingAndNextClickedAndPromptThrowsThenSystemSettingsOpen() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        defaultBrowserProvider.throwError = true

        sut.performPendingActions(from: .popover)
        videoPresenter.complete(with: .next)

        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertTrue(defaultBrowserProvider.openSystemPreferencesCalled)
    }

    @MainActor
    func testWhenAppStoreSetAsDefaultPendingThenPerformPresentsDefaultBrowserPromptWithoutVideo() {
        setAppStoreBuild(addToDockOnlyCTA: true, bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: true)

        sut.performPendingActions(from: .popover)

        XCTAssertTrue(videoPresenter.presentations.isEmpty)
        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
    }

    @MainActor
    func testWhenAppStoreBothPendingAndVideoCannotShowThenDefaultBrowserPromptIsPresented() {
        setAppStoreBuild(bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        videoPresenter.presentResult = false
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }

        XCTAssertEqual(videoPresenter.presentations, [.init(entryPoint: .popover, primaryAction: .next)])
        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testWhenAppStoreBothPendingThenSetAsDefaultRequestIsReportedOnlyAfterNext() {
        setAppStoreBuild(bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }
        XCTAssertEqual(requestCount, 0)

        videoPresenter.complete(with: .next)
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testWhenAppStoreBothPendingAndCancelClickedThenSetAsDefaultRequestIsNotReported() {
        setAppStoreBuild(bothDefaultBrowserAndDockCTA: true, isDefault: false, isInDock: false)
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }
        videoPresenter.complete(with: .cancel)

        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testWhenAppStoreAddToDockPendingThenSetAsDefaultRequestIsNotReported() {
        setAppStoreBuild(addToDockOnlyCTA: true, isDefault: true, isInDock: false)
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }
        videoPresenter.complete(with: .done)

        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testWhenAppStoreSetAsDefaultPendingThenSetAsDefaultRequestIsReported() {
        setAppStoreBuild(isDefault: false, isInDock: true)
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }

        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testWhenDMGBothPendingThenSetAsDefaultRequestIsReported() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = false
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }

        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testWhenDMGAddToDockPendingThenSetAsDefaultRequestIsNotReported() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = true
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }

        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testWhenPresentingPromptThrowsThenSetAsDefaultRequestIsStillReported() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = true
        defaultBrowserProvider.isDefault = false
        defaultBrowserProvider.throwError = true
        var requestCount = 0

        sut.performPendingActions(from: .popover) { requestCount += 1 }

        XCTAssertTrue(defaultBrowserProvider.openSystemPreferencesCalled)
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testWhenDMGBothPendingThenPerformDoesNotPresentVideo() {
        dockCustomizer.supportsAddingToDock = true
        dockCustomizer.dockStatus = false
        defaultBrowserProvider.isDefault = false

        sut.performPendingActions(from: .popover)

        XCTAssertTrue(videoPresenter.presentations.isEmpty)
        XCTAssertTrue(dockCustomizer.wasAddToDockCalled)
    }
}
