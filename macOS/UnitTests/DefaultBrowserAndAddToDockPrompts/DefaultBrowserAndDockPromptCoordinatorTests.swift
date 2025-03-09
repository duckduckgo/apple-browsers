//
//  DefaultBrowserAndDockPromptCoordinatorTests.swift
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
import BrowserServicesKit
import FeatureFlags
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptCoordinatorTests: XCTestCase {

    // MARK: - Evaluate prompt eligibility tests

    func testEvaluatePromptEligibility_SparkleBuild_DefaultBrowserAndAddedToDock_ReturnsNil() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true

        XCTAssertNil(sut.evaluatePromptEligibility)
    }

    func testEvaluatePromptEligibility_SparkleBuild_DefaultBrowserAndNotAddedToDock_ReturnsAddToDockPrompt() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false

        XCTAssertEqual(sut.evaluatePromptEligibility, .addToDockPrompt)
    }

    func testEvaluatePromptEligibility_SparkleBuild_NotDefaultBrowserAndAddedToDock_ReturnsSetAsDefaultPrompt() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true

        XCTAssertEqual(sut.evaluatePromptEligibility, .setAsDefaultPrompt)
    }

    func testEvaluatePromptEligibility_SparkleBuild_NotDefaultBrowserAndNotAddedToDock_ReturnsBothDefaultBrowserAndDockPrompt() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false

        XCTAssertEqual(sut.evaluatePromptEligibility, .bothDefaultBrowserAndDockPrompt)
    }

    func testEvaluatePromptEligibility_AppStoreBuild_DefaultBrowser_ReturnsNil() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = false

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false

        XCTAssertNil(sut.evaluatePromptEligibility)
    }

    func testEvaluatePromptEligibility_AppStoreBuild_NotDefaultBrowser_ReturnsSetAsDefaultPrompt() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = false

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false

        XCTAssertEqual(sut.evaluatePromptEligibility, .setAsDefaultPrompt)
    }

    // MARK: - Get prompty type tests

    func testGetPromptTypeReturnsNilWhenUserIsNotEligibleForExperiment() {
        let featureFlaggerMock = FeatureFlaggerMock(enabledFeatureFlags: [.popoverVsBannerExperiment])
        let experimentDecidingMock = DefaultBrowserAndDockPromptExperimentDecidingMock()
        experimentDecidingMock.isUserEligibleForExperiment = false

        let sut = DefaultBrowserAndDockPromptCoordinator(featureFlagger: featureFlaggerMock)

        XCTAssertNil(sut.getPromptType(experimentDecider: experimentDecidingMock))

    }

    func testGetPromptTypeReturnsNilWhenFeatureFlagCohortIsControl() {
        let featureFlaggerMock = FeatureFlaggerMock(enabledFeatureFlags: [.popoverVsBannerExperiment])
        let experimentDecidingMock = DefaultBrowserAndDockPromptExperimentDecidingMock()
        experimentDecidingMock.isUserEligibleForExperiment = true

        let sut = DefaultBrowserAndDockPromptCoordinator(featureFlagger: featureFlaggerMock)

        featureFlaggerMock.cohortToReturn = FeatureFlag.PopoverVSBannerExperimentCohort.control

        XCTAssertNil(sut.getPromptType(experimentDecider: experimentDecidingMock))
    }

    func testGetPromptTypeReturnsBannerWhenFeatureFlagCohortIsBanner() {
        let featureFlaggerMock = FeatureFlaggerMock(enabledFeatureFlags: [.popoverVsBannerExperiment])
        let experimentDecidingMock = DefaultBrowserAndDockPromptExperimentDecidingMock()
        experimentDecidingMock.isUserEligibleForExperiment = true

        let sut = DefaultBrowserAndDockPromptCoordinator(featureFlagger: featureFlaggerMock)

        featureFlaggerMock.cohortToReturn = FeatureFlag.PopoverVSBannerExperimentCohort.banner
        let result = sut.getPromptType(experimentDecider: experimentDecidingMock)

        XCTAssertEqual(result, .banner)
    }

    func testGetPromptTypeReturnsPopoverWhenFeatureFlagCohortIsPopover() {
        let featureFlaggerMock = FeatureFlaggerMock(enabledFeatureFlags: [.popoverVsBannerExperiment])
        let experimentDecidingMock = DefaultBrowserAndDockPromptExperimentDecidingMock()
        experimentDecidingMock.isUserEligibleForExperiment = true

        let sut = DefaultBrowserAndDockPromptCoordinator(featureFlagger: featureFlaggerMock)

        featureFlaggerMock.cohortToReturn = FeatureFlag.PopoverVSBannerExperimentCohort.popover
        let result = sut.getPromptType(experimentDecider: experimentDecidingMock)

        XCTAssertEqual(result, .popover)
    }

    func testGetPromptTypeReturnsNilWhenFeatureFlagIsDisabled() {
        let featureFlaggerMock = FeatureFlaggerMock(enabledFeatureFlags: [])
        let experimentDecidingMock = DefaultBrowserAndDockPromptExperimentDecidingMock()
        experimentDecidingMock.isUserEligibleForExperiment = true

        let sut = DefaultBrowserAndDockPromptCoordinator(featureFlagger: featureFlaggerMock)

        featureFlaggerMock.cohortToReturn = FeatureFlag.PopoverVSBannerExperimentCohort.popover

        XCTAssertNil(sut.getPromptType(experimentDecider: experimentDecidingMock))
    }

    // MARK: - Prompt confirmation tests

    func testOnPromptConfirmationCallsAddToDockAndSetAsDefaultBrowserWhenBothDefaultBrowserAndDockPromptType() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false

        sut.onPromptConfirmation()

        XCTAssertTrue(dockCustomizerMock.dockStatus)
        XCTAssertTrue(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testOnPromptConfirmationCallsAddToDockWhenAddToDockPromptType() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false

        sut.onPromptConfirmation()

        XCTAssertTrue(dockCustomizerMock.dockStatus)
        XCTAssertFalse(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testOnPromptConfirmationCallsSetAsDefaultBrowserWhenSetAsDefaultPromptType() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true

        sut.onPromptConfirmation()

        XCTAssertFalse(dockCustomizerMock.wasAddToDockCalled)
        XCTAssertTrue(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testOnPromptConfirmationDoesNothingWhenEvaluatePromptEligibilityIsNil() {
        let defaultBrowserProviderMock = DefaultBrowserProviderMock()
        let dockCustomizerMock = DockCustomizerMock()
        let applicationBuildTypeMock = ApplicationBuildTypeMock()
        let featureFlagger = MockFeatureFlagger()

        applicationBuildTypeMock.isSparkleBuild = true

        let sut = DefaultBrowserAndDockPromptCoordinator(
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildTypeMock
        )

        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true

        sut.onPromptConfirmation()

        XCTAssertFalse(dockCustomizerMock.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }
}

final class ApplicationBuildTypeMock: ApplicationBuildType {
    var isSparkleBuild: Bool = false
    var isAppStoreBuild: Bool = false
}

final class DefaultBrowserAndDockPromptExperimentDecidingMock: DefaultBrowserAndDockPromptExperimentDeciding {
    var isUserEligibleForExperiment: Bool = false
}

final class FeatureFlaggerMock: FeatureFlagger {
    var internalUserDecider: InternalUserDecider
    var localOverrides: FeatureFlagLocalOverriding?

    var mockActiveExperiments: [String: ExperimentData] = [:]

    var enabledFeatureFlags: [FeatureFlag] = []

    var cohortToReturn: (any FeatureFlagCohortDescribing)?

    public init(internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring()),
                enabledFeatureFlags: [FeatureFlag] = []) {
        self.internalUserDecider = internalUserDecider
        self.enabledFeatureFlags = enabledFeatureFlags
    }

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        guard let flag = featureFlag as? FeatureFlag else {
            return false
        }
        guard enabledFeatureFlags.contains(flag) else {
            return false
        }
        return true
    }

    func getCohortIfEnabled(_ subfeature: any PrivacySubfeature) -> CohortID? {
        return nil
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        if isFeatureOn(for: featureFlag, allowOverride: false) {
            return cohortToReturn
        } else {
            return nil
        }
    }

    var allActiveExperiments: Experiments {
        mockActiveExperiments
    }
}
