//
//  BrokerProfileScanSubJobTests.swift
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
import Common
import PixelKit
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class BrokerProfileScanSubJobTests: XCTestCase {
    var sut: BrokerProfileScanSubJob!

    var mockScanRunner: MockScanSubJobWebRunner!
    var mockOptOutRunner: MockOptOutSubJobWebRunner!
    var mockDatabase: MockDatabase!
    var mockEventsHandler: MockOperationEventsHandler!
    var mockPixelHandler: MockDataBrokerProtectionPixelsHandler!
    var mockDependencies: MockBrokerProfileJobDependencies!

    override func setUp() {
        super.setUp()
        mockScanRunner = MockScanSubJobWebRunner()
        mockOptOutRunner = MockOptOutSubJobWebRunner()
        mockDatabase = MockDatabase()
        mockEventsHandler = MockOperationEventsHandler()
        mockPixelHandler = MockDataBrokerProtectionPixelsHandler()

        mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.mockScanRunner = self.mockScanRunner
        mockDependencies.mockOptOutRunner = self.mockOptOutRunner
        mockDependencies.database = self.mockDatabase
        mockDependencies.eventsHandler = self.mockEventsHandler
        mockDependencies.pixelHandler = self.mockPixelHandler

        sut = BrokerProfileScanSubJob(dependencies: mockDependencies)
    }

    private func makeFixtureIdentifiers() -> BrokerProfileScanSubJob.ScanIdentifiers {
        .init(brokerId: 1, profileQueryId: 1)
    }

    private func makeFixtureBrokerProfileQueryData(broker: DataBroker = .mock,
                                                   profileQuery: ProfileQuery = .mock,
                                                   scanHistoryEvents: [HistoryEvent] = []) -> BrokerProfileQueryData {
        BrokerProfileQueryData(
            dataBroker: broker,
            profileQuery: profileQuery,
            scanJobData: .init(
                brokerId: broker.id ?? 1,
                profileQueryId: profileQuery.id ?? 1,
                historyEvents: scanHistoryEvents
            )
        )
    }

    // MARK: - validateScanPreconditions

    func testValidateScanPreconditions_whenBrokerIdMissing_throws() {
        let broker = DataBroker(name: "broker",
                                url: "broker.com",
                                steps: [],
                                version: "1",
                                schedulingConfig: .default,
                                optOutUrl: "",
                                eTag: "",
                                removedAt: nil)
        let profile = ProfileQuery(firstName: "John", lastName: "Doe", city: "City", state: "State", birthYear: 1990)
        let brokerData = BrokerProfileQueryData(dataBroker: broker,
                                                profileQuery: profile,
                                                scanJobData: .mock)

        XCTAssertThrowsError(
            try sut.validateScanPreconditions(brokerProfileQueryData: brokerData)
        ) { error in
            XCTAssertEqual(error as? BrokerProfileSubJobError, .idsMissingForBrokerOrProfileQuery)
        }
    }

    func testValidateScanPreconditions_whenProfileQueryIdMissing_throws() {
        let broker = DataBroker.mock
        let profile = ProfileQuery(firstName: "John", lastName: "Doe", city: "City", state: "State", birthYear: 1990)
        let brokerData = BrokerProfileQueryData(dataBroker: broker,
                                                profileQuery: profile,
                                                scanJobData: .mock)

        XCTAssertThrowsError(try sut.validateScanPreconditions(brokerProfileQueryData: brokerData)) { error in
            XCTAssertEqual(error as? BrokerProfileSubJobError, .idsMissingForBrokerOrProfileQuery)
        }
    }

    func testValidateScanPreconditions_whenAllIdsPresent_returnsIdentifiers() throws {
        let brokerData = makeFixtureBrokerProfileQueryData()

        let result = try sut.validateScanPreconditions(brokerProfileQueryData: brokerData)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.brokerId, 1)
        XCTAssertEqual(result?.profileQueryId, 1)
    }

    // MARK: - reportScanCompletion

    func testReportScanCompletion_updatesLastRunDate() {
        let brokerData = makeFixtureBrokerProfileQueryData()
        let identifiers = makeFixtureIdentifiers()
        let notificationCenter = NotificationCenter()

        sut.reportScanCompletion(database: mockDatabase,
                                 notificationCenter: notificationCenter,
                                 brokerProfileQueryData: brokerData,
                                 identifiers: identifiers)

        XCTAssertTrue(mockDatabase.wasUpdateLastRunDateForScanCalled)
    }

    func testReportScanCompletion_postsFinishNotification() {
        let brokerData = makeFixtureBrokerProfileQueryData()
        let identifiers = makeFixtureIdentifiers()
        let notificationCenter = NotificationCenter()
        var notificationReceived = false
        var receivedObject: Any?

        let observer = notificationCenter.addObserver(forName: DataBrokerProtectionNotifications.didFinishScan,
                                                      object: nil,
                                                      queue: nil) { notification in
            notificationReceived = true
            receivedObject = notification.object
        }

        defer {
            notificationCenter.removeObserver(observer)
        }

        sut.reportScanCompletion(database: mockDatabase,
                                 notificationCenter: notificationCenter,
                                 brokerProfileQueryData: brokerData,
                                 identifiers: identifiers)

        XCTAssertTrue(notificationReceived, "Notification should have been posted")
        XCTAssertEqual(receivedObject as? String, brokerData.dataBroker.name)
    }

    func testReportScanCompletion_whenDatabaseFails_doesNotThrow() {
        let brokerData = makeFixtureBrokerProfileQueryData()
        let identifiers = makeFixtureIdentifiers()
        let notificationCenter = NotificationCenter()
        mockDatabase.updateLastRunDateError = MockDatabase.MockError.saveFailed

        sut.reportScanCompletion(database: mockDatabase,
                                 notificationCenter: notificationCenter,
                                 brokerProfileQueryData: brokerData,
                                 identifiers: identifiers)

        XCTAssertTrue(mockDatabase.wasUpdateLastRunDateForScanCalled)
    }

    // MARK: - createScanStageContext

    func testCreateScanStageContext_createsEventPixelsAndCalculator() {
        let brokerData = makeFixtureBrokerProfileQueryData()

        let context = sut.createScanStageContext(brokerProfileQueryData: brokerData,
                                                 isManual: false,
                                                 isAuthenticated: false,
                                                 database: mockDatabase,
                                                 pixelHandler: mockPixelHandler,
                                                 parentURL: nil,
                                                 vpnConnectionState: "connected",
                                                 vpnBypassStatus: "enabled",
                                                 featureFlagger: MockDBPFeatureFlagger())

        XCTAssertNotNil(context.eventPixels)
        XCTAssertNotNil(context.stageCalculator)
    }

    func testCreateScanStageContext_whenManualScan_setsImmediateOperation() {
        let brokerData = makeFixtureBrokerProfileQueryData()

        let context = sut.createScanStageContext(brokerProfileQueryData: brokerData,
                                                 isManual: true,
                                                 isAuthenticated: false,
                                                 database: mockDatabase,
                                                 pixelHandler: mockPixelHandler,
                                                 parentURL: nil,
                                                 vpnConnectionState: "connected",
                                                 vpnBypassStatus: "enabled",
                                                 featureFlagger: MockDBPFeatureFlagger())

        let calculator = context.stageCalculator as DataBrokerProtectionStageDurationCalculator
        XCTAssertNotNil(calculator)
        XCTAssertTrue(calculator.isImmediateOperation)
    }

    func testCreateScanStageContext_whenNotManualScan_doesNotSetImmediateOperation() {
        let brokerData = makeFixtureBrokerProfileQueryData()

        let context = sut.createScanStageContext(brokerProfileQueryData: brokerData,
                                                 isManual: false,
                                                 isAuthenticated: false,
                                                 database: mockDatabase,
                                                 pixelHandler: mockPixelHandler,
                                                 parentURL: nil,
                                                 vpnConnectionState: "connected",
                                                 vpnBypassStatus: "enabled",
                                                 featureFlagger: MockDBPFeatureFlagger())

        let calculator = context.stageCalculator as DataBrokerProtectionStageDurationCalculator
        XCTAssertNotNil(calculator)
        XCTAssertFalse(calculator.isImmediateOperation)
    }

    // MARK: - markScanStarted

    func testMarkScanStarted_persistsHistoryEvent() throws {
        let identifiers = makeFixtureIdentifiers()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     parentURL: nil,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())

        try sut.markScanStarted(brokerId: identifiers.brokerId,
                                profileQueryId: identifiers.profileQueryId,
                                stageCalculator: calculator,
                                database: mockDatabase)

        XCTAssertTrue(mockDatabase.scanEvents.contains { $0.type == .scanStarted })
    }

    func testMarkScanStarted_whenHistoryWriteFails_rethrows() {
        let identifiers = makeFixtureIdentifiers()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     parentURL: nil,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        mockDatabase.addHistoryEventError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(try sut.markScanStarted(brokerId: identifiers.brokerId,
                                                     profileQueryId: identifiers.profileQueryId,
                                                     stageCalculator: calculator,
                                                     database: mockDatabase)) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - makeScanRunner

    func testMakeScanRunner_usesFactory() {
        var capturedBrokerData: BrokerProfileQueryData?
        var capturedCalculator: StageDurationCalculator?
        var capturedShouldRun: (() -> Bool)?

        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     parentURL: nil,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())

        let runner = sut.makeScanRunner(brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
                                        stageCalculator: calculator,
                                        shouldRunNextStep: { true },
                                        runnerFactory: { profile, calc, should in
            capturedBrokerData = profile
            capturedCalculator = calc
            capturedShouldRun = should
            return MockScanSubJobWebRunner()
        })

        XCTAssertNotNil(runner)
        XCTAssertEqual(capturedBrokerData?.dataBroker.name, "Test broker")
        XCTAssertTrue((capturedCalculator as AnyObject) === (calculator as AnyObject))
        XCTAssertNotNil(capturedShouldRun)
        XCTAssertTrue(capturedShouldRun?() ?? false)
    }

    // MARK: - executeScan

    func testExecuteScan_invokesRunner() async throws {
        let runner = MockScanSubJobWebRunner()
        runner.scanResults = [.mockWithoutRemovedDate]

        let profiles = try await sut.executeScan(runner: runner,
                                                 brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
                                                 showWebView: true,
                                                 shouldRunNextStep: { true })

        XCTAssertTrue(runner.wasScanCalled)
        XCTAssertEqual(profiles.count, 1)
    }

    func testExecuteScan_whenRunnerThrows_rethrows() async {
        let runner = MockScanSubJobWebRunner()
        runner.shouldScanThrow = true

        do {
            _ = try await sut.executeScan(runner: runner,
                                          brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
                                          showWebView: true,
                                          shouldRunNextStep: { true })
            XCTFail("Expected runner scan to throw")
        } catch {
            XCTAssertTrue(runner.wasScanCalled)
        }
    }

    func testExecuteScan_returnsExtractedProfiles() async throws {
        let runner = MockScanSubJobWebRunner()
        let expectedProfiles = [ExtractedProfile.mockWithoutRemovedDate, ExtractedProfile.mockWithoutId]
        runner.scanResults = expectedProfiles

        let profiles = try await sut.executeScan(runner: runner,
                                                 brokerProfileQueryData: makeFixtureBrokerProfileQueryData(),
                                                 showWebView: false,
                                                 shouldRunNextStep: { true })

        XCTAssertEqual(profiles.count, expectedProfiles.count)
    }

    // MARK: - handleScanMatches

    func testHandleScanMatches_firesSuccessPixel() throws {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let eventPixels = DataBrokerProtectionEventPixels(database: mockDatabase,
                                                          handler: mockPixelHandler)
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     parentURL: nil,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        let matches = [ExtractedProfile.mockWithoutRemovedDate]
        var scheduleOptOutsCalled = false

        try sut.handleScanMatches(matches: matches,
                                  brokerId: identifiers.brokerId,
                                  profileQueryId: identifiers.profileQueryId,
                                  brokerProfileQueryData: brokerData,
                                  database: mockDatabase,
                                  eventPixels: eventPixels,
                                  stageCalculator: calculator,
                                  scheduleOptOuts: { _, _, _, _, _, _, _ in
            scheduleOptOutsCalled = true
        })

        XCTAssertTrue(scheduleOptOutsCalled)
        XCTAssertTrue(mockDatabase.scanEvents.contains { $0.type == .matchesFound(count: 1) })
    }

    func testHandleScanMatches_addsMatchesFoundEvent() throws {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let eventPixels = DataBrokerProtectionEventPixels(database: mockDatabase,
                                                          handler: mockPixelHandler)
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     parentURL: nil,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        let matches = [ExtractedProfile.mockWithoutRemovedDate, ExtractedProfile.mockWithoutId]

        try sut.handleScanMatches(matches: matches,
                                 brokerId: identifiers.brokerId,
                                 profileQueryId: identifiers.profileQueryId,
                                 brokerProfileQueryData: brokerData,
                                 database: mockDatabase,
                                 eventPixels: eventPixels,
                                 stageCalculator: calculator,
                                 scheduleOptOuts: { _, _, _, _, _, _, _ in })

        XCTAssertTrue(mockDatabase.scanEvents.contains { $0.type == .matchesFound(count: 2) })
    }

    func testHandleScanMatches_whenDatabaseFails_rethrows() {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let eventPixels = DataBrokerProtectionEventPixels(database: mockDatabase,
                                                          handler: mockPixelHandler)
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        let matches = [ExtractedProfile.mockWithoutRemovedDate]
        mockDatabase.addHistoryEventError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(try sut.handleScanMatches(matches: matches,
                                                       brokerId: identifiers.brokerId,
                                                       profileQueryId: identifiers.profileQueryId,
                                                       brokerProfileQueryData: brokerData,
                                                       database: mockDatabase,
                                                       eventPixels: eventPixels,
                                                       stageCalculator: calculator,
                                                       scheduleOptOuts: { _, _, _, _, _, _, _ in })) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - handleScanWithNoMatches

    func testHandleScanWithNoMatches_callsStoreNoMatchesEvent() throws {
        let identifiers = makeFixtureIdentifiers()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     parentURL: nil,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        var storeNoMatchesCalled = false

        try sut.handleScanWithNoMatches(brokerId: identifiers.brokerId,
                                        profileQueryId: identifiers.profileQueryId,
                                        database: mockDatabase,
                                        stageCalculator: calculator,
                                        storeNoMatchesEvent: { _, _, _, _ in
            storeNoMatchesCalled = true
        })

        XCTAssertTrue(storeNoMatchesCalled)
    }

    func testHandleScanWithNoMatches_whenStoreEventFails_rethrows() {
        let identifiers = makeFixtureIdentifiers()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     parentURL: nil,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())

        XCTAssertThrowsError(try sut.handleScanWithNoMatches(brokerId: identifiers.brokerId,
                                                             profileQueryId: identifiers.profileQueryId,
                                                             database: mockDatabase,
                                                             stageCalculator: calculator,
                                                             storeNoMatchesEvent: { _, _, _, _ in
            throw MockDatabase.MockError.saveFailed
        })) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - detectRemovedProfiles

    func testDetectRemovedProfiles_whenNoProfilesRemoved_returnsEmpty() {
        let previousProfiles = [ExtractedProfile.mockWithoutRemovedDate]
        let currentProfiles = [ExtractedProfile.mockWithoutRemovedDate]

        let removedProfiles = sut.detectRemovedProfiles(previouslyExtractedProfiles: previousProfiles,
                                                        currentScanProfiles: currentProfiles)

        XCTAssertTrue(removedProfiles.isEmpty)
    }

    func testDetectRemovedProfiles_whenProfileRemoved_returnsRemovedProfile() {
        let profile1 = ExtractedProfile(id: 1, name: "Profile 1", profileUrl: "url1", identifier: "id1")
        let profile2 = ExtractedProfile(id: 2, name: "Profile 2", profileUrl: "url2", identifier: "id2")
        let previousProfiles = [profile1, profile2]
        let currentProfiles = [profile1]

        let removedProfiles = sut.detectRemovedProfiles(previouslyExtractedProfiles: previousProfiles,
                                                        currentScanProfiles: currentProfiles)

        XCTAssertEqual(removedProfiles.count, 1)
        XCTAssertEqual(removedProfiles.first?.identifier, "id2")
    }

    func testDetectRemovedProfiles_whenAllProfilesRemoved_returnsAllProfiles() {
        let profile1 = ExtractedProfile(id: 1, name: "Profile 1", profileUrl: "url1", identifier: "id1")
        let profile2 = ExtractedProfile(id: 2, name: "Profile 2", profileUrl: "url2", identifier: "id2")
        let previousProfiles = [profile1, profile2]
        let currentProfiles: [ExtractedProfile] = []

        let removedProfiles = sut.detectRemovedProfiles(previouslyExtractedProfiles: previousProfiles,
                                                        currentScanProfiles: currentProfiles)

        XCTAssertEqual(removedProfiles.count, 2)
    }

    func testDetectRemovedProfiles_whenNewProfileAdded_returnsEmpty() {
        let profile1 = ExtractedProfile(id: 1, name: "Profile 1", profileUrl: "url1", identifier: "id1")
        let profile2 = ExtractedProfile(id: 2, name: "Profile 2", profileUrl: "url2", identifier: "id2")
        let previousProfiles = [profile1]
        let currentProfiles = [profile1, profile2]

        let removedProfiles = sut.detectRemovedProfiles(previouslyExtractedProfiles: previousProfiles,
                                                        currentScanProfiles: currentProfiles)

        XCTAssertTrue(removedProfiles.isEmpty)
    }

    // MARK: - handleRemovedProfiles

    func testHandleRemovedProfiles_callsMarkRemovedAndNotify() throws {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let removedProfiles = [ExtractedProfile.mockWithoutRemovedDate]
        var markRemovedCalled = false

        try sut.handleRemovedProfiles(removedProfiles: removedProfiles,
                                      brokerId: identifiers.brokerId,
                                      profileQueryId: identifiers.profileQueryId,
                                      brokerProfileQueryData: brokerData,
                                      database: mockDatabase,
                                      pixelHandler: mockPixelHandler,
                                      eventsHandler: mockEventsHandler,
                                      featureFlagger: MockDBPFeatureFlagger(),
                                      markRemovedAndNotify: { _, _, _, _, _, _, _, _ in
            markRemovedCalled = true
        })

        XCTAssertTrue(markRemovedCalled)
    }

    func testHandleRemovedProfiles_whenMarkRemovedFails_rethrows() {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let removedProfiles = [ExtractedProfile.mockWithoutRemovedDate]

        XCTAssertThrowsError(try sut.handleRemovedProfiles(removedProfiles: removedProfiles,
                                                           brokerId: identifiers.brokerId,
                                                           profileQueryId: identifiers.profileQueryId,
                                                           brokerProfileQueryData: brokerData,
                                                           database: mockDatabase,
                                                           pixelHandler: mockPixelHandler,
                                                           eventsHandler: mockEventsHandler,
                                                           featureFlagger: MockDBPFeatureFlagger(),
                                                           markRemovedAndNotify: { _, _, _, _, _, _, _, _ in
            throw MockDatabase.MockError.saveFailed
        })) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - updateDatesAfterNoRemovals

    func testUpdateDatesAfterNoRemovals_callsUpdateOperationDates() throws {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        var updateOperationDatesCalled = false

        try sut.updateDatesAfterNoRemovals(brokerId: identifiers.brokerId,
                                           profileQueryId: identifiers.profileQueryId,
                                           brokerProfileQueryData: brokerData,
                                           database: mockDatabase,
                                           updateOperationDates: { _, _, _, _, _, _ in
            updateOperationDatesCalled = true
        })

        XCTAssertTrue(updateOperationDatesCalled)
    }

    func testUpdateDatesAfterNoRemovals_passesCorrectOrigin() throws {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        var capturedOrigin: OperationPreferredDateUpdaterOrigin?

        try sut.updateDatesAfterNoRemovals(brokerId: identifiers.brokerId,
                                           profileQueryId: identifiers.profileQueryId,
                                           brokerProfileQueryData: brokerData,
                                           database: mockDatabase,
                                           updateOperationDates: { origin, _, _, _, _, _ in
            capturedOrigin = origin
        })

        XCTAssertEqual(capturedOrigin, .scan)
    }

    func testUpdateDatesAfterNoRemovals_passesNilExtractedProfileId() throws {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        var capturedExtractedProfileId: Int64? = Int64(999) // Start with non-nil sentinel

        try sut.updateDatesAfterNoRemovals(brokerId: identifiers.brokerId,
                                           profileQueryId: identifiers.profileQueryId,
                                           brokerProfileQueryData: brokerData,
                                           database: mockDatabase,
                                           updateOperationDates: { _, _, _, extractedProfileId, _, _ in
            capturedExtractedProfileId = extractedProfileId
        })

        XCTAssertNil(capturedExtractedProfileId, "extractedProfileId should be nil")
    }

    func testUpdateDatesAfterNoRemovals_whenUpdateFails_rethrows() {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()

        XCTAssertThrowsError(try sut.updateDatesAfterNoRemovals(brokerId: identifiers.brokerId,
                                                                profileQueryId: identifiers.profileQueryId,
                                                                brokerProfileQueryData: brokerData,
                                                                database: mockDatabase,
                                                                updateOperationDates: { _, _, _, _, _, _ in
            throw MockDatabase.MockError.saveFailed
        })) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - handleScanFailure

    func testHandleScanFailure_firesErrorPixel() {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        let testError = DataBrokerProtectionError.unknown("test error")
        var handleErrorCalled = false

        let returnedError = sut.handleScanFailure(error: testError,
                                                  brokerId: identifiers.brokerId,
                                                  profileQueryId: identifiers.profileQueryId,
                                                  brokerProfileQueryData: brokerData,
                                                  stageCalculator: calculator,
                                                  database: mockDatabase,
                                                  schedulingConfig: .default,
                                                  scanWideEventRecorder: nil,
                                                  handleError: { _, _, _, _, _, _, _ in
            handleErrorCalled = true
        })

        XCTAssertTrue(handleErrorCalled)
        XCTAssertEqual(returnedError as? DataBrokerProtectionError, testError)
    }

    func testHandleScanFailure_passesCorrectOrigin() {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        let testError = DataBrokerProtectionError.unknown("test error")
        var capturedOrigin: OperationPreferredDateUpdaterOrigin?

        _ = sut.handleScanFailure(error: testError,
                                  brokerId: identifiers.brokerId,
                                  profileQueryId: identifiers.profileQueryId,
                                  brokerProfileQueryData: brokerData,
                                  stageCalculator: calculator,
                                  database: mockDatabase,
                                  schedulingConfig: .default,
                                  scanWideEventRecorder: nil,
                                  handleError: { origin, _, _, _, _, _, _ in
            capturedOrigin = origin
        })

        XCTAssertEqual(capturedOrigin, .scan)
    }

    func testHandleScanFailure_passesNilExtractedProfileId() {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        let testError = DataBrokerProtectionError.unknown("test error")
        var capturedExtractedProfileId: Int64? = Int64(999) // Start with non-nil to prove it gets set to nil

        _ = sut.handleScanFailure(error: testError,
                                  brokerId: identifiers.brokerId,
                                  profileQueryId: identifiers.profileQueryId,
                                  brokerProfileQueryData: brokerData,
                                  stageCalculator: calculator,
                                  database: mockDatabase,
                                  schedulingConfig: .default,
                                  scanWideEventRecorder: nil,
                                  handleError: { _, _, _, extractedProfileId, _, _, _ in
            capturedExtractedProfileId = extractedProfileId
        })

        XCTAssertNil(capturedExtractedProfileId, "extractedProfileId should be nil")
    }

    func testHandleScanFailure_returnsOriginalError() {
        let identifiers = makeFixtureIdentifiers()
        let brokerData = makeFixtureBrokerProfileQueryData()
        let calculator = DataBrokerProtectionStageDurationCalculator(dataBrokerURL: "https://broker.com",
                                                                     dataBrokerVersion: "1.0",
                                                                     handler: mockPixelHandler,
                                                                     vpnConnectionState: "state",
                                                                     vpnBypassStatus: "status",
                                                                     featureFlagger: MockDBPFeatureFlagger())
        let testError = DataBrokerProtectionError.actionFailed(actionID: "test", message: "test message")

        let returnedError = sut.handleScanFailure(error: testError,
                                                  brokerId: identifiers.brokerId,
                                                  profileQueryId: identifiers.profileQueryId,
                                                  brokerProfileQueryData: brokerData,
                                                  stageCalculator: calculator,
                                                  database: mockDatabase,
                                                  schedulingConfig: .default,
                                                  scanWideEventRecorder: nil,
                                                  handleError: { _, _, _, _, _, _, _ in })

        if case .actionFailed(let actionID, let message) = returnedError as? DataBrokerProtectionError {
            XCTAssertEqual(actionID, "test")
            XCTAssertEqual(message, "test message")
        } else {
            XCTFail("Expected actionFailed error")
        }
    }

    // MARK: - updateOperationDataDates error scenarios

    func testUpdateOperationDataDates_whenBrokerProfileQueryDataThrows_rethrows() {
        let identifiers = makeFixtureIdentifiers()
        mockDatabase.brokerProfileQueryDataError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(
            try sut.updateOperationDataDates(origin: .scan,
                                            brokerId: identifiers.brokerId,
                                            profileQueryId: identifiers.profileQueryId,
                                            extractedProfileId: nil,
                                            schedulingConfig: .default,
                                            database: mockDatabase)
        ) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    func testUpdateOperationDataDates_whenUpdatePreferredRunDateForScanThrows_rethrows() throws {
        let identifiers = makeFixtureIdentifiers()
        let extractedProfileId: Int64 = 1

        let historyEvent = HistoryEvent(extractedProfileId: extractedProfileId,
                                        brokerId: identifiers.brokerId,
                                        profileQueryId: identifiers.profileQueryId,
                                        type: .matchesFound(count: 1))

        let pastDate = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        let brokerData = BrokerProfileQueryData(dataBroker: .mock,
                                                profileQuery: .mock,
                                                scanJobData: .init(brokerId: identifiers.brokerId,
                                                                   profileQueryId: identifiers.profileQueryId,
                                                                   preferredRunDate: pastDate,
                                                                   historyEvents: [historyEvent]))

        let throwingDatabase = MockDatabase()
        throwingDatabase.brokerProfileQueryDataToReturn = [brokerData]
        throwingDatabase.updatePreferredRunDateError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(try sut.updateOperationDataDates(origin: .scan,
                                                              brokerId: identifiers.brokerId,
                                                              profileQueryId: identifiers.profileQueryId,
                                                              extractedProfileId: extractedProfileId,
                                                              schedulingConfig: .default,
                                                              database: throwingDatabase)) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    func testUpdateOperationDataDates_whenUpdatePreferredRunDateForOptOutThrows_rethrows() throws {
        let identifiers = makeFixtureIdentifiers()
        let extractedProfileId: Int64 = 1
        let historyEvent = HistoryEvent(extractedProfileId: extractedProfileId,
                                        brokerId: identifiers.brokerId,
                                        profileQueryId: identifiers.profileQueryId,
                                        type: .optOutRequested)

        let optOutJobData = OptOutJobData(brokerId: identifiers.brokerId,
                                          profileQueryId: identifiers.profileQueryId,
                                          createdDate: Date(),
                                          preferredRunDate: Date(),
                                          historyEvents: [historyEvent],
                                          attemptCount: 0,
                                          extractedProfile: ExtractedProfile(id: extractedProfileId))

        let brokerData = BrokerProfileQueryData(dataBroker: .mock,
                                                profileQuery: .mock,
                                                scanJobData: .init(brokerId: identifiers.brokerId,
                                                                   profileQueryId: identifiers.profileQueryId,
                                                                   historyEvents: [historyEvent]),
                                                optOutJobData: [optOutJobData])

        let throwingDatabase = MockDatabase()
        throwingDatabase.brokerProfileQueryDataToReturn = [brokerData]
        throwingDatabase.updatePreferredRunDateError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(try sut.updateOperationDataDates(origin: .scan,
                                                              brokerId: identifiers.brokerId,
                                                              profileQueryId: identifiers.profileQueryId,
                                                              extractedProfileId: extractedProfileId,
                                                              schedulingConfig: .default,
                                                              database: throwingDatabase)) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    func testUpdateOperationDataDates_whenUpdateSubmittedSuccessfullyDateThrows_rethrows() throws {
        let identifiers = makeFixtureIdentifiers()
        let extractedProfileId: Int64 = 1
        let historyEvent = HistoryEvent(extractedProfileId: extractedProfileId,
                                        brokerId: identifiers.brokerId,
                                        profileQueryId: identifiers.profileQueryId,
                                        type: .optOutRequested)

        let optOutJobData = OptOutJobData(brokerId: identifiers.brokerId,
                                          profileQueryId: identifiers.profileQueryId,
                                          createdDate: Date(),
                                          preferredRunDate: Date(),
                                          historyEvents: [historyEvent],
                                          attemptCount: 0,
                                          submittedSuccessfullyDate: nil,
                                          extractedProfile: ExtractedProfile(id: extractedProfileId))

        let brokerData = BrokerProfileQueryData(dataBroker: .mock,
                                                profileQuery: .mock,
                                                scanJobData: .init(brokerId: identifiers.brokerId,
                                                                   profileQueryId: identifiers.profileQueryId,
                                                                   historyEvents: [historyEvent]),
                                                optOutJobData: [optOutJobData])

        let throwingDatabase = MockDatabase()
        throwingDatabase.brokerProfileQueryDataToReturn = [brokerData]
        throwingDatabase.updateSubmittedSuccessfullyDateError = MockDatabase.MockError.saveFailed

        XCTAssertThrowsError(try sut.updateOperationDataDates(origin: .scan,
                                                              brokerId: identifiers.brokerId,
                                                              profileQueryId: identifiers.profileQueryId,
                                                              extractedProfileId: extractedProfileId,
                                                              schedulingConfig: .default,
                                                              database: throwingDatabase)) { error in
            XCTAssertEqual(error as? MockDatabase.MockError, .saveFailed)
        }
    }

    // MARK: - Notification tests

    func testWhenOnlyOneProfileIsFoundAndRemoved_thenAllInfoRemovedNotificationIsSent() async {
        do {
            let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

            let brokerId: Int64 = 1
            let profileQueryId: Int64 = 1
            let extractedProfileId: Int64 = 1
            let currentPreferredRunDate = Date()

            let mockDataBroker = DataBroker(name: "databroker",
                                            url: "databroker.com",
                                            steps: [Step](),
                                            version: "1.0",
                                            schedulingConfig: config,
                                            optOutUrl: "",
                                            eTag: "",
                                            removedAt: nil)
            let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

            let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
            let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

            let extractedProfileSaved = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc")

            let optOutData = [OptOutJobData.mock(with: extractedProfileSaved)]

            let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                                profileQuery: mockProfileQuery,
                                                                scanJobData: mockScanOperation,
                                                                optOutJobData: optOutData)
            mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

            mockScanRunner.scanResults = []
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: extractedProfileSaved)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockEventsHandler.allProfilesRemovedFired)
            XCTAssertFalse(mockEventsHandler.firstProfileRemovedFired)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenManyProfilesAreFoundAndOnlyOneRemoved_thenFirstRemovedNotificationIsSent() async {
        do {

            let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

            let brokerId: Int64 = 1
            let profileQueryId: Int64 = 1
            let extractedProfileId: Int64 = 1
            let currentPreferredRunDate = Date()

            let mockDataBroker = DataBroker(name: "databroker",
                                            url: "databroker.com",
                                            steps: [Step](),
                                            version: "1.0",
                                            schedulingConfig: config,
                                            optOutUrl: "",
                                            eTag: "",
                                            removedAt: nil)
            let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

            let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
            let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

            let extractedProfileSaved1 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc", identifier: "abc")
            let extractedProfileSaved2 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "zxz", identifier: "zxz")

            let optOutData = [OptOutJobData.mock(with: extractedProfileSaved1),
                              OptOutJobData.mock(with: extractedProfileSaved2)]

            let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                                profileQuery: mockProfileQuery,
                                                                scanJobData: mockScanOperation,
                                                                optOutJobData: optOutData)
            mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

            mockScanRunner.scanResults = [extractedProfileSaved1]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: extractedProfileSaved1),
                                    OptOutJobData.mock(with: extractedProfileSaved2)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockEventsHandler.allProfilesRemovedFired)
            XCTAssertTrue(mockEventsHandler.firstProfileRemovedFired)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenNoProfilesAreRemoved_thenNoNotificationsAreSent() async {
        do {

            let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

            let brokerId: Int64 = 1
            let profileQueryId: Int64 = 1
            let extractedProfileId: Int64 = 1
            let currentPreferredRunDate = Date()

            let mockDataBroker = DataBroker(name: "databroker",
                                            url: "databroker.com",
                                            steps: [Step](),
                                            version: "1.0",
                                            schedulingConfig: config,
                                            optOutUrl: "",
                                            eTag: "",
                                            removedAt: nil)
            let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

            let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
            let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

            let extractedProfileSaved1 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc")
            let extractedProfileSaved2 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "zxz")

            let optOutData = [OptOutJobData.mock(with: extractedProfileSaved1),
                              OptOutJobData.mock(with: extractedProfileSaved2)]

            let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                                profileQuery: mockProfileQuery,
                                                                scanJobData: mockScanOperation,
                                                                optOutJobData: optOutData)
            mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

            mockScanRunner.scanResults = [extractedProfileSaved1, extractedProfileSaved2]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: extractedProfileSaved1),
                                    OptOutJobData.mock(with: extractedProfileSaved2)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockEventsHandler.allProfilesRemovedFired)
            XCTAssertFalse(mockEventsHandler.firstProfileRemovedFired)
        } catch {
            XCTFail("Should not throw")
        }
    }

    // MARK: - Run scan operation tests

    func testWhenProfileQueryIdIsNil_thenRunScanThrows() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mockWithoutId,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockScanRunner.wasScanCalled)
        }
    }

    func testWhenBrokerIdIsNil_thenRunScanThrows() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mockWithoutId,
                    profileQuery: .mock,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id for broker")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
        }
    }

    func testWhenScanStarts_thenScanStartedEventIsAddedToTheDatabase() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertEqual(mockDatabase.scanEvents.first?.type, .scanStarted)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScanDoesNotFoundProfiles_thenNoMatchFoundEventIsAddedToTheDatabase() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.scanEvents.contains(where: { $0.type == .noMatchFound }))
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScannedProfileIsAlreadyInTheDatabase_noOptOutOperationIsCreated() async {
        do {
            mockDatabase.extractedProfilesFromBroker = [.mockWithoutRemovedDate]
            mockScanRunner.scanResults = [.mockWithoutRemovedDate]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNil(mockDatabase.extractedProfileRemovedDate)
            XCTAssertFalse(mockDatabase.wasSaveOptOutOperationCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScannedProfileIsAlreadyInTheDatabaseAndWasRemoved_thenTheRemovedDateIsSetBackToNil() async {
        do {
            mockDatabase.extractedProfilesFromBroker = [.mockWithRemovedDate]
            mockScanRunner.scanResults = [.mockWithRemovedDate]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNil(mockDatabase.extractedProfileRemovedDate)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScannedProfileIsAlreadyInTheDatabaseAndWasNotFoundInBroker_thenTheRemovedDateIsSet() async {
        do {
            mockScanRunner.scanResults = []
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNotNil(mockDatabase.extractedProfileRemovedDate)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenNewExtractedProfileIsNotInDatabase_thenIsAddedToTheDatabaseAndOptOutOperationIsCreated() async {
        do {
            mockScanRunner.scanResults = [.mockWithoutId]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.wasSaveOptOutOperationCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenRemovedProfileIsFound_thenOptOutConfirmedIsAddedRemoveDateIsUpdated() async {
        do {
            mockScanRunner.scanResults = [.mockWithoutId]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutConfirmed }))
            XCTAssertTrue(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNotNil(mockDatabase.extractedProfileRemovedDate)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenNoRemovedProfilesAreFound_thenNoOtherEventIsAdded() async {
        do {
            mockScanRunner.scanResults = [.mockWithoutRemovedDate]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutConfirmed }))
            XCTAssertFalse(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNil(mockDatabase.extractedProfileRemovedDate)
            XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenErrorIsCaught_thenEventIsAddedToTheDatabase() async {
        do {
            mockScanRunner.shouldScanThrow = true
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Should throw!")
        } catch {
            XCTAssertTrue(mockDatabase.wasAddHistoryEventCalled)
            XCTAssertTrue(mockDatabase.scanEvents.contains(where: { $0.type == .error(error: .unknown("Test error")) }))
            XCTAssertFalse(mockDatabase.scanEvents.contains(where: { $0.type == .matchesFound(count: 1) }))
            XCTAssertFalse(mockDatabase.scanEvents.contains(where: { $0.type == .noMatchFound }))
            XCTAssertFalse(mockDatabase.wasSaveOptOutOperationCalled)
        }
    }

    func testWhenUpdatingDatesOnOptOutAndLastEventIsError_thenWeSetPreferredRunDateWithRetryErrorDate() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: .unknown("Test error")))
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 1, confirmOptOutScan: 0, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(schedulingConfig.retryError.hoursToSeconds)))
    }

    func testWhenUpdatingDatesOnScanAndLastEventIsError_thenWeSetPreferredRunDateWithRetryErrorDate() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: nil, brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: .unknown("Test error")))
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 1, confirmOptOutScan: 0, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: nil, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: Date().addingTimeInterval(schedulingConfig.retryError.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsOptOutRequested_thenWeSetScanPreferredRunDateWithConfirmOptOutDate() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 1, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: Date().addingTimeInterval(schedulingConfig.confirmOptOutScan.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsOptOutRequested_thenWeSetOptOutPreferredRunDateToOptOutReattempt() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 1, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(schedulingConfig.hoursUntilNextOptOutAttempt.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsMatchesFound_thenWeSetScanPreferredDateToMaintenance() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .matchesFound(count: 0))
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 0, maintenanceScan: 1, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: Date().addingTimeInterval(schedulingConfig.maintenanceScan.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsOptOutStarted_thenNothingHappens() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutStarted)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 0, maintenanceScan: 1, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnScan)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnOptOut)
    }

    func testWhenUpdatingDatesAndLastEventIsScanStarted_thenNothingHappens() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .scanStarted)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 0, maintenanceScan: 1, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnScan)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnOptOut)
    }

    func testUpdatingScanDateFromOptOut_thenScanRespectMostRecentDate() throws {
        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()

        let mockDataBroker = DataBroker(name: "databroker",
                                        url: "databroker.com",
                                        steps: [Step](),
                                        version: "1.0",
                                        schedulingConfig: config,
                                        optOutUrl: "",
                                        eTag: "",
                                        removedAt: nil)
        let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

        let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
        let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

        let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker, profileQuery: mockProfileQuery, scanJobData: mockScanOperation)
        mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

        try sut.updateOperationDataDates(origin: .optOut, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: config, database: mockDatabase)

        // If the date is not going to be set, we don't call the database function
        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(config.hoursUntilNextOptOutAttempt.hoursToSeconds)))
    }

    func testUpdatingScanDateFromScan_thenScanDoesNotRespectMostRecentDate() throws {
        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()
        let expectedPreferredRunDate = Date().addingTimeInterval(config.confirmOptOutScan.hoursToSeconds)

        let mockDataBroker = DataBroker(name: "databroker",
                                        url: "databroker.com",
                                        steps: [Step](),
                                        version: "1.0",
                                        schedulingConfig: config,
                                        optOutUrl: "",
                                        eTag: "",
                                        removedAt: nil)
        let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

        let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
        let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

        let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker, profileQuery: mockProfileQuery, scanJobData: mockScanOperation)
        mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: config, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: expectedPreferredRunDate), "\(String(describing: mockDatabase.lastPreferredRunDateOnScan)) is not equal to \(expectedPreferredRunDate)")

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(config.hoursUntilNextOptOutAttempt.hoursToSeconds)))
    }

    func testScanSubJob_whenExecutedSuccessfully_returnsTrue() async throws {
        // When
        let result = try await sut.runScan(
            brokerProfileQueryData: .init(
                dataBroker: .mock,
                profileQuery: .mock,
                scanJobData: .mock
            ),
            showWebView: false,
            isManual: false,
            shouldRunNextStep: { true }
        )

        // Then
        XCTAssertTrue(result)
    }

}
