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

    func testWhenProvideJobs_andRemovedBrokersExist_thenExcludesRemovedBrokersFromJobScheduling() throws {
        // Given
        let activeBrokerData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        let removedBrokerData = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        mockDatabase.brokerProfileQueryDataToReturn = [activeBrokerData, removedBrokerData]

        // When
        let result = try sut.createJobs(with: .all,
                                        withPriorityDate: nil,
                                        showWebView: false,
                                        errorDelegate: MockBrokerProfileJobErrorDelegate(),
                                        jobDependencies: mockDependencies)

        // Then
        XCTAssertTrue(mockDatabase.wasFetchAllBrokerProfileQueryDataCalled, "Should call fetchAllBrokerProfileQueryData")
        XCTAssertEqual(mockDatabase.lastShouldFilterRemovedBrokers, true, "Should request filtering of removed brokers for job scheduling")

        // Should only create jobs for active broker
        XCTAssertEqual(result.count, 1, "Should only create jobs for active brokers")
    }

    func testProvideJobs_withOnlyRemovedBrokers_returnsEmptyArray() throws {
        // Given
        let removedBroker1 = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        let removedBroker2 = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        mockDatabase.brokerProfileQueryDataToReturn = [removedBroker1, removedBroker2]

        // When
        let result = try sut.createJobs(with: .all,
                                        withPriorityDate: nil,
                                        showWebView: false,
                                        errorDelegate: MockBrokerProfileJobErrorDelegate(),
                                        jobDependencies: mockDependencies)

        // Then
        XCTAssertEqual(result.count, 0, "Should not create jobs for removed brokers")
    }

    func testProvideJobs_withMixedBrokers_onlyCreatesJobsForActiveOnes() throws {
        // Given
        let activeBroker1 = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        // Create second active broker with different ID
        let activeBroker2DataBroker = DataBroker(
            id: 3,
            name: "ActiveBroker2",
            url: "https://active2.com",
            steps: [
                Step(type: .scan, actions: [Action]()),
                Step(type: .optOut, actions: [Action]())
            ],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig.mock,
            mirrorSites: [],
            optOutUrl: "",
            eTag: "",
            removedAt: nil // Active broker
        )
        let activeBroker2 = BrokerProfileQueryData(
            dataBroker: activeBroker2DataBroker,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        let removedBroker1 = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        let removedBroker2 = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        mockDatabase.brokerProfileQueryDataToReturn = [activeBroker1, removedBroker1, activeBroker2, removedBroker2]

        // When
        let result = try sut.createJobs(with: .all,
                                        withPriorityDate: nil,
                                        showWebView: false,
                                        errorDelegate: MockBrokerProfileJobErrorDelegate(),
                                        jobDependencies: mockDependencies)

        // Then
        XCTAssertTrue(mockDatabase.wasFetchAllBrokerProfileQueryDataCalled, "Should call fetchAllBrokerProfileQueryData")
        XCTAssertEqual(mockDatabase.lastShouldFilterRemovedBrokers, true, "Should request filtering of removed brokers")

        // Should create jobs only for active brokers (removed brokers are filtered at database level)
        XCTAssertEqual(result.count, 2, "Should create jobs only for active brokers")
    }

    func testProvideJobs_allFilterRemovedBrokers() throws {
        // Given
        let activeBrokerData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        let removedBrokerData = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [.mock(with: .mockWithoutRemovedDate)]
        )

        mockDatabase.brokerProfileQueryDataToReturn = [activeBrokerData, removedBrokerData]

        let jobTypes: [JobType] = [.scheduledScan, .manualScan, .optOut, .all]

        // When & Then
        for jobType in jobTypes {
            // Reset call tracking flags
            mockDatabase.wasFetchAllBrokerProfileQueryDataCalled = false
            mockDatabase.lastShouldFilterRemovedBrokers = nil

            let result = try sut.createJobs(with: jobType,
                                            withPriorityDate: nil,
                                            showWebView: false,
                                            errorDelegate: MockBrokerProfileJobErrorDelegate(),
                                            jobDependencies: mockDependencies)

            XCTAssertTrue(mockDatabase.wasFetchAllBrokerProfileQueryDataCalled, "Should call fetchAllBrokerProfileQueryData for \(jobType)")
            XCTAssertEqual(mockDatabase.lastShouldFilterRemovedBrokers, true, "Should request filtering for job type \(jobType)")

            // Should create at most 1 job (for active broker only)
            XCTAssertLessThanOrEqual(result.count, 1, "Should create at most 1 job for \(jobType)")
        }
    }
}
