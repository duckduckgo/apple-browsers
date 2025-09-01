//
//  BrokerProfileJobProviderTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@testable import DataBrokerProtectionCore
import BrowserServicesKit
import DataBrokerProtectionCoreTestsUtils
import XCTest

final class BrokerProfileJobProviderTests: XCTestCase {

    private let sut: BrokerProfileJobProviding = BrokerProfileJobProvider()

    // Dependencies
    private var mockDatabase: MockDatabase!
    private var mockSchedulerConfig = BrokerJobExecutionConfig()
    private var mockPixelHandler: MockPixelHandler!
    private var mockEventsHandler: MockOperationEventsHandler!
    var mockDependencies: BrokerProfileJobDependencies!

    override func setUpWithError() throws {
        mockDatabase = MockDatabase()
        mockPixelHandler = MockPixelHandler()
        mockEventsHandler = MockOperationEventsHandler()

        mockDependencies = BrokerProfileJobDependencies(database: mockDatabase,
                                                        contentScopeProperties: ContentScopeProperties.mock,
                                                        privacyConfig: PrivacyConfigurationManagingMock(),
                                                        executionConfig: mockSchedulerConfig,
                                                        notificationCenter: .default,
                                                        pixelHandler: mockPixelHandler,
                                                        eventsHandler: mockEventsHandler,
                                                        dataBrokerProtectionSettings: DataBrokerProtectionSettings(defaults: .standard),
                                                        emailService: EmailServiceMock(),
                                                        captchaService: CaptchaServiceMock(),
                                                        featureFlagger: MockDBPFeatureFlagger())
    }

    func testWhenBuildOperations_andBrokerQueryDataHasDuplicateBrokers_thenDuplicatesAreIgnored() throws {
        // Given
        let dataBrokerProfileQueries: [BrokerProfileQueryData] = [
            .init(dataBroker: .mock(withId: 1),
                  profileQuery: .mock,
                  scanJobData: .mock(withBrokerId: 1)),
            .init(dataBroker: .mock(withId: 1),
                  profileQuery: .mock,
                  scanJobData: .mock(withBrokerId: 1)),
            .init(dataBroker: .mock(withId: 2),
                  profileQuery: .mock,
                  scanJobData: .mock(withBrokerId: 2)),
            .init(dataBroker: .mock(withId: 2),
                  profileQuery: .mock,
                  scanJobData: .mock(withBrokerId: 2)),
            .init(dataBroker: .mock(withId: 2),
                  profileQuery: .mock,
                  scanJobData: .mock(withBrokerId: 2)),
            .init(dataBroker: .mock(withId: 3),
                  profileQuery: .mock,
                  scanJobData: .mock(withBrokerId: 2)),
        ]
        mockDatabase.brokerProfileQueryDataToReturn = dataBrokerProfileQueries

        // When
        let result = try! sut.createJobs(with: .manualScan,
                                         withPriorityDate: Date(),
                                         showWebView: false,
                                         errorDelegate: MockBrokerProfileJobErrorDelegate(),
                                         jobDependencies: mockDependencies)

        // Then
        XCTAssert(result.count == 3)
    }
}
