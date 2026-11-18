//
//  UserAssistanceSchedulingTests.swift
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

import Common
import DataBrokerProtectionCoreTestsUtils
import Foundation
import Testing
import WebKit
import XCTest
@_spi(Testing) import WideEvent
@testable import DataBrokerProtectionCore

struct UserAssistanceSchedulingTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [nil, "not json", #"{"enabledBrokers":["*"]}"#] as [String?])
    func missingMalformedOrWildcardSettingsEnableNoBrokers(settings: String?) {
        let privacyConfig = PrivacyConfigurationMock()
        privacyConfig.subfeatureSettings = settings
        #expect(UserAssistanceConfig(privacyConfig: privacyConfig).enabledBrokers.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [Date?.none, Date(timeIntervalSince1970: 1234), Date.distantFuture])
    func awaitingAssistancePreservesPreferredRunDate(preferredRunDate: Date?) throws {
        let date = try OperationPreferredDateCalculator().dateForOptOutOperation(
            currentPreferredRunDate: preferredRunDate,
            optOutHistoryEvents: [.mock(type: .optOutStarted), .mock(type: .optOutAwaitingUserAssistance)],
            extractedProfileID: 1, schedulingConfig: .mock, attemptCount: 0)
        #expect(date == preferredRunDate)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func awaitingAssistanceEndsTheOperationWithoutMarkingItStalled() {
        let start = Date().addingTimeInterval(-24 * 3600)
        let job = OptOutJobData.mock(with: .mockWithoutRemovedDate, historyEvents: [
            .mock(type: .optOutStarted, date: start),
            .mock(type: .optOutAwaitingUserAssistance, date: start.addingTimeInterval(60))
        ])
        let result = StalledOperationCalculator.optOut.calculate(from: [.mock(optOutJobData: [job])])
        #expect(result.total == 1)
        #expect(result.stalled == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [RegularScheduling.assistanceEnabled, .flagDisabledDuringAttempt, .flagDisabledAfterAttempt])
    func regularJobKeepsScansAndResumesWaitingOptOutAfterFlagAndAttemptEnd(state: RegularScheduling) async throws {
        let dependencies = MockBrokerProfileJobDependencies()
        let database = MockDatabase()
        dependencies.database = database
        let flagger = MockDBPFeatureFlagger(isUserAssistanceOn: true)
        dependencies.featureFlagger = flagger
        let manager = PrivacyConfigurationManagingMock()
        let privacyConfig = PrivacyConfigurationMock()
        privacyConfig.subfeatureSettings = #"{"enabledBrokers":["testbroker.com"]}"#
        manager.privacyConfig = privacyConfig
        dependencies.privacyConfig = manager
        let history = [HistoryEvent.mock(type: .optOutAwaitingUserAssistance)]
        let optOut = OptOutJobData.mock(with: .mockWithoutRemovedDate, preferredRunDate: .distantPast, historyEvents: history)
        let data = BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: .mock, optOutJobData: [optOut])
        database.brokerProfileQueryDataToReturn = [data]
        database.optOutToReturn = optOut
        database.optOutEvents = history
        database.extractedProfilesFromBroker = [optOut.extractedProfile]
        dependencies.mockScanRunner.scanResults = [optOut.extractedProfile]
        let id = AssistedOptOutID(brokerId: optOut.brokerId, profileQueryId: optOut.profileQueryId,
                                  extractedProfileId: try #require(optOut.extractedProfile.id))
        if state != .assistanceEnabled {
            dependencies.runningAssistedOptOuts.insert(id)
            flagger.isUserAssistanceOn = false
            if state == .flagDisabledAfterAttempt {
                dependencies.runningAssistedOptOuts.remove(id)
            }
        }
        let delegate = MockBrokerProfileJobStatusReportingDelegate()
        let job = BrokerProfileJob(dataBrokerID: optOut.brokerId, jobType: .all, showWebView: false,
                                   statusReportingDelegate: delegate, jobDependencies: dependencies)
        let completed = XCTestExpectation(description: "Broker job completed")
        job.completionBlock = { completed.fulfill() }
        job.start()
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 15)
        try #require(result == .completed)

        #expect(job.isFinished)
        #expect(dependencies.mockScanRunner.wasScanCalled)
        #expect(database.scanEvents.contains { $0.type == .scanStarted })
        let shouldRunOptOut = state == .flagDisabledAfterAttempt
        #expect(dependencies.mockOptOutRunner.wasOptOutCalled == shouldRunOptOut)
        if shouldRunOptOut {
            #expect(database.optOutEvents.map(\.type) == [.optOutAwaitingUserAssistance, .optOutStarted, .optOutRequested])
        } else {
            #expect(database.optOutEvents.map(\.type) == history.map(\.type))
            #expect(!database.wasUpdatedPreferredRunDateForOptOutCalled)
            #expect(!database.wasUpdateLastRunDateForOptOutCalled)
            #expect(optOut.preferredRunDate == .distantPast)
        }
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [AssistedEnd.cancelled, .failed, .timedOut, .submitted])
    func assistedEndUsesOnlyAssistedHistoryAndSkipsRegularWideEvents(end: AssistedEnd) async throws {
        let dependencies = MockBrokerProfileJobDependencies()
        let database = MockDatabase()
        let wideEvent = WideEventMock()
        dependencies.database = database
        dependencies.wideEvent = wideEvent
        var failurePixels = 0
        dependencies.pixelHandler = EventMapping { event, _, _, _ in
            if case .optOutFailure = event { failurePixels += 1 }
        }
        let preferredDate = Date.distantPast
        let job = OptOutJobData.mock(with: .mockWithoutRemovedDate, preferredRunDate: preferredDate)
        database.optOutToReturn = job
        let data = BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: .mock, optOutJobData: [job])
        let globalID = OptOutWideEventIdentifier(brokerId: job.brokerId, profileQueryId: job.profileQueryId,
                                                extractedProfileId: try #require(job.extractedProfile.id)).toGlobalId
        let interval = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 1234), end: nil)
        let submission = OptOutSubmissionWideEventData(globalData: .init(id: globalID), dataBrokerURL: data.dataBroker.url,
                                                       dataBrokerVersion: data.dataBroker.version, submissionInterval: interval)
        let confirmation = OptOutConfirmationWideEventData(globalData: .init(id: globalID), dataBrokerURL: data.dataBroker.url,
                                                           dataBrokerVersion: data.dataBroker.version, confirmationInterval: interval)
        wideEvent.startFlow(submission)
        wideEvent.startFlow(confirmation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let priorSubmission = try encoder.encode(submission)
        let priorConfirmation = try encoder.encode(confirmation)
        let observer = SchedulingAssistanceObserver()
        dependencies.mockAssistedOptOutRunner.optOutHandler = {
            #expect(database.optOutEvents.map(\.type) == [.optOutStarted])
            switch end {
            case .cancelled: throw CancellationError()
            case .failed: throw DataBrokerProtectionError.unknown("failure")
            case .timedOut: throw DataBrokerProtectionError.jobTimeout
            case .submitted: break
            }
        }
        do {
            let submitted = try await BrokerProfileOptOutSubJob(dependencies: dependencies).runAssistedOptOut(
                for: job.extractedProfile, brokerProfileQueryData: data, observer: observer, shouldRunNextStep: { true })
            #expect(end == .submitted)
            #expect(submitted)
        } catch {
            #expect(end != .submitted)
        }
        #expect(dependencies.assistedRunnerObserver === observer)
        #expect(!dependencies.mockOptOutRunner.wasOptOutCalled)
        #expect(database.optOutEvents.map(\.type) == [.optOutStarted, end == .submitted ? .optOutRequested : .optOutAwaitingUserAssistance])
        if end != .submitted {
            #expect(!database.wasUpdatedPreferredRunDateForOptOutCalled)
            #expect(job.preferredRunDate == preferredDate)
            #expect(database.attemptCount == 0)
        }
        #expect(failurePixels == (end == .failed ? 1 : 0))
        #expect(wideEvent.started.count == 2)
        #expect(wideEvent.updates.isEmpty)
        #expect(wideEvent.completions.isEmpty)
        #expect(wideEvent.discarded.isEmpty)
        let storedSubmission = try #require(wideEvent.getFlowData(OptOutSubmissionWideEventData.self, globalID: globalID))
        let storedConfirmation = try #require(wideEvent.getFlowData(OptOutConfirmationWideEventData.self, globalID: globalID))
        #expect(try encoder.encode(storedSubmission) == priorSubmission)
        #expect(try encoder.encode(storedConfirmation) == priorConfirmation)
    }

    enum RegularScheduling: Sendable {
        case assistanceEnabled, flagDisabledDuringAttempt, flagDisabledAfterAttempt
    }

    enum AssistedEnd: Sendable {
        case cancelled, failed, timedOut, submitted
    }
}

@MainActor
private final class SchedulingAssistanceObserver: OptOutAssistanceObserving {
    func attemptDidCreate(webView: WKWebView) {}
    func attemptWillRun(_ action: Action) {}
    func attemptNeedsUser(actionID: String) {}
}
