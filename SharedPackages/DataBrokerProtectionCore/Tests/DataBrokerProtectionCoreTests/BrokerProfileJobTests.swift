//
//  BrokerProfileJobTests.swift
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
import DataBrokerProtectionCoreTestsUtils
import XCTest

final class BrokerProfileJobTests: XCTestCase {
    lazy var mockOptOutQueryData: [BrokerProfileQueryData] = {
        let brokerId: Int64 = 1

        let mockNilPreferredRunDateQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: nil, optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: nil)])
        }
        let mockPastQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowMinus(hours: $0), optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: .nowMinus(hours: $0))])
        }
        let mockFutureQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowPlus(hours: $0), optOutJobData: [BrokerProfileQueryData.createOptOutJobData(extractedProfileId: Int64($0), brokerId: brokerId, profileQueryId: Int64($0), preferredRunDate: .nowPlus(hours: $0))])
        }

        return mockNilPreferredRunDateQueryData + mockPastQueryData + mockFutureQueryData
    }()

    lazy var mockScanQueryData: [BrokerProfileQueryData] = {
        let mockNilPreferredRunDateQueryData = Array(1...10).map { _ in
            BrokerProfileQueryData.mock(preferredRunDate: nil)
        }
        let mockPastQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowMinus(hours: $0))
        }
        let mockFutureQueryData = Array(1...10).map {
            BrokerProfileQueryData.mock(preferredRunDate: .nowPlus(hours: $0))
        }

        return mockNilPreferredRunDateQueryData + mockPastQueryData + mockFutureQueryData
    }()

    // MARK: - Lifecycle Tests

    func testWhenFetchingBrokerProfileQueryDataFails_ThenJobCompletesWithNoOutput() {
        let delegate = MockBrokerProfileJobErrorDelegate()
        let database = MockDatabase()
        let mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.database = database

        database.fetchAllBrokerProfileQueryDataError = NSError(domain: "pir.test.error", code: 0, userInfo: nil)

        let job = BrokerProfileJob(dataBrokerID: 1,
                                   jobType: .all,
                                   showWebView: false,
                                   errorDelegate: delegate,
                                   jobDependencies: mockDependencies)

        let finishedExpectation = expectation(for: NSPredicate(format: "isFinished == true"), evaluatedWith: job, handler: nil)
        job.start()
        wait(for: [finishedExpectation], timeout: 10.0)

        XCTAssertTrue(job.isFinished)
        XCTAssertTrue(database.scanEvents.isEmpty)
        XCTAssertTrue(database.optOutEvents.isEmpty)
    }

    func testWhenScanDataIsPresent_ThenScanEventsAreCreated() {
        let delegate = MockBrokerProfileJobErrorDelegate()
        let database = MockDatabase()
        let mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.database = database

        database.brokerProfileQueryDataToReturn = [
            .init(dataBroker: .mock(withId: 1), profileQuery: .mock, scanJobData: .mock(withBrokerId: 1))
        ]

        let job = BrokerProfileJob(dataBrokerID: 1,
                                   jobType: .all,
                                   showWebView: false,
                                   errorDelegate: delegate,
                                   jobDependencies: mockDependencies)

        let finishedExpectation = expectation(for: NSPredicate(format: "isFinished == true"), evaluatedWith: job, handler: nil)
        job.start()
        wait(for: [finishedExpectation], timeout: 10.0)

        XCTAssertTrue(job.isFinished)
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .scanStarted }))
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .noMatchFound }))
        XCTAssertTrue(database.optOutEvents.isEmpty)
    }

    func testWhenOptOutDataIsPresent_ThenOptOutEventsAreCreated() {
        let delegate = MockBrokerProfileJobErrorDelegate()
        let database = MockDatabase()
        let mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.database = database

        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()

        let mockDataBroker = DataBroker(id: brokerId,
                                        name: "databroker",
                                        url: "databroker.com",
                                        steps: [Step](),
                                        version: "1.0",
                                        schedulingConfig: config,
                                        optOutUrl: "",
                                        eTag: "")
        let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

        let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
        let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

        let extractedProfileSaved = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc")

        let optOutData = [OptOutJobData.mock(with: extractedProfileSaved)]

        let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                            profileQuery: mockProfileQuery,
                                                            scanJobData: mockScanOperation,
                                                            optOutJobData: optOutData)
        database.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

        let job = BrokerProfileJob(dataBrokerID: 1,
                                   jobType: .all,
                                   showWebView: false,
                                   errorDelegate: delegate,
                                   jobDependencies: mockDependencies)

        let finishedExpectation = expectation(for: NSPredicate(format: "isFinished == true"), evaluatedWith: job, handler: nil)
        job.start()
        wait(for: [finishedExpectation], timeout: 10.0)

        XCTAssertTrue(job.isFinished)
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .scanStarted }))
        XCTAssertTrue(database.scanEvents.contains(where: { $0.type == .noMatchFound }))
        XCTAssertTrue(database.optOutEvents.contains(where: { $0.type == .optOutStarted }))
        XCTAssertTrue(database.optOutEvents.contains(where: { $0.type == .optOutRequested }))
        XCTAssertTrue(database.optOutEvents.contains(where: { $0.type == .optOutConfirmed }))
    }

    // MARK: - Filtering Tests

    func testWhenFilteringOptOutOperationData_thenAllButFuturePreferredRunDateIsReturned() {
        let operationData1 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: nil)
        let operationData2 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: .now)
        let operationData3 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: .distantPast)
        let operationData4 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .optOut, priorityDate: .distantFuture)

        XCTAssertEqual(operationData1.count, 30) // all jobs
        XCTAssertEqual(operationData2.count, 20) // nil preferred run date + past jobs
        XCTAssertEqual(operationData3.count, 10) // nil preferred run date jobs
        XCTAssertEqual(operationData4.count, 30) // all jobs
    }

    func testWhenFilteringScanOperationData_thenPreferredRunDatePriorToPriorityDateIsReturned() {
        let operationData1 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockScanQueryData, jobType: .scheduledScan, priorityDate: nil)
        let operationData2 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockScanQueryData, jobType: .manualScan, priorityDate: .now)
        let operationData3 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockScanQueryData, jobType: .scheduledScan, priorityDate: .distantPast)
        let operationData4 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockScanQueryData, jobType: .manualScan, priorityDate: .distantFuture)

        XCTAssertEqual(operationData1.count, 30) // all jobs
        XCTAssertEqual(operationData2.count, 10) // past jobs
        XCTAssertEqual(operationData3.count, 0) // no jobs
        XCTAssertEqual(operationData4.count, 20) // past + future jobs
    }

    func testFilteringAllOperationData() {
        let operationData1 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: nil)
        let operationData2 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: .now)
        let operationData3 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: .distantPast)
        let operationData4 = MockBrokerProfileJob.eligibleJobsSortedByPreferredRunOrder(brokerProfileQueriesData: mockOptOutQueryData, jobType: .all, priorityDate: .distantFuture)

        XCTAssertEqual(operationData1.filter { $0 is ScanJobData }.count, 30) // all jobs
        XCTAssertEqual(operationData1.filter { $0 is OptOutJobData }.count, 30) // all jobs
        XCTAssertEqual(operationData1.count, 30+30)

        XCTAssertEqual(operationData2.filter { $0 is ScanJobData }.count, 10) // past jobs
        XCTAssertEqual(operationData2.filter { $0 is OptOutJobData }.count, 20) // nil preferred run date + past jobs
        XCTAssertEqual(operationData2.count, 10+20)

        XCTAssertEqual(operationData3.filter { $0 is ScanJobData }.count, 0) // no jobs
        XCTAssertEqual(operationData3.filter { $0 is OptOutJobData }.count, 10) // nil preferred run date jobs
        XCTAssertEqual(operationData3.count, 0+10)

        XCTAssertEqual(operationData4.filter { $0 is ScanJobData }.count, 20) // past + future jobs
        XCTAssertEqual(operationData4.filter { $0 is OptOutJobData }.count, 30) // all jobs
        XCTAssertEqual(operationData4.count, 20+30)
    }

}
