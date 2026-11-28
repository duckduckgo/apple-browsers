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
import PrivacyConfig
@testable import BrowserServicesKit

final class StartupFailureMetricsTests: XCTestCase {

    private var directory: URL!
    private var storageURL: URL!
    private var pixels: PixelKitMock!
    private var now: Date!
    private var defaults: UserDefaults!

    private enum TestFeatureFlag: String, FeatureFlagDescribing {
        case startupFailureMetrics

        var defaultValue: FeatureFlagDefaultValue { .disabled }
        var source: FeatureFlagSource { .remoteReleasable(MacOSBrowserConfigSubfeature.startupFailureMetrics) }
        var supportsLocalOverriding: Bool { true }
        var cohortType: (any FeatureFlagCohortDescribing.Type)? { nil }
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storageURL = directory.appendingPathComponent("startup-failure-metrics.json")
        pixels = PixelKitMock()
        now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults = try XCTUnwrap(UserDefaults(suiteName: directory.lastPathComponent))
        defaults.set(true, forKey: StartupFailureMetrics.enabledKey)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: directory.lastPathComponent)
        defaults = nil
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        directory = nil
        storageURL = nil
        pixels = nil
        now = nil
    }

    func testDefaultOffDoesNotResolveProvidersOrCreateEpisodeStorage() {
        defaults.removeObject(forKey: StartupFailureMetrics.enabledKey)
        let subject = StartupFailureMetrics(storageURL: {
            XCTFail("Disabled tracking must not resolve episode storage")
            return self.storageURL
        }, pixelFiring: {
            XCTFail("Disabled tracking must not resolve PixelKit")
            return self.pixels
        }, defaults: defaults, dateProvider: {
            XCTFail("Disabled tracking must not read the date")
            return self.now
        })
        let featureFlagger = MockFeatureFlagger(featuresStub: [TestFeatureFlag.startupFailureMetrics.rawValue: false])
        subject.configure(featureFlagger: featureFlagger, feature: TestFeatureFlag.startupFailureMetrics)

        subject.recordFailure()
        subject.recordUserReturnedToApp()
        subject.recordSuccessfulStartup()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNil(defaults.object(forKey: StartupFailureMetrics.enabledKey))
    }

    func testFlagCanEnableTrackingDuringTheSession() {
        let featureFlagger = MockFeatureFlagger(featuresStub: [TestFeatureFlag.startupFailureMetrics.rawValue: false])
        let subject = makeSubject()
        subject.configure(featureFlagger: featureFlagger, feature: TestFeatureFlag.startupFailureMetrics)
        subject.recordFailure()

        featureFlagger.featuresStub[TestFeatureFlag.startupFailureMetrics.rawValue] = true
        featureFlagger.triggerUpdate()
        subject.recordFailure()

        XCTAssertEqual(pixels.actualFireCalls, [ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard)])
    }

    func testDisableDuringPixelClientResolutionPreventsEpisodeWork() {
        let featureFlagger = MockFeatureFlagger(featuresStub: [TestFeatureFlag.startupFailureMetrics.rawValue: true])
        let subject = StartupFailureMetrics(storageURL: {
            XCTFail("Tracking disabled while resolving PixelKit must not access episode storage")
            return self.storageURL
        }, pixelFiring: {
            featureFlagger.featuresStub[TestFeatureFlag.startupFailureMetrics.rawValue] = false
            featureFlagger.triggerUpdate()
            return self.pixels
        }, defaults: defaults)
        subject.configure(featureFlagger: featureFlagger, feature: TestFeatureFlag.startupFailureMetrics)

        subject.recordFailure()

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDisablingTrackingPreservesEpisodeBeforeAndAfterReturn() throws {
        let flag = TestFeatureFlag.startupFailureMetrics
        makeSubject().recordFailure()
        let pendingState = try Data(contentsOf: storageURL)
        let featureFlagger = MockFeatureFlagger(featuresStub: [flag.rawValue: false])
        let nextLaunch = makeSubject()
        nextLaunch.configure(featureFlagger: featureFlagger, feature: flag)

        nextLaunch.recordFailure()
        nextLaunch.recordUserReturnedToApp()
        nextLaunch.recordSuccessfulStartup()
        XCTAssertEqual(try Data(contentsOf: storageURL), pendingState)
        XCTAssertEqual(pixels.actualFireCalls.count, 1)

        featureFlagger.featuresStub[flag.rawValue] = true
        featureFlagger.triggerUpdate()
        nextLaunch.recordUserReturnedToApp()
        let returnedState = try Data(contentsOf: storageURL)

        featureFlagger.featuresStub[flag.rawValue] = false
        featureFlagger.triggerUpdate()
        nextLaunch.recordFailure()
        nextLaunch.recordUserReturnedToApp()
        nextLaunch.recordSuccessfulStartup()
        XCTAssertEqual(try Data(contentsOf: storageURL), returnedState)
        XCTAssertEqual(pixels.actualFireCalls.count, 2)

        featureFlagger.featuresStub[flag.rawValue] = true
        featureFlagger.triggerUpdate()
        nextLaunch.recordSuccessfulStartup()
        XCTAssertEqual(pixels.actualFireCalls, [
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysBucket: .sameDay), frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.recovered(daysBucket: .sameDay), frequency: .standard)
        ])
    }

    func testResolvedFlagValueIsUsedBeforeFlaggerIsAvailableOnNextLaunch() {
        defaults.removeObject(forKey: StartupFailureMetrics.enabledKey)
        let featureFlagger = MockFeatureFlagger(featuresStub: [TestFeatureFlag.startupFailureMetrics.rawValue: true])
        let subject = makeSubject()
        subject.configure(featureFlagger: featureFlagger, feature: TestFeatureFlag.startupFailureMetrics)

        makeSubject().recordFailure()
        XCTAssertEqual(pixels.actualFireCalls.count, 1)

        featureFlagger.featuresStub[TestFeatureFlag.startupFailureMetrics.rawValue] = false
        featureFlagger.triggerUpdate()
        makeSubject().recordUserReturnedToApp()
        makeSubject().recordSuccessfulStartup()

        XCTAssertFalse(defaults.bool(forKey: StartupFailureMetrics.enabledKey))
        XCTAssertEqual(pixels.actualFireCalls.count, 1)
    }

    func testConfiguringTrackerDoesNotRetainItThroughFlagUpdates() {
        let featureFlagger = MockFeatureFlagger(featuresStub: [TestFeatureFlag.startupFailureMetrics.rawValue: true])
        var subject: StartupFailureMetrics? = makeSubject()
        weak var weakSubject = subject
        subject?.configure(featureFlagger: featureFlagger, feature: TestFeatureFlag.startupFailureMetrics)

        subject = nil

        XCTAssertNil(weakSubject)
        featureFlagger.featuresStub[TestFeatureFlag.startupFailureMetrics.rawValue] = false
        featureFlagger.triggerUpdate()
        XCTAssertTrue(defaults.bool(forKey: StartupFailureMetrics.enabledKey))
    }

    func testHealthyLaunchDoesNotReportFailureOrReturn() {
        let subject = makeSubject()
        subject.recordUserReturnedToApp()
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
        makeSubject(storageURL: debugURL).recordUserReturnedToApp()
        XCTAssertEqual(pixels.actualFireCalls.count, 1)

        makeSubject(storageURL: releaseURL).recordUserReturnedToApp()
        XCTAssertEqual(pixels.actualFireCalls.count, 2)
    }

    func testEpisodeReportsEachMilestoneOnceAndRearmsOnRecovery() {
        let failedLaunch = makeSubject()
        failedLaunch.recordFailure()
        failedLaunch.recordFailure()
        failedLaunch.recordUserReturnedToApp()
        failedLaunch.recordSuccessfulStartup()
        XCTAssertEqual(pixels.actualFireCalls.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        now.addTimeInterval(2 * 24 * 60 * 60)
        makeSubject().recordFailure()
        now.addTimeInterval(24 * 60 * 60)
        let failedRelaunch = makeSubject()
        failedRelaunch.recordUserReturnedToApp()
        failedRelaunch.recordUserReturnedToApp()
        failedRelaunch.recordFailure()
        failedRelaunch.recordSuccessfulStartup()
        makeSubject().recordFailure()
        XCTAssertEqual(pixels.actualFireCalls.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        now.addTimeInterval(2 * 24 * 60 * 60)
        let recovery = makeSubject()
        recovery.recordUserReturnedToApp()
        recovery.recordSuccessfulStartup()
        recovery.recordSuccessfulStartup()
        makeSubject().recordSuccessfulStartup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))

        now.addTimeInterval(10 * 24 * 60 * 60)
        makeSubject().recordFailure()
        now.addTimeInterval(24 * 60 * 60)
        makeSubject().recordUserReturnedToApp()

        XCTAssertEqual(pixels.actualFireCalls, [
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysBucket: .threeDays), frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.recovered(daysBucket: .fiveDays), frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysBucket: .oneDay), frequency: .standard)
        ])
    }

    func testPreviouslyCompletedStateAllowsANewFailureEpisode() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let completedState = #"{"firstFailureDate":0,"didReportReturn":true,"didSuccessfullyStart":true}"#
        try Data(completedState.utf8).write(to: storageURL)

        let healthyLaunch = makeSubject()
        healthyLaunch.recordUserReturnedToApp()
        healthyLaunch.recordSuccessfulStartup()
        XCTAssertTrue(pixels.actualFireCalls.isEmpty)

        makeSubject().recordFailure()
        XCTAssertEqual(pixels.actualFireCalls, [ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard)])
    }

    func testReturnAndRecoveryUseTheSameWholeDayBuckets() {
        let day: TimeInterval = 24 * 60 * 60
        let cases: [(elapsed: TimeInterval, bucket: String)] = [
            (0, "0"), (day - 1, "0"), (day, "1+"), (3 * day - 1, "1+"), (3 * day, "3+"),
            (5 * day - 1, "3+"), (5 * day, "5+"), (8 * day - 1, "5+"), (8 * day, "8+"),
            (13 * day - 1, "8+"), (13 * day, "13+"), (21 * day - 1, "13+"), (21 * day, "21+"),
            (365 * day, "21+")
        ]

        for testCase in cases {
            makeSubject().recordFailure()
            now.addTimeInterval(testCase.elapsed)
            let recovery = makeSubject()
            recovery.recordUserReturnedToApp()
            recovery.recordSuccessfulStartup()

            let expectedParameters = ["days_count": testCase.bucket]
            XCTAssertEqual(pixels.actualFireCalls.suffix(2).map { $0.pixel.parameters },
                           [expectedParameters, expectedParameters],
                           "Return and recovery after \(testCase.elapsed) seconds")
        }
    }

    func testClockMovingBackwardsOmitsReturnAndRecoveryAge() {
        makeSubject().recordFailure()
        now.addTimeInterval(-24 * 60 * 60)
        let recovery = makeSubject()
        recovery.recordUserReturnedToApp()
        recovery.recordSuccessfulStartup()

        XCTAssertEqual(pixels.actualFireCalls.dropFirst().map { $0.pixel.parameters }, [nil, nil])
    }

    func testUnreadableStateDoesNotStartADuplicateEpisode() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid state".utf8).write(to: storageURL)
        let subject = makeSubject()
        subject.recordFailure()
        subject.recordUserReturnedToApp()
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
        StartupFailureMetrics(storageURL: { self.storageURL }, pixelFiring: { nil }, defaults: defaults).recordFailure()

        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testPixelClientCanBeConfiguredAfterTrackerIsCreated() {
        var client: PixelKitMock?
        let subject = StartupFailureMetrics(storageURL: { self.storageURL }, pixelFiring: { client }, defaults: defaults, dateProvider: { self.now })
        client = pixels

        subject.recordFailure()

        XCTAssertEqual(pixels.actualFireCalls, [ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard)])
    }

    func testSuccessfulStartupBeforeReturnLeavesEpisodeOpen() {
        makeSubject().recordFailure()
        let nextLaunch = makeSubject()
        nextLaunch.recordSuccessfulStartup()

        XCTAssertEqual(pixels.actualFireCalls.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        nextLaunch.recordUserReturnedToApp()
        nextLaunch.recordSuccessfulStartup()

        XCTAssertEqual(pixels.actualFireCalls, [
            ExpectedFireCall(pixel: StartupFailurePixel.failure, frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.returned(daysBucket: .sameDay), frequency: .standard),
            ExpectedFireCall(pixel: StartupFailurePixel.recovered(daysBucket: .sameDay), frequency: .standard)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testOriginalPixelPayloadsIncludeElapsedDayBucketsAndOptIntoRetry() {
        makeSubject().recordFailure()
        let nextLaunch = makeSubject()
        nextLaunch.recordUserReturnedToApp()
        nextLaunch.recordSuccessfulStartup()

        #if os(macOS)
        let expectedNames = ["startup_failure_macos", "startup_failure_returned_macos", "startup_failure_recovered_macos"]
        #else
        let expectedNames = ["startup_failure", "startup_failure_returned", "startup_failure_recovered"]
        #endif
        XCTAssertEqual(pixels.actualFireCalls.map { $0.pixel.name }, expectedNames)
        XCTAssertTrue(pixels.actualFireCalls.allSatisfy { $0.pixel.namePrefix == .none })
        XCTAssertNil(pixels.actualFireCalls.first?.pixel.parameters)
        XCTAssertEqual(pixels.actualFireCalls.dropFirst().compactMap { $0.pixel.parameters }, [
            ["days_count": "0"],
            ["days_count": "0"]
        ])
        XCTAssertTrue(pixels.actualFireCalls.allSatisfy { $0.frequency == .standard })
        XCTAssertTrue(pixels.actualFireCalls.allSatisfy { $0.includeAppVersionParameter })
        XCTAssertEqual(pixels.actualFireOptions, [.withRetry, .withRetry, .withRetry])
    }

    private func makeSubject(storageURL: URL? = nil) -> StartupFailureMetrics {
        StartupFailureMetrics(storageURL: { storageURL ?? self.storageURL }, pixelFiring: { self.pixels }, defaults: defaults, dateProvider: { self.now })
    }
}
