//
//  QuitSurveyDeciderTests.swift
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

import FeatureFlags
import XCTest
import SharedTestUtilities

@testable import DuckDuckGo_Privacy_Browser

// MARK: - Mocks

final class MockQuitSurveyPersistor: QuitSurveyPersistor {
    var alwaysShowQuitSurvey: Bool = false
    var pendingReturnUserReasons: String?
    var hasQuitAppBefore: Bool = false
}

final class MockReinstallingUserDetecting: ReinstallingUserDetecting {
    var isReinstallingUser: Bool = false

    func checkForReinstallingUser() throws {
        // No-op for tests
    }
}

// MARK: - Tests

@MainActor
final class QuitSurveyDeciderTests: XCTestCase {

    // MARK: - Properties

    private var featureFlagger: MockFeatureFlagger!
    private var dataClearingPreferences: DataClearingPreferences!
    private var dataClearingPersistor: MockFireButtonPreferencesPersistor!
    private var downloadManager: FileDownloadManagerMock!
    private var persistor: MockQuitSurveyPersistor!
    private var reinstallUserDetection: MockReinstallingUserDetecting!
    private var currentDate: Date!
    private var installDate: Date!

    private var decider: QuitSurveyDecider!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.firstTimeQuitSurvey]

        dataClearingPersistor = MockFireButtonPreferencesPersistor()
        dataClearingPreferences = DataClearingPreferences(persistor: dataClearingPersistor)

        downloadManager = FileDownloadManagerMock()
        persistor = MockQuitSurveyPersistor()
        reinstallUserDetection = MockReinstallingUserDetecting()

        currentDate = Date()
        installDate = currentDate.addingTimeInterval(-1 * 24 * 60 * 60) // 1 day ago

        createDecider()
    }

    override func tearDown() {
        decider = nil
        featureFlagger = nil
        dataClearingPreferences = nil
        dataClearingPersistor = nil
        downloadManager = nil
        persistor = nil
        reinstallUserDetection = nil
        super.tearDown()
    }

    private func createDecider() {
        decider = QuitSurveyDecider(
            featureFlagger: featureFlagger,
            dataClearingPreferences: dataClearingPreferences,
            downloadManager: downloadManager,
            installDate: installDate,
            persistor: persistor,
            reinstallUserDetection: reinstallUserDetection,
            dateProvider: { [unowned self] in self.currentDate }
        )
    }

    // MARK: - Feature Flag Tests

    func testWhenFeatureFlagIsDisabledThenShouldNotShowSurvey() {
        featureFlagger.enabledFeatureFlags = []
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    func testWhenFeatureFlagIsEnabledThenShouldShowSurvey() {
        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    // MARK: - Auto-Clear Dialog Tests

    func testWhenAutoClearAndWarnBeforeClearingEnabledThenShouldNotShowSurvey() {
        dataClearingPersistor.autoClearEnabled = true
        dataClearingPersistor.warnBeforeClearingEnabled = true
        dataClearingPreferences = DataClearingPreferences(persistor: dataClearingPersistor)
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    func testWhenOnlyAutoClearEnabledThenShouldShowSurvey() {
        dataClearingPersistor.autoClearEnabled = true
        dataClearingPersistor.warnBeforeClearingEnabled = false
        dataClearingPreferences = DataClearingPreferences(persistor: dataClearingPersistor)
        createDecider()

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    func testWhenOnlyWarnBeforeClearingEnabledThenShouldShowSurvey() {
        dataClearingPersistor.autoClearEnabled = false
        dataClearingPersistor.warnBeforeClearingEnabled = true
        dataClearingPreferences = DataClearingPreferences(persistor: dataClearingPersistor)
        createDecider()

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    func testWhenBothAutoClearAndWarnDisabledThenShouldShowSurvey() {
        dataClearingPersistor.autoClearEnabled = false
        dataClearingPersistor.warnBeforeClearingEnabled = false
        dataClearingPreferences = DataClearingPreferences(persistor: dataClearingPersistor)
        createDecider()

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    // MARK: - New User Threshold Tests

    func testWhenUserInstalledTodayThenShouldShowSurvey() {
        installDate = currentDate
        createDecider()

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    func testWhenUserInstalled3DaysAgoThenShouldShowSurvey() {
        installDate = currentDate.addingTimeInterval(-3 * 24 * 60 * 60)
        createDecider()

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    func testWhenUserInstalled4DaysAgoThenShouldNotShowSurvey() {
        installDate = currentDate.addingTimeInterval(-4 * 24 * 60 * 60)
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    func testWhenUserInstalled14DaysAgoThenShouldNotShowSurvey() {
        installDate = currentDate.addingTimeInterval(-14 * 24 * 60 * 60)
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    // MARK: - First Quit Tests

    func testWhenUserHasNotQuitBeforeThenShouldShowSurvey() {
        persistor.hasQuitAppBefore = false
        createDecider()

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    func testWhenUserHasQuitBeforeThenShouldNotShowSurvey() {
        persistor.hasQuitAppBefore = true
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    // MARK: - Reinstalling User Tests

    func testWhenUserIsNotReinstallingThenShouldShowSurvey() {
        reinstallUserDetection.isReinstallingUser = false
        createDecider()

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    func testWhenUserIsReinstallingThenShouldNotShowSurvey() {
        reinstallUserDetection.isReinstallingUser = true
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    // MARK: - Mark Quit Survey Shown Tests

    func testMarkQuitSurveyShownUpdatesPersistor() {
        XCTAssertFalse(persistor.hasQuitAppBefore)

        decider.markQuitSurveyShown()

        XCTAssertTrue(persistor.hasQuitAppBefore)
    }

    func testAfterMarkingQuitSurveyShownShouldNotShowSurveyAgain() {
        XCTAssertTrue(decider.shouldShowQuitSurvey)

        decider.markQuitSurveyShown()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    // MARK: - Combined Conditions Tests

    func testWhenAllConditionsMetThenShouldShowSurvey() {
        // Feature flag enabled (default)
        // No auto-clear dialog (default)
        // No active downloads (default)
        // New user within 14 days (default)
        // First quit (default)

        XCTAssertTrue(decider.shouldShowQuitSurvey)
    }

    func testWhenFeatureFlagDisabledAndAllOtherConditionsMetThenShouldNotShowSurvey() {
        featureFlagger.enabledFeatureFlags = []
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    func testWhenNewUserButHasQuitBeforeThenShouldNotShowSurvey() {
        persistor.hasQuitAppBefore = true
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    func testWhenFirstQuitButNotNewUserThenShouldNotShowSurvey() {
        installDate = currentDate.addingTimeInterval(-30 * 24 * 60 * 60)
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }

    func testWhenAutoClearDialogWillShowAndNewUserFirstQuitThenShouldNotShowSurvey() {
        dataClearingPersistor.autoClearEnabled = true
        dataClearingPersistor.warnBeforeClearingEnabled = true
        dataClearingPreferences = DataClearingPreferences(persistor: dataClearingPersistor)
        createDecider()

        XCTAssertFalse(decider.shouldShowQuitSurvey)
    }
}

// MARK: - DataClearingPreferences Test Extension

private extension DataClearingPreferences {
    @MainActor
    convenience init(persistor: FireButtonPreferencesPersistor) {
        self.init(
            persistor: persistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: MockFeatureFlagger(),
            pixelFiring: nil,
            aiChatHistoryCleaner: MockAIChatHistoryCleaner()
        )
    }
}
