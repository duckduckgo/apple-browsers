//
//  BrokerProfileJobDependenciesTests.swift
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class BrokerProfileJobDependenciesTests: XCTestCase {

    private func makeDependencies(isRemoteScanExecutionOn: Bool) -> BrokerProfileJobDependencies {
        BrokerProfileJobDependencies(
            database: MockDatabase(),
            contentScopeProperties: .mock,
            privacyConfig: PrivacyConfigurationManagingMock(),
            executionConfig: BrokerJobExecutionConfig(),
            notificationCenter: .default,
            pixelHandler: MockDataBrokerProtectionPixelsHandler(),
            eventsHandler: MockOperationEventsHandler(),
            dataBrokerProtectionSettings: DataBrokerProtectionSettings(defaults: .standard),
            emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
            captchaService: CaptchaServiceMock(),
            featureFlagger: MockDBPFeatureFlagger(isRemoteScanExecutionOn: isRemoteScanExecutionOn),
            applicationNameForUserAgentProvider: { nil },
            remoteScanService: MockRemoteScanService()
        )
    }

    func testWhenRemoteScanFlagIsOff_thenWebViewScanRunnerIsCreated() {
        let dependencies = makeDependencies(isRemoteScanExecutionOn: false)

        let runner = dependencies.createScanRunner(profileQuery: BrokerProfileQueryData.mock(),
                                                   stageDurationCalculator: MockStageDurationCalculator(),
                                                   shouldRunNextStep: { true })

        XCTAssertTrue(runner is BrokerProfileScanSubJobWebRunner)
    }

    func testWhenRemoteScanFlagIsOn_thenRemoteScanRunnerIsCreated() {
        let dependencies = makeDependencies(isRemoteScanExecutionOn: true)

        let runner = dependencies.createScanRunner(profileQuery: BrokerProfileQueryData.mock(),
                                                   stageDurationCalculator: MockStageDurationCalculator(),
                                                   shouldRunNextStep: { true })

        XCTAssertTrue(runner is RemoteBrokerProfileScanSubJobRunner)
    }

    func testWhenRemoteScanFlagIsOn_thenOptOutRunnerIsStillWebView() {
        let dependencies = makeDependencies(isRemoteScanExecutionOn: true)

        let runner = dependencies.createOptOutRunner(profileQuery: BrokerProfileQueryData.mock(),
                                                     stageDurationCalculator: MockStageDurationCalculator(),
                                                     shouldRunNextStep: { true })

        XCTAssertTrue(runner is BrokerProfileOptOutSubJobWebRunner)
    }
}
