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
    private var mockPixelHandler: MockDataBrokerProtectionPixelsHandler!
    private var mockEventsHandler: MockOperationEventsHandler!
    var mockDependencies: BrokerProfileJobDependencies!

    override func setUpWithError() throws {
        mockDatabase = MockDatabase()
        mockPixelHandler = MockDataBrokerProtectionPixelsHandler()
        mockEventsHandler = MockOperationEventsHandler()

        mockDependencies = BrokerProfileJobDependencies(database: mockDatabase,
                                                        contentScopeProperties: ContentScopeProperties.mock,
                                                        privacyConfig: PrivacyConfigurationManagingMock(),
                                                        executionConfig: mockSchedulerConfig,
                                                        notificationCenter: .default,
                                                        pixelHandler: mockPixelHandler,
                                                        eventsHandler: mockEventsHandler,
                                                        dataBrokerProtectionSettings: DataBrokerProtectionSettings(defaults: .standard),
                                                        emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(),
                                                        captchaService: CaptchaServiceMock(),
                                                        featureFlagger: MockDBPFeatureFlagger(),
                                                        applicationNameForUserAgentProvider: { nil })
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
                                         statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(),
                                         isAuthenticatedUser: true,
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
                                        statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(),
                                        isAuthenticatedUser: true,
                                        jobDependencies: mockDependencies)

        // Then
        XCTAssertTrue(mockDatabase.wasFetchEligibleBrokerProfileQueryDataCalled, "Should fetch eligible broker data (removed brokers excluded)")
        XCTAssertEqual(mockDatabase.lastFetchEligibleIsAuthenticatedUser, true)

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
                                        statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(),
                                        isAuthenticatedUser: true,
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
                                        statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(),
                                        isAuthenticatedUser: true,
                                        jobDependencies: mockDependencies)

        // Then
        XCTAssertTrue(mockDatabase.wasFetchEligibleBrokerProfileQueryDataCalled, "Should fetch eligible broker data (removed brokers excluded)")
        XCTAssertEqual(mockDatabase.lastFetchEligibleIsAuthenticatedUser, true)

        // Should create jobs only for active brokers (removed brokers are filtered at database level)
        XCTAssertEqual(result.count, 2, "Should create jobs only for active brokers")
    }

    func testProvideJobs_acrossAllJobTypes_fetchesEligibleBrokerData() throws {
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
            mockDatabase.wasFetchEligibleBrokerProfileQueryDataCalled = false
            mockDatabase.lastFetchEligibleIsAuthenticatedUser = nil

            let result = try sut.createJobs(with: jobType,
                                            withPriorityDate: nil,
                                            showWebView: false,
                                            statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(),
                                            isAuthenticatedUser: true,
                                            jobDependencies: mockDependencies)

            XCTAssertTrue(mockDatabase.wasFetchEligibleBrokerProfileQueryDataCalled, "Should fetch eligible broker data for job type \(jobType)")
            XCTAssertEqual(mockDatabase.lastFetchEligibleIsAuthenticatedUser, true)

            // Should create at most 1 job (for active broker only)
            XCTAssertLessThanOrEqual(result.count, 1, "Should create at most 1 job for \(jobType)")
        }
    }

    func testProvideJobs_whenFreemiumUserHasSubscriptionRequiredBroker_excludesBrokerFromJobScheduling() throws {
        // Given
        let gatedBrokerData = BrokerProfileQueryData(
            dataBroker: makeBroker(id: 1, scanActions: [MockAction(actionType: .generateEmail)]),
            profileQuery: .mock,
            scanJobData: .mock(withBrokerId: 1)
        )
        let eligibleBrokerData = BrokerProfileQueryData(
            dataBroker: makeBroker(id: 2, scanActions: [MockAction(actionType: .click)]),
            profileQuery: .mock,
            scanJobData: .mock(withBrokerId: 2)
        )
        let otherEligibleBrokerData = BrokerProfileQueryData(
            dataBroker: makeBroker(id: 3, scanActions: [MockAction(actionType: .navigate)]),
            profileQuery: .mock,
            scanJobData: .mock(withBrokerId: 3)
        )
        mockDatabase.brokerProfileQueryDataToReturn = [gatedBrokerData, eligibleBrokerData, otherEligibleBrokerData]

        // When
        let result = try sut.createJobs(with: .scheduledScan,
                                        withPriorityDate: nil,
                                        showWebView: false,
                                        statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(),
                                        isAuthenticatedUser: false,
                                        jobDependencies: mockDependencies)

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(mockDatabase.lastFetchEligibleIsAuthenticatedUser, false)
    }

    func testProvideJobs_whenAuthenticatedUserHasSubscriptionRequiredBroker_includesBrokerInJobScheduling() throws {
        // Given
        let gatedBrokerData = BrokerProfileQueryData(
            dataBroker: makeBroker(id: 1, scanActions: [MockAction(actionType: .generateEmail)]),
            profileQuery: .mock,
            scanJobData: .mock(withBrokerId: 1)
        )
        mockDatabase.brokerProfileQueryDataToReturn = [gatedBrokerData]

        // When
        let result = try sut.createJobs(with: .scheduledScan,
                                        withPriorityDate: nil,
                                        showWebView: false,
                                        statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(),
                                        isAuthenticatedUser: true,
                                        jobDependencies: mockDependencies)

        // Then
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(mockDatabase.lastFetchEligibleIsAuthenticatedUser, true)
    }

    private func makeBroker(id: Int64, scanActions: [Action]) -> DataBroker {
        DataBroker(
            id: id,
            name: "Broker \(id)",
            url: "broker-\(id).com",
            steps: [
                Step(type: .scan, actions: scanActions)
            ],
            version: "1.0",
            schedulingConfig: .mock,
            optOutUrl: "",
            eTag: "",
            removedAt: nil
        )
    }

}

private struct MockAction: Action {
    let id: String = "mock"
    let actionType: ActionType
    let json: Data? = nil

    func with(json: Data?) -> MockAction {
        MockAction(actionType: actionType)
    }
}
