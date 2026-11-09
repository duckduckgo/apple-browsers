//
//  StartupFailureMetricsTests.swift
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
@_spi(Testing) import PixelKit
@testable import BrowserServicesKit

final class StartupFailureMetricsTests: XCTestCase {

    private var directory: URL!
    private var storageURL: URL!
    private var pixels: PixelKitMock!
    private var now: Date!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storageURL = directory.appendingPathComponent("startup-failure-metrics.json")
        pixels = PixelKitMock()
        now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        directory = nil
        storageURL = nil
        pixels = nil
        now = nil
    }

    func testHealthyLaunchDoesNotReportFailureOrReturn() {
        let subject = makeSubject()
        subject.recordReturn()
        subject.recordSuccessfulStartup()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testAppVariantsDoNotShareFailureEpisodes() throws {
        let releaseURL = try XCTUnwrap(StartupFailureMetrics.makeStorageURL(
            applicationSupportDirectory: directory, bundleIdentifier: "browser.release"
        ))
        let debugURL = try XCTUnwrap(StartupFailureMetrics.makeStorageURL(
            applicationSupportDirectory: directory, bundleIdentifier: "browser.debug"
        ))
        makeSubject(storageURL: releaseURL).recordFailure()
        makeSubject(storageURL: debugURL).recordReturn()
        XCTAssertEqual(pixels.actualFireCalls.count, 1)

        makeSubject(storageURL: releaseURL).recordReturn()
        XCTAssertEqual(pixels.actualFireCalls.count, 2)
    }

    func testFirstFailureIsPersistedAndReportedOnce() {
        let subject = makeSubject()
        subject.recordFailure()
        subject.recordFailure()
        makeSubject().recordFailure()

        XCTAssertEqual(pixels.actualFireCalls, [
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard)
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testFailureCannotBeReportedAsReturnInTheSameProcess() {
        let subject = makeSubject()
        subject.recordFailure()
        subject.recordReturn()
        subject.recordSuccessfulStartup()

        XCTAssertEqual(pixels.actualFireCalls.count, 1)

        makeSubject().recordReturn()
        XCTAssertEqual(pixels.actualFireCalls.count, 2)
    }

    func testFirstReturnIsReportedOnlyOnceAcrossLaunches() {
        makeSubject().recordFailure()
        now.addTimeInterval(2 * 24 * 60 * 60)
        let nextLaunch = makeSubject()
        nextLaunch.recordReturn()
        nextLaunch.recordReturn()
        makeSubject().recordReturn()

        XCTAssertEqual(pixels.actualFireCalls, [
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysSinceFailure: "2"), frequency: .standard)
        ])
    }

    func testChangingProblemsDuringRetriesDoesNotResetTheFirstFailureDate() {
        makeSubject().recordFailure()
        now.addTimeInterval(2 * 24 * 60 * 60)
        makeSubject().recordFailure()
        now.addTimeInterval(24 * 60 * 60)
        makeSubject().recordReturn()

        XCTAssertEqual(pixels.actualFireCalls.last?.pixel.parameters, ["days_since_first_failure": "3"])
        XCTAssertEqual(pixels.actualFireCalls.count, 2)
    }

    func testReturningWithoutSuccessfulStartupDoesNotRearmFailureReporting() {
        makeSubject().recordFailure()
        let retry = makeSubject()
        retry.recordReturn()
        retry.recordFailure()
        retry.recordSuccessfulStartup()
        makeSubject().recordFailure()

        XCTAssertEqual(pixels.actualFireCalls.count, 2)
    }

    func testSuccessfulStartupAllowsANewFailureEpisode() {
        makeSubject().recordFailure()
        let recovery = makeSubject()
        recovery.recordReturn()
        recovery.recordSuccessfulStartup()
        recovery.recordSuccessfulStartup()

        now.addTimeInterval(10 * 24 * 60 * 60)
        makeSubject().recordFailure()
        now.addTimeInterval(24 * 60 * 60)
        makeSubject().recordReturn()

        XCTAssertEqual(pixels.actualFireCalls, [
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysSinceFailure: "0"), frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.recovered(daysSinceFailure: "0"), frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysSinceFailure: "1"), frequency: .standard)
        ])
    }

    func testSuccessfulStartupAfterRepeatedFailedReturnsReportsRecoveryOnce() {
        makeSubject().recordFailure()
        now.addTimeInterval(24 * 60 * 60)
        let failedReturn = makeSubject()
        failedReturn.recordReturn()
        failedReturn.recordFailure()
        failedReturn.recordSuccessfulStartup()

        now.addTimeInterval(2 * 24 * 60 * 60)
        let recovery = makeSubject()
        recovery.recordReturn()
        recovery.recordSuccessfulStartup()
        recovery.recordSuccessfulStartup()
        makeSubject().recordSuccessfulStartup()

        XCTAssertEqual(pixels.actualFireCalls, [
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysSinceFailure: "1"), frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.recovered(daysSinceFailure: "3"), frequency: .standard)
        ])
    }

    func testReturnAgeUsesWholeElapsedDaysAndCapsAtSevenDays() {
        let cases: [(TimeInterval, String)] = [
            (0, "0"),
            (24 * 60 * 60 - 1, "0"),
            (24 * 60 * 60, "1"),
            (7 * 24 * 60 * 60 - 1, "6"),
            (7 * 24 * 60 * 60, "7+"),
            (365 * 24 * 60 * 60, "7+")
        ]

        for (index, testCase) in cases.enumerated() {
            let file = directory.appendingPathComponent("case-\(index).json")
            let start = now!
            makeSubject(storageURL: file).recordFailure()
            now.addTimeInterval(testCase.0)
            makeSubject(storageURL: file).recordReturn()
            XCTAssertEqual(pixels.actualFireCalls.last?.pixel.parameters, ["days_since_first_failure": testCase.1])
            now = start
        }
    }

    func testClockMovingBackwardsDoesNotReportAnImmediateReturn() {
        makeSubject().recordFailure()
        now.addTimeInterval(-24 * 60 * 60)
        makeSubject().recordReturn()

        XCTAssertEqual(pixels.actualFireCalls.last?.pixel.parameters, ["days_since_first_failure": "unknown"])
    }

    func testUnreadableStateDoesNotStartADuplicateEpisode() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid state".utf8).write(to: storageURL)
        let subject = makeSubject()
        subject.recordFailure()
        subject.recordReturn()
        subject.recordSuccessfulStartup()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testUnwritableStateDoesNotEmitAPixel() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parentFile = directory.appendingPathComponent("file-not-directory")
        try Data().write(to: parentFile)
        makeSubject(storageURL: parentFile.appendingPathComponent("state.json")).recordFailure()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testUnavailablePixelKitDoesNotPersistAnUnreportedFailure() {
        StartupFailureMetrics(storageURL: storageURL, pixelFiring: { nil }).recordFailure()

        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testPixelClientCanBeConfiguredAfterTrackerIsCreated() {
        var client: PixelKitMock?
        let subject = StartupFailureMetrics(storageURL: storageURL, pixelFiring: { client }, dateProvider: { self.now })
        client = pixels

        subject.recordFailure()

        XCTAssertEqual(pixels.actualFireCalls, [ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard)])
    }

    func testFailedSendDoesNotCreateAdditionalFailureOrReturnAttempts() {
        pixels.expectedFireError = URLError(.notConnectedToInternet)
        makeSubject().recordFailure()
        makeSubject().recordFailure()
        makeSubject().recordReturn()
        makeSubject().recordReturn()

        XCTAssertEqual(pixels.actualFireCalls.count, 2)
    }

    func testPixelsContainOnlyBucketedAgeWithoutTimestampsOrIdentifiers() {
        makeSubject().recordFailure()
        makeSubject().recordReturn()

        XCTAssertNil(pixels.actualFireCalls.first?.pixel.parameters)
        XCTAssertEqual(pixels.actualFireCalls.last?.pixel.parameters, ["days_since_first_failure": "0"])
        XCTAssertTrue(pixels.actualFireCalls.allSatisfy { $0.frequency == .standard })
        XCTAssertTrue(pixels.actualFireCalls.allSatisfy { $0.includeAppVersionParameter })
    }

    private func makeSubject(storageURL: URL? = nil) -> StartupFailureMetrics {
        StartupFailureMetrics(storageURL: storageURL ?? self.storageURL, pixelFiring: { self.pixels }, dateProvider: { self.now })
    }
}
