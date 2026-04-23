//
//  DataBrokerProtectionStatsPixelsTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
@testable import PixelKit

final class DataBrokerProtectionStatsPixelsTests: XCTestCase {

    private let handler = MockDataBrokerProtectionPixelsHandler()

    override func tearDown() {
        handler.clear()
    }

    func testWhen24HoursHaveNotPassed_thenWeDontFireCustomStatsPixels() {
        // Given
        let repository = MockDataBrokerProtectionStatsPixelsRepository()
        repository._customStatsPixelsLastSentTimestamp = Date.nowMinus(hours: 23)
        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = [
            .mock()
        ]
        let sut = DataBrokerProtectionStatsPixels(database: database,
                                                  handler: handler,
                                                  repository: repository)

        // When
        sut.fireCustomStatsPixelsIfNeeded()

        // Then
        XCTAssertTrue(repository.didGetCustomStatsPixelsLastSentTimestamp)
        XCTAssertEqual(repository.getCount, 1)
        XCTAssertFalse(repository.didSetCustomStatsPixelsLastSentTimestamp)
        XCTAssertEqual(repository.setCount, 0)
    }

    func testWhenCustomStatsPixelsJustSent_thenSecondCallWithin24HoursDoesNotRefire() {
        // Given
        handler.clear()
        let repository = MockDataBrokerProtectionStatsPixelsRepository()
        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = [
            .mock()
        ]
        let sut = DataBrokerProtectionStatsPixels(database: database,
                                                  handler: handler,
                                                  repository: repository)

        // When
        sut.fireCustomStatsPixelsIfNeeded()
        sut.fireCustomStatsPixelsIfNeeded()
        sut.fireCustomStatsPixelsIfNeeded()

        // Then
        XCTAssertTrue(repository.didGetCustomStatsPixelsLastSentTimestamp)
        XCTAssertEqual(repository.getCount, 3) // We're trying to fire 3 times, so 3 get counts should be recorded
        XCTAssertTrue(repository.didSetCustomStatsPixelsLastSentTimestamp)
        XCTAssertEqual(repository.setCount, 1) // Only the first call should send the stats pixel
    }

    func testWhen24HoursHavePassed_thenWeFireCustomStatsPixels() {
        // Given
        let repository = MockDataBrokerProtectionStatsPixelsRepository()
        repository._customStatsPixelsLastSentTimestamp = Date.nowMinus(hours: 25)
        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = [
            .mock()
        ]
        let sut = DataBrokerProtectionStatsPixels(database: database,
                                                  handler: handler,
                                                  repository: repository)

        // When
        sut.fireCustomStatsPixelsIfNeeded()

        // Then
        XCTAssertTrue(repository.didGetCustomStatsPixelsLastSentTimestamp)
        XCTAssertTrue(repository.didSetCustomStatsPixelsLastSentTimestamp)
    }

    func testWhen24HoursHavePassed_andOptOutsWereRequestedWereFound_thenWeFirePixelsWithExpectedValues() {
        // Given
        let repository = MockDataBrokerProtectionStatsPixelsRepository()
        repository._customStatsPixelsLastSentTimestamp = Date.nowMinus(hours: 26)
        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = BrokerProfileQueryData.queryDataMultipleBrokersVaryingSuccessRates
        let sut = DataBrokerProtectionStatsPixels(database: database,
                                                  handler: handler,
                                                  repository: repository)
        let expectation = self.expectation(description: "Async task completion")

        // When
        sut.fireCustomStatsPixelsIfNeeded()

        // There is a 100ms delay between pixels firing, so we need a delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.0) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0) { error in
            if let error = error {
                XCTFail("Expectation failed with error: \(error)")
            }

            // Then
            MockDataBrokerProtectionPixelsHandler.lastPixelsFired.sort { $0.params!["optout_submit_success_rate"]! <  $1.params!["optout_submit_success_rate"]! }
            let pixel1 = MockDataBrokerProtectionPixelsHandler.lastPixelsFired[0]
            let pixel2 = MockDataBrokerProtectionPixelsHandler.lastPixelsFired[1]
            let pixel3 = MockDataBrokerProtectionPixelsHandler.lastPixelsFired[2]
            let pixel4 = MockDataBrokerProtectionPixelsHandler.lastPixelsFired[3]
            XCTAssertTrue(MockDataBrokerProtectionPixelsHandler.lastPixelsFired.count == 4)
            XCTAssertEqual(pixel1.params!["optout_submit_success_rate"], "0.5")
            XCTAssertEqual(pixel2.params!["optout_submit_success_rate"], "0.71")
            XCTAssertEqual(pixel3.params!["optout_submit_success_rate"], "0.75")
            XCTAssertEqual(pixel4.params!["optout_submit_success_rate"], "1.0")
            XCTAssertTrue(repository.didGetCustomStatsPixelsLastSentTimestamp)
            XCTAssertTrue(repository.didSetCustomStatsPixelsLastSentTimestamp)
        }
    }

    // MARK: - opt out confirmed/unconfirmed pixel tests

    private static let dataBrokerURL = DataBroker.mockWithDefaults().url
    private let optOutJobAt7DaysConfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt7DaysConfirmed(dataBroker: dataBrokerURL)
    private let optOutJobAt7DaysUnconfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt7DaysUnconfirmed(dataBroker: dataBrokerURL)
    private let optOutJobAt14DaysConfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt14DaysConfirmed(dataBroker: dataBrokerURL)
    private let optOutJobAt14DaysUnconfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt14DaysUnconfirmed(dataBroker: dataBrokerURL)
    private let optOutJobAt21DaysConfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt21DaysConfirmed(dataBroker: dataBrokerURL)
    private let optOutJobAt21DaysUnconfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt21DaysUnconfirmed(dataBroker: dataBrokerURL)
    private let optOutJobAt42DaysConfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt42DaysConfirmed(dataBroker: dataBrokerURL)
    private let optOutJobAt42DaysUnconfirmedPixel = DataBrokerProtectionSharedPixels.optOutJobAt42DaysUnconfirmed(dataBroker: dataBrokerURL)

    private func validatePixelsFired(_ pixels: [DataBrokerProtectionSharedPixels]) {
        let pixelsFired = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        for pixel in pixels {
            let matchingPixelsFired = pixelsFired.filter { $0.name == pixel.name }
            XCTAssertEqual(matchingPixelsFired.count, 1)
            XCTAssertNotNil(matchingPixelsFired.first)
            let matchingPixelFired = matchingPixelsFired.first!
            XCTAssertEqual(matchingPixelFired.params, pixel.params)
        }
    }

    private func validatePixelsNotFired(_ pixels: [DataBrokerProtectionSharedPixels]) {
        let pixelsFired = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        for pixel in pixels {
            let matchingPixelsFired = pixelsFired.filter { $0.name == pixel.name }
            XCTAssertEqual(matchingPixelsFired.count, 0)
        }
    }

    func testWhenSubmittedDateIs6DaysAgo_thenNoPixelsAreFired() async {
        // Given
        let mockDatabase = MockDatabase()
        let submittedDate = Calendar.current.date(byAdding: .day, value: -6, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutConfirmed,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: false,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        print(pixels)

        // Then
        validatePixelsNotFired([optOutJobAt7DaysConfirmedPixel,
                                optOutJobAt7DaysUnconfirmedPixel,
                                optOutJobAt14DaysConfirmedPixel,
                                optOutJobAt14DaysUnconfirmedPixel,
                                optOutJobAt21DaysConfirmedPixel,
                                optOutJobAt21DaysUnconfirmedPixel,
                                optOutJobAt42DaysConfirmedPixel,
                                optOutJobAt42DaysUnconfirmedPixel
                               ])

        // Cleanup
        handler.clear()
    }

    func testWhenSubmittedDateIs15DaysAgoAndOptOutConfirmed_then7And14ConfirmedPixelsAreFiredButNoOthers() async {
        // Given
        let mockDatabase = MockDatabase()
        let submittedDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutConfirmed,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: false,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        print(pixels)

        // Then
        validatePixelsFired([optOutJobAt7DaysConfirmedPixel,
                             optOutJobAt14DaysConfirmedPixel])
        validatePixelsNotFired([optOutJobAt7DaysUnconfirmedPixel,
                                optOutJobAt14DaysUnconfirmedPixel,
                                optOutJobAt21DaysConfirmedPixel,
                                optOutJobAt21DaysUnconfirmedPixel,
                                optOutJobAt42DaysConfirmedPixel,
                                optOutJobAt42DaysUnconfirmedPixel
                               ])

        // Cleanup
        handler.clear()
    }

    func testWhenSubmittedDateIs15DaysAgoAndOptOutNotConfirmed_then7And14UnconfirmedPixelsAreFiredButNoOthers() async {
        // Given
        let mockDatabase = MockDatabase()
        let submittedDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutRequested,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: false,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        print(pixels)

        // Then
        validatePixelsFired([optOutJobAt7DaysUnconfirmedPixel,
                             optOutJobAt14DaysUnconfirmedPixel])
        validatePixelsNotFired([optOutJobAt7DaysConfirmedPixel,
                                optOutJobAt14DaysConfirmedPixel,
                                optOutJobAt21DaysConfirmedPixel,
                                optOutJobAt21DaysUnconfirmedPixel,
                                optOutJobAt42DaysConfirmedPixel,
                                optOutJobAt42DaysUnconfirmedPixel
                               ])

        // Cleanup
        handler.clear()
    }

    func testWhenPixelAlreadySentFlagsTrue_thenPixelsNotSent() async {
        // Given
        let mockDatabase = MockDatabase()
        let submittedDate = Calendar.current.date(byAdding: .day, value: -22, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutConfirmed,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: true,
                                               fourteenDaysConfirmationPixelFired: true,
                                               twentyOneDaysConfirmationPixelFired: true)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        print(pixels)

        // Then
        validatePixelsNotFired([optOutJobAt7DaysConfirmedPixel,
                                optOutJobAt7DaysUnconfirmedPixel,
                                optOutJobAt14DaysConfirmedPixel,
                                optOutJobAt14DaysUnconfirmedPixel,
                                optOutJobAt21DaysConfirmedPixel,
                                optOutJobAt21DaysUnconfirmedPixel
                               ])

        // Cleanup
        handler.clear()
    }

    func testWhenSomePixelAlreadySentFlagsTrue_thenPixelsSentOrNotSentAsPerFlag() async {
        // Given
        let mockDatabase = MockDatabase()
        let submittedDate = Calendar.current.date(byAdding: .day, value: -22, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutConfirmed,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: true,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        print(pixels)

        // Then
        validatePixelsFired([optOutJobAt14DaysConfirmedPixel,
                             optOutJobAt21DaysConfirmedPixel])
        validatePixelsNotFired([optOutJobAt7DaysConfirmedPixel,
                                optOutJobAt7DaysUnconfirmedPixel,
                                optOutJobAt14DaysUnconfirmedPixel,
                                optOutJobAt21DaysUnconfirmedPixel,
                                optOutJobAt42DaysConfirmedPixel,
                                optOutJobAt42DaysUnconfirmedPixel
                               ])

        // Cleanup
        handler.clear()
    }

    func testWhenSubmittedDateIs43DaysAgoAndOptOutConfirmed_thenAllConfirmedPixelsAreFired() async {
        // Given
        let mockDatabase = MockDatabase()
        let submittedDate = Calendar.current.date(byAdding: .day, value: -43, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutConfirmed,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: false,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false,
                                               fortyTwoDaysConfirmationPixelFired: false)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])

        // Then
        validatePixelsFired([optOutJobAt7DaysConfirmedPixel,
                             optOutJobAt14DaysConfirmedPixel,
                             optOutJobAt21DaysConfirmedPixel,
                             optOutJobAt42DaysConfirmedPixel])
        validatePixelsNotFired([optOutJobAt7DaysUnconfirmedPixel,
                                optOutJobAt14DaysUnconfirmedPixel,
                                optOutJobAt21DaysUnconfirmedPixel,
                                optOutJobAt42DaysUnconfirmedPixel])
        XCTAssertTrue(mockDatabase.wasUpdateFortyTwoDaysConfirmationPixelFired)

        // Cleanup
        handler.clear()
    }

    func testWhenSubmittedDateIs43DaysAgoAndOptOutNotConfirmed_thenAllUnconfirmedPixelsAreFired() async {
        // Given
        let mockDatabase = MockDatabase()
        let submittedDate = Calendar.current.date(byAdding: .day, value: -43, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutRequested,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: false,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false,
                                               fortyTwoDaysConfirmationPixelFired: false)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])

        // Then
        validatePixelsFired([optOutJobAt7DaysUnconfirmedPixel,
                             optOutJobAt14DaysUnconfirmedPixel,
                             optOutJobAt21DaysUnconfirmedPixel,
                             optOutJobAt42DaysUnconfirmedPixel])
        validatePixelsNotFired([optOutJobAt7DaysConfirmedPixel,
                                optOutJobAt14DaysConfirmedPixel,
                                optOutJobAt21DaysConfirmedPixel,
                                optOutJobAt42DaysConfirmedPixel])
        XCTAssertTrue(mockDatabase.wasUpdateFortyTwoDaysConfirmationPixelFired)

        // Cleanup
        handler.clear()
    }

    func testWhenSubmittedDateIsNil_thenNoPixelsAreFired() async {
        // Migrating existing users the submitted date defaults to nil, and pixels shouldn't be fired

        // Given
        let mockDatabase = MockDatabase()
        let optOutJobData = OptOutJobData.mock(with: .optOutConfirmed,
                                               submittedDate: nil,
                                               sevenDaysConfirmationPixelFired: false,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false)
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mockWith(historyEvents: optOutJobData.historyEvents),
            optOutJobData: [optOutJobData])

        let sut = DataBrokerProtectionStatsPixels(database: mockDatabase,
                                                  handler: handler,
                                                  repository: MockDataBrokerProtectionStatsPixelsRepository())

        // When
        sut.fireRegularIntervalConfirmationPixelsForSubmittedOptOuts(for: [brokerProfileQueryData])
        let pixels = MockDataBrokerProtectionPixelsHandler.lastPixelsFired
        print(pixels)

        // Then
        validatePixelsNotFired([optOutJobAt7DaysConfirmedPixel,
                                optOutJobAt7DaysUnconfirmedPixel,
                                optOutJobAt14DaysConfirmedPixel,
                                optOutJobAt14DaysUnconfirmedPixel,
                                optOutJobAt21DaysConfirmedPixel,
                                optOutJobAt21DaysUnconfirmedPixel,
                                optOutJobAt42DaysConfirmedPixel,
                                optOutJobAt42DaysUnconfirmedPixel
                               ])

        // Cleanup
        handler.clear()
    }

    func testWhenFireCustomStatsPixelsIfNeeded_thenExcludesRemovedBrokersFromCustomStats() throws {
        // Given
        let repository = MockDataBrokerProtectionStatsPixelsRepository()
        repository._customStatsPixelsLastSentTimestamp = Date.nowMinus(hours: 25)
        let database = MockDatabase()

        let submittedDate = Calendar.current.date(byAdding: .day, value: -22, to: Date())
        let optOutJobData = OptOutJobData.mock(with: .optOutConfirmed,
                                               submittedDate: submittedDate,
                                               sevenDaysConfirmationPixelFired: true,
                                               fourteenDaysConfirmationPixelFired: false,
                                               twentyOneDaysConfirmationPixelFired: false)

        let activeBrokerData = BrokerProfileQueryData(
            dataBroker: .mock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [optOutJobData]
        )

        let removedBrokerData = BrokerProfileQueryData(
            dataBroker: .removedMock,
            profileQuery: .mock,
            scanJobData: .mock,
            optOutJobData: [optOutJobData]
        )

        database.brokerProfileQueryDataToReturn = [activeBrokerData, removedBrokerData]

        let sut = DataBrokerProtectionStatsPixels(database: database,
                                                  handler: handler,
                                                  repository: repository)

        // When
        sut.fireCustomStatsPixelsIfNeeded()

        // Then
        XCTAssertTrue(database.wasFetchAllBrokerProfileQueryDataCalled, "Should call fetchAllBrokerProfileQueryData")
        XCTAssertEqual(database.lastShouldFilterRemovedBrokers, true, "Should request filtering of removed brokers for custom stats")

        // Verify the trigger was set to fire custom stats pixels
        XCTAssertTrue(repository.didSetCustomStatsPixelsLastSentTimestamp, "Should update timestamp after firing")
    }

}
