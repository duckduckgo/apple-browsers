//
//  MaliciousSiteProtectionDatasetsFetcherTests.swift
//  DuckDuckGo
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

import CombineSchedulers
import enum UIKit.UIBackgroundRefreshStatus
import Foundation
import FoundationExtensions
import MaliciousSiteProtection
import Testing
@testable import DuckDuckGo

@Suite("Malicious Site Protection - Datasets Fetcher")
final class MaliciousSiteProtectionDatasetsFetcherTests {
    private var sut: MaliciousSiteProtectionDatasetsFetcher!
    private var updateManagerMock: MockMaliciousSiteProtectionUpdateManager!
    private var featureFlaggerMock: MockMaliciousSiteProtectionFeatureFlags!
    private var userPreferencesManagerMock: MockMaliciousSiteProtectionPreferencesManager!
    private var backgroundSchedulerMock: MockBackgroundScheduler!
    private var timeTraveller: TimeTraveller!
    private var application: MockBackgroundRefreshApplication!
    private var preferencesScheduler: TestSchedulerOf<DispatchQueue>!

    init() {
        setupSUT()
    }

    func setupSUT(
        updateManagerMock: MockMaliciousSiteProtectionUpdateManager = .init(),
        featureFlaggerMock: MockMaliciousSiteProtectionFeatureFlags = .init(),
        userPreferencesManagerMock: MockMaliciousSiteProtectionPreferencesManager = .init(),
        backgroundSchedulerMock: MockBackgroundScheduler = .init(),
        application: MockBackgroundRefreshApplication = .init(),
        preferencesScheduler: TestSchedulerOf<DispatchQueue> = DispatchQueue.test
    ) {
        self.updateManagerMock = updateManagerMock
        self.featureFlaggerMock = featureFlaggerMock
        self.userPreferencesManagerMock = userPreferencesManagerMock
        self.backgroundSchedulerMock = backgroundSchedulerMock
        self.timeTraveller = TimeTraveller()
        self.application = application
        self.preferencesScheduler = preferencesScheduler

        sut = MaliciousSiteProtectionDatasetsFetcher(
            updateManager: updateManagerMock,
            featureFlagger: featureFlaggerMock,
            userPreferencesManager: userPreferencesManagerMock,
            dateProvider: timeTraveller.getDate,
            backgroundTaskScheduler: backgroundSchedulerMock,
            application: application,
            preferencesScheduler: preferencesScheduler.eraseToAnyScheduler(),
            backgroundTaskRegistrations: .init(),
            featureFlagChanges: { nil }
        )
    }

    @MainActor
    private func deliverPreferenceChanges() {
        preferencesScheduler.advance(by: .seconds(1))
    }

    // MARK: - Explicitly Fetch Datasets

    @available(iOS 16, *)
    @MainActor
    @Test("Fetch Datasets When Feature Is Enabled and User Turned On the Feature", .timeLimit(.minutes(1)))
    func whenStartFetchingCalled_AndFeatureEnabled_AndPreferencesEnabled_ThenStartUpdateTask() async throws {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        setupSUT(featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        await sut.startFetching().value

        // THEN
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Do not Fetch Datasets When Feature is Disabled", .timeLimit(.minutes(1)))
    func whenStartFetchingCalled_AndFeatureDisabled_ThenDoNotStartUpdateTask() {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        sut.startFetching()

        // THEN
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Do not Fetch Datasets When User Turned Off the Feature", .timeLimit(.minutes(1)))
    func whentartFetchingCalled_AndFeatureEnabled_AndPreferencesDisabled_ThenDoNotStartUpdateTask() {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        sut.startFetching()

        // THEN
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Fetch Hash Prefix Dataset When Start Fetching Is Called And Last Update Date Is Greater Than Update Interval", .timeLimit(.minutes(1)))
    func whenStartFetchingCalled_AndLastHashPrefixSetUpdateDateIsGreaterThanUpdateInterval_ThenFetchHashPrefixSet() async throws {
        // GIVEN
        let lastUpdate = timeTraveller.getDate().addingTimeInterval(-.minutes(6))
        updateManagerMock.lastHashPrefixSetUpdateDate = lastUpdate
        updateManagerMock.lastFilterSetUpdateDate = lastUpdate
        featureFlaggerMock.hashPrefixUpdateFrequency = 5 // Value expressed in minutes
        featureFlaggerMock.filterSetUpdateFrequency = 10 // Value expressed in minutes
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        await sut.startFetching().value

        // THEN
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Fetch Filter Dataset When Start Fetching Is Called And Last Update Date Is Greater Than Update Interval", .timeLimit(.minutes(1)))
    func whenStartFetchingCalled_AndLastFilterSetUpdateDateIsGreaterThanUpdateInterval_ThenFetchHashPrefixSet() async throws {
        // GIVEN
        let lastUpdate = timeTraveller.getDate().addingTimeInterval(-.minutes(11))
        updateManagerMock.lastHashPrefixSetUpdateDate = lastUpdate
        updateManagerMock.lastFilterSetUpdateDate = lastUpdate
        featureFlaggerMock.hashPrefixUpdateFrequency = 15 // Value expressed in minutes
        featureFlaggerMock.filterSetUpdateFrequency = 10 // Value expressed in minutes
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        await sut.startFetching().value

        // THEN
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Check Calling Multiple Times Start Fetching Does Not Trigger Update Tasks if Existing Are In Flight", .timeLimit(.minutes(1)))
    func whenStartFetchingCalledMultipleTimes_AndUpdateTasksAreInFlight_ThenDoesNotTriggerUpdateTasks() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        featureFlaggerMock.hashPrefixUpdateFrequency = 1 // Value expressed in minutes
        featureFlaggerMock.filterSetUpdateFrequency = 1 // Value expressed in minutes
        #expect(!sut.isDatasetsFetchInProgress)

        // WHEN
        let firstCallTask = sut.startFetching()

        // THEN
        #expect(sut.isDatasetsFetchInProgress)

        // WHEN
        let secondCallTask = sut.startFetching()

        // THEN
        await firstCallTask.value
        await secondCallTask.value

        #expect(updateManagerMock.updateCallCount == 2)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
        #expect(!sut.isDatasetsFetchInProgress)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Check Fetching Only HashPrefix Reset InProgress Flag to False When Finishing Update", .timeLimit(.minutes(1)))
    func whenStartFetchingCalled_AndOnlyHashPrefixNeedsUpdate_ThenResetInProgressFlagWhenUpdateFinishes() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = timeTraveller.getDate()
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        featureFlaggerMock.hashPrefixUpdateFrequency = 1 // Value expressed in minutes
        featureFlaggerMock.filterSetUpdateFrequency = 1 // Value expressed in minutes
        #expect(!sut.isDatasetsFetchInProgress)

        // WHEN
        let task = sut.startFetching()
        #expect(sut.isDatasetsFetchInProgress)

        // THEN
        await task.value
        #expect(updateManagerMock.updateCallCount == 1)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
        #expect(!sut.isDatasetsFetchInProgress)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Check Fetching Only FilterSet Reset InProgress Flag to False When Finishing Update", .timeLimit(.minutes(1)))
    func whenStartFetchingCalled_AndOnlyFilterSetNeedsUpdate_ThenResetInProgressFlagWhenUpdateFinishes() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = timeTraveller.getDate()
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        featureFlaggerMock.hashPrefixUpdateFrequency = 1 // Value expressed in minutes
        featureFlaggerMock.filterSetUpdateFrequency = 1 // Value expressed in minutes
        #expect(!sut.isDatasetsFetchInProgress)

        // WHEN
        let task = sut.startFetching()
        #expect(sut.isDatasetsFetchInProgress)

        // THEN
        await task.value
        #expect(updateManagerMock.updateCallCount == 1)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
        #expect(!sut.isDatasetsFetchInProgress)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Fetch Datasets When Update Interval Becomes Greater Than Last Update Interval", .timeLimit(.minutes(1)))
    func whenStartFetchingCalled_AndUpdateIntervalBecomesGraterThanLastUpdateDate_ThenFetchDatasets() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = timeTraveller.getDate()
        updateManagerMock.lastFilterSetUpdateDate = timeTraveller.getDate()
        featureFlaggerMock.hashPrefixUpdateFrequency = 15 // Value expressed in minutes
        featureFlaggerMock.filterSetUpdateFrequency = 10 // Value expressed in minutes
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        sut.startFetching()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        timeTraveller.advanceBy(.minutes(16))
        await sut.startFetching().value

        // THEN
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

    // MARK: - Events Upon User Preference Subscription

    @available(iOS 16, *)
    @Test("Do Not Fetch Datasets on Init when Feature Is Enabled and User Turned On the Feature", .timeLimit(.minutes(1)))
    func whenInitialized_AndFeatureEnabled_AndPreferencesEnabled_ThenStartUpdateTask() {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // WHEN
        setupSUT(featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)

        // THEN
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Start Fetching Datasets When User Turns On the Feature And Last Update Is Greater Than Update Interval", .timeLimit(.minutes(1)))
    func whenPreferencesEnabled_AndLastUpdateDateIsGreaterThanUpdateInterval_ThenStartUpdateTask() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // THEN
        deliverPreferenceChanges()
        let fetch = try #require(sut.datasetFetchTask)
        await fetch.value
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Check Multiple Preferences Settings Toggles And Final Preference is On Starts Fetching Tasks Only Once", .timeLimit(.minutes(1)))
    func whenPreferencesEnabledAndDisabledMultipleTimes_AndFinalPreferencesOn_ThenStartUpdateTaskOnce() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // THEN
        deliverPreferenceChanges()
        let fetch = try #require(sut.datasetFetchTask)
        await fetch.value
        #expect(updateManagerMock.updateCallCount == 2)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Check Multiple Preferences Settings Toggles And Final Preference is Off Does Not Start Fetching Tasks", .timeLimit(.minutes(1)))
    func whenPreferencesEnabledAndDisabledMultipleTimes_AndFinalPreferencesOff_ThenDoNotStartUpdateTask() {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false

        // THEN
        deliverPreferenceChanges()
        #expect(sut.datasetFetchTask == nil)
        #expect(updateManagerMock.updateCallCount == 0)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Do Not Start Fetching Datasets When User Turns On the Feature and Last Update Is Smaller Than Update Interval", .timeLimit(.minutes(1)))
    func whenPreferencesEnabled_AndLastUpdateDateIsSmallerThanUpdateInterval_ThenDoNotStartUpdateTask() {
        // GIVEN
        let now = timeTraveller.getDate()
        updateManagerMock.lastHashPrefixSetUpdateDate = now
        updateManagerMock.lastFilterSetUpdateDate = now
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // THEN
        deliverPreferenceChanges()
        #expect(sut.datasetFetchTask == nil)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    // MARK: - Background Tasks

    @available(iOS 16, *)
    @MainActor
    @Test("Schedule Background Tasks When Init And Feature Preference Is On", .timeLimit(.minutes(1)))
    func whenInitAndFeaturePreferenceIsOnThenScheduleBackgroundTasks() {
        // GIVEN
        let expectedBackgroundTasksIdentifiers = [
            "com.duckduckgo.app.maliciousSiteProtectionHashPrefixSetRefresh",
            "com.duckduckgo.app.maliciousSiteProtectionFilterSetRefresh",
        ]
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        setupSUT(featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock, backgroundSchedulerMock: backgroundSchedulerMock)

        // WHEN
        sut.registerBackgroundRefreshTaskHandler()
        deliverPreferenceChanges()

        // THEN
        #expect(backgroundSchedulerMock.submittedTaskRequests.map(\.identifier) == expectedBackgroundTasksIdentifiers)
        #expect(sut.datasetFetchTask == nil)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Register Background Tasks", .timeLimit(.minutes(1)))
    func whenRegisterBackgroundRefreshTaskHandlerIsCalledThenRegisterBackgroundTasks() {
        // GIVEN
        let expectedBackgroundTasksIdentifiers = [
            "com.duckduckgo.app.maliciousSiteProtectionHashPrefixSetRefresh",
            "com.duckduckgo.app.maliciousSiteProtectionFilterSetRefresh",
        ]
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers.isEmpty)

        // WHEN
        sut.registerBackgroundRefreshTaskHandler()

        // THEN
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers[expectedBackgroundTasksIdentifiers[0]] != nil)
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers[expectedBackgroundTasksIdentifiers[1]] != nil)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Prevent register Background Tasks multiple times When RegisterBackgroundTasksIsCalled", .timeLimit(.minutes(1)))
    func whenRegisterBackgroundTasksIsCalledThenItAsksDataFetcherToRegisterBackgroundTasks() {
        // GIVEN
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers.isEmpty)

        // WHEN registering the first time
        sut.registerBackgroundRefreshTaskHandler()

        // THEN
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers["com.duckduckgo.app.maliciousSiteProtectionHashPrefixSetRefresh"] == 1)
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers["com.duckduckgo.app.maliciousSiteProtectionFilterSetRefresh"] == 1)

        // WHEN registering a second time
        sut.registerBackgroundRefreshTaskHandler()

        // THEN there are no more registration happening
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers["com.duckduckgo.app.maliciousSiteProtectionHashPrefixSetRefresh"] == 1)
        #expect(backgroundSchedulerMock.capturedRegisteredTaskIdentifiers["com.duckduckgo.app.maliciousSiteProtectionFilterSetRefresh"] == 1)
    }

    @available(iOS 16, *)
    @MainActor
    @Test(
        "Do Not Execute Background Task When Dataset Does Not Need To Update",
        .timeLimit(.minutes(1)),
        arguments: [
            (type: DataManager.StoredDataType.Kind.hashPrefixSet, updateFrequency: 1),
            (type: .filterSet, updateFrequency: 5),
        ]
    )
    func whenRegisterBackgroundRefreshTaskHandlerIsExecuted_AndShouldNotRefreshDataset_ThenSetTaskCompletedTrueAndScheduleRefreshTask(datasetInfo: (type: DataManager.StoredDataType.Kind, updateFrequency: Int)) throws {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        featureFlaggerMock.hashPrefixUpdateFrequency = 1
        featureFlaggerMock.filterSetUpdateFrequency = 5
        let date = timeTraveller.getDate()
        updateManagerMock.lastHashPrefixSetUpdateDate = date
        updateManagerMock.lastFilterSetUpdateDate = date
        let identifier = datasetInfo.type.backgroundTaskIdentifier
        let backgroundTask = MockBGTask(identifier: identifier)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(!backgroundTask.didCallSetTaskCompleted)
        #expect(backgroundTask.capturedTaskCompletedSuccess == nil)
        let launchHandler = try #require(backgroundSchedulerMock.launchHandlers[identifier])

        // WHEN
        launchHandler?(backgroundTask)

        // THEN
        #expect(backgroundTask.didCallSetTaskCompleted)
        #expect(backgroundTask.capturedTaskCompletedSuccess == true)
        #expect(backgroundTask.expirationHandler == nil)
        #expect(backgroundSchedulerMock.didCallSubmitTaskRequest)
        let capturedSubmittedTaskRequest = try #require(backgroundSchedulerMock.capturedSubmittedTaskRequest)
        let earliestBeginDate = try #require(capturedSubmittedTaskRequest.earliestBeginDate)
        #expect(capturedSubmittedTaskRequest.identifier == identifier)
        #expect(earliestBeginDate == date.addingTimeInterval(.minutes(datasetInfo.updateFrequency)))
    }

    @available(iOS 16, *)
    @MainActor
    @Test(
        "Execute Background Task When Dataset Needs To Update",
        .timeLimit(.minutes(1)),
        arguments: [
            DataManager.StoredDataType.Kind.hashPrefixSet,
            .filterSet,
        ]
    )
    func whenRegisterBackgroundRefreshTaskHandlerIsExecuted_AndShouldRefreshDataset_ThenRunTask(datasetType: DataManager.StoredDataType.Kind) throws {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        let identifier = datasetType.backgroundTaskIdentifier
        let backgroundTask = MockBGTask(identifier: identifier)
        sut.registerBackgroundRefreshTaskHandler()
        let launchHandler = try #require(backgroundSchedulerMock.launchHandlers[identifier])
        #expect(backgroundTask.expirationHandler == nil)

        // WHEN
        launchHandler?(backgroundTask)

        // THEN
        #expect(backgroundTask.expirationHandler != nil)
    }

    @available(iOS 16, *)
    @MainActor
    @Test(
        "Check Expiration Handler Cancel Task",
        .timeLimit(.minutes(1)),
        arguments: [
            DataManager.StoredDataType.Kind.hashPrefixSet,
            .filterSet,
        ]
    )
    func whenExpirationHandlerIsCalledThenCancelTask(datasetType: DataManager.StoredDataType.Kind) throws {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        let identifier = datasetType.backgroundTaskIdentifier
        let backgroundTask = MockBGTask(identifier: identifier)
        sut.registerBackgroundRefreshTaskHandler()
        let launchHandler = try #require(backgroundSchedulerMock.launchHandlers[identifier])
        #expect(!backgroundTask.didCallSetTaskCompleted)
        #expect(backgroundTask.capturedTaskCompletedSuccess == nil)
        launchHandler?(backgroundTask)

        // WHEN
        backgroundTask.expirationHandler?()

        // THEN
        #expect(backgroundTask.didCallSetTaskCompleted)
        #expect(backgroundTask.capturedTaskCompletedSuccess == false)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Start Background Update Task When User Turns On the Feature And Background Tasks Are Available", .timeLimit(.minutes(1)))
    func whenUserTurnsOnProtectionThenStartBackgroundUpdateTask() {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        updateManagerMock.lastHashPrefixSetUpdateDate = timeTraveller.getDate()
        updateManagerMock.lastFilterSetUpdateDate = timeTraveller.getDate()
        sut.registerBackgroundRefreshTaskHandler()
        #expect(!backgroundSchedulerMock.didCallSubmitTaskRequest)
        #expect(backgroundSchedulerMock.capturedSubmittedTaskRequest == nil)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // THEN
        deliverPreferenceChanges()
        #expect(backgroundSchedulerMock.submittedTaskRequests.map(\.identifier) == DataManager.StoredDataType.Kind.allCases.map(\.backgroundTaskIdentifier))
    }

    @available(iOS 16, *)
    @MainActor
    @Test(
        "Do Not Start Background Update Task When User Turns On the Feature And Background Tasks Are Not Available",
        .timeLimit(.minutes(1)),
        arguments: [
            UIBackgroundRefreshStatus.denied,
            .restricted,
        ]
    )
    func whenUserTurnsOnProtectionThenStartBackgroundUpdateTask(backgroundRefreshStatus: UIBackgroundRefreshStatus) {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        application.backgroundRefreshStatus = backgroundRefreshStatus
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock, application: application)
        updateManagerMock.lastHashPrefixSetUpdateDate = timeTraveller.getDate()
        updateManagerMock.lastFilterSetUpdateDate = timeTraveller.getDate()
        sut.registerBackgroundRefreshTaskHandler()
        #expect(!backgroundSchedulerMock.didCallSubmitTaskRequest)
        #expect(backgroundSchedulerMock.capturedSubmittedTaskRequest == nil)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // THEN
        deliverPreferenceChanges()
        #expect(!backgroundSchedulerMock.didCallSubmitTaskRequest)
        #expect(backgroundSchedulerMock.capturedSubmittedTaskRequest == nil)
    }

    @available(iOS 16, *)
    @MainActor
    @Test("Stop Background Update Task When User Turns Off the Feature", .timeLimit(.minutes(1)))
    func whenUserTurnsOffProtectionThenStopBackgroundUpdateTask() {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        setupSUT(featureFlaggerMock: featureFlaggerMock)
        updateManagerMock.lastHashPrefixSetUpdateDate = timeTraveller.getDate()
        updateManagerMock.lastFilterSetUpdateDate = timeTraveller.getDate()
        sut.registerBackgroundRefreshTaskHandler()
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        deliverPreferenceChanges()
        let expectedIdentifiers = DataManager.StoredDataType.Kind.allCases.map(\.backgroundTaskIdentifier)
        #expect(backgroundSchedulerMock.submittedTaskRequests.map(\.identifier) == expectedIdentifiers)
        #expect(backgroundSchedulerMock.canceledTaskRequestIdentifiers.isEmpty)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false

        // THEN
        deliverPreferenceChanges()
        #expect(backgroundSchedulerMock.canceledTaskRequestIdentifiers == expectedIdentifiers)
    }

    @available(iOS 16, *)
    @MainActor
    @Test(
        "Test Background Task Is Not Executed If Fetch is In Progress",
        .timeLimit(.minutes(1)),
        arguments: [
            DataManager.StoredDataType.Kind.hashPrefixSet,
            .filterSet,
        ]
    )
    func whenBackgroundFetchFiresAndUpdateIsInProgressSkipIt(datasetType: DataManager.StoredDataType.Kind) async throws {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        let identifier = datasetType.backgroundTaskIdentifier
        let backgroundTask = MockBGTask(identifier: identifier)
        let (backgroundCompletions, backgroundCompletion) = AsyncStream<Bool>.makeStream()
        backgroundTask.onCompletion = { success in
            backgroundCompletion.yield(success)
            backgroundCompletion.finish()
        }
        sut.registerBackgroundRefreshTaskHandler()
        let launchHandler = try #require(backgroundSchedulerMock.launchHandlers[identifier])
        #expect(backgroundTask.expirationHandler == nil)

        // Hold the foreground fetch open until the background request has completed.
        let (updateRelease, releaseUpdate) = AsyncStream<Void>.makeStream()
        defer { releaseUpdate.finish() }
        updateManagerMock.nextUpdateTask = Task {
            for await _ in updateRelease {}
        }

        // WHEN
        let firstCallTask = sut.startFetching()

        // THEN
        #expect(sut.isDatasetsFetchInProgress)

        // WHEN
        launchHandler?(backgroundTask)

        // THEN
        var completions = backgroundCompletions.makeAsyncIterator()
        #expect(await completions.next() == true)
        #expect(sut.isDatasetsFetchInProgress)
        releaseUpdate.finish()
        await firstCallTask.value

        // THEN
        #expect(updateManagerMock.updateCallCount == 2)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }
}
