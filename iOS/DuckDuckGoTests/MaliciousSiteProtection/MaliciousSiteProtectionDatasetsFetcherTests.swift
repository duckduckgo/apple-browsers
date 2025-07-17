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

import Testing
import Foundation
import MaliciousSiteProtection
import enum UIKit.UIBackgroundRefreshStatus
import CombineSchedulers
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
        MaliciousSiteProtectionDatasetsFetcher.resetRegisteredTaskIdentifiers()
    }

    func setupSUT(
        updateManagerMock: MockMaliciousSiteProtectionUpdateManager = .init(),
        featureFlaggerMock: MockMaliciousSiteProtectionFeatureFlags = .init(),
        userPreferencesManagerMock: MockMaliciousSiteProtectionPreferencesManager = .init(),
        dateProvider: @escaping () -> Date = Date.init,
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
            preferencesScheduler: preferencesScheduler.eraseToAnyScheduler()
        )
    }

    // MARK: - Explicitly Fetch Datasets

    @MainActor
    @Test("Fetch Datasets When Feature Is Enabled and User Turned On the Feature")
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

    @MainActor
    @Test("Do not Fetch Datasets When Feature is Disabled")
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

    @MainActor
    @Test("Do not Fetch Datasets When User Turned Off the Feature")
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

    @MainActor
    @Test("Fetch Hash Prefix Dataset When Start Fetching Is Called And Last Update Date Is Greater Than Update Interval")
    func whenStartFetchingCalled_AndLastHashPrefixSetUpdateDateIsGreaterThanUpdateInterval_ThenFetchHashPrefixSet() async throws {
        // GIVEN
        let timeTraveller = TimeTraveller()
        timeTraveller.advanceBy(-.minutes(6))
        updateManagerMock.lastHashPrefixSetUpdateDate = timeTraveller.getDate()
        updateManagerMock.lastFilterSetUpdateDate = timeTraveller.getDate()
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

    @MainActor
    @Test("Fetch Filter Dataset When Start Fetching Is Called And Last Update Date Is Greater Than Update Interval")
    func whenStartFetchingCalled_AndLastFilterSetUpdateDateIsGreaterThanUpdateInterval_ThenFetchHashPrefixSet() async throws {
        // GIVEN
        let timeTraveller = TimeTraveller()
        timeTraveller.advanceBy(-.minutes(11))
        updateManagerMock.lastHashPrefixSetUpdateDate = timeTraveller.getDate()
        updateManagerMock.lastFilterSetUpdateDate = timeTraveller.getDate()
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

    @MainActor
    @Test("Check Calling Multiple Times Start Fetching Does Not Trigger Update Tasks if Existing Are In Flight")
    func whenStartFetchingCalledMultipleTimes_AndUpdateTasksAreInFlight_ThenDoesNotTriggerUpdateTasks() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        updateManagerMock.updateDataTaskExecutionTime = 0.5
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

    @MainActor
    @Test("Check Fetching Only HashPrefix Reset InProgress Flag to False When Finishing Update")
    func whenStartFetchingCalled_AndOnlyHashPrefixNeedsUpdate_ThenResetInProgressFlagWhenUpdateFinishes() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .now
        updateManagerMock.updateDataTaskExecutionTime = 0.5
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

    @MainActor
    @Test("Check Fetching Only FilterSet Reset InProgress Flag to False When Finishing Update")
    func whenStartFetchingCalled_AndOnlyFilterSetNeedsUpdate_ThenResetInProgressFlagWhenUpdateFinishes() async throws {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .now
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        updateManagerMock.updateDataTaskExecutionTime = 0.5
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

    @MainActor
    @Test("Fetch Datasets When Update Interval Becomes Greater Than Last Update Interval")
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

    @Test("Do Not Fetch Datasets on Init when Feature Is Enabled and User Turned On the Feature")
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

    @MainActor
    @Test("Start Fetching Datasets When User Turns On the Feature And Last Update Is Greater Than Update Interval", .disabled("Flaky Test"))
    func whenPreferencesEnabled_AndLastUpdateDateIsGreaterThanUpdateInterval_ThenStartUpdateTask() async {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
        let expectation = Expectation()
        updateManagerMock.onUpdateDatasets = {
            expectation.fulfill()
        }

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // TRUE
        await preferencesScheduler.advance(by: .seconds(1))
        #expect(await expectation.wait(timeout: 0.1))
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

    @MainActor
    @Test("Check Multiple Preferences Settings Toggles And Final Preference is On Starts Fetching Tasks Only Once", .disabled("Flaky Test"))
    func whenPreferencesEnabledAndDisabledMultipleTimes_AndFinalPreferencesOn_ThenDoNotStartUpdateTask() async {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
        let expectation = Expectation()
        updateManagerMock.onUpdateDatasets = {
            expectation.fulfill()
        }

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // TRUE
        await preferencesScheduler.advance(by: .seconds(1))
        #expect(await expectation.wait(timeout: 0.1))
        #expect(updateManagerMock.updateCallCount == 2)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

    @MainActor
    @Test("Check Multiple Preferences Settings Toggles And Final Preference is Off Does Not Start Fetching Tasks")
    func whenPreferencesEnabledAndDisabledMultipleTimes_AndFinalPreferencesOff_ThenDoNotStartUpdateTask() async {
        // GIVEN
        updateManagerMock.lastHashPrefixSetUpdateDate = .distantPast
        updateManagerMock.lastFilterSetUpdateDate = .distantPast
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
        let expectation = Expectation(isInverted: true)
        updateManagerMock.onUpdateDatasets = {
            expectation.fulfill()
        }

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false

        // TRUE
        await preferencesScheduler.advance(by: .seconds(1))
        #expect(await expectation.wait(timeout: 0.1))
        #expect(updateManagerMock.updateCallCount == 0)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    @Test("Do Not Start Fetching Datasets When User Turns On the Feature and Last Update Is Smaller Than Update Interval")
    func whenPreferencesEnabled_AndLastUpdateDateIsSmallerThanUpdateInterval_ThenDoNotStartUpdateTask() {
        // GIVEN
        let now = Date()
        updateManagerMock.lastHashPrefixSetUpdateDate = now
        updateManagerMock.lastFilterSetUpdateDate = now
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // TRUE
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == false)
        #expect(updateManagerMock.updateDatasets[.filterSet] == false)
    }

    // MARK: - Background Tasks

    @Test("Schedule Background Tasks When Init And Feature Preference Is On")
    func whenInitAndFeaturePreferenceIsOnThenScheduleBackgroundTasks() async {
        // GIVEN
        let expectedBackgroundTasksIdentifiers = [
            "com.duckduckgo.app.maliciousSiteProtectionHashPrefixSetRefresh",
            "com.duckduckgo.app.maliciousSiteProtectionFilterSetRefresh",
        ]
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        setupSUT(featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock, backgroundSchedulerMock: backgroundSchedulerMock)

        await confirmation(expectedCount: 2) { submittedBackgroundTask in
            backgroundSchedulerMock.scheduleBackgroundTaskConfirmation = submittedBackgroundTask

            // WHEN
            await sut.registerBackgroundRefreshTaskHandler()

            // THEN
            await preferencesScheduler.advance(by: .seconds(1))
            #expect(backgroundSchedulerMock.submittedTaskRequests.map(\.identifier) == expectedBackgroundTasksIdentifiers)
        }
    }

    @MainActor
    @Test("Register Background Tasks")
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

    @MainActor
    @Test("Prevent register Background Tasks multiple times When RegisterBackgroundTasksIsCalled")
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

    @MainActor
    @Test(
        "Do Not Execute Background Task When Dataset Does Not Need To Update",
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
        let date = Date()
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
        let tolerance: TimeInterval = 5
        #expect(backgroundTask.didCallSetTaskCompleted)
        #expect(backgroundTask.capturedTaskCompletedSuccess == true)
        #expect(backgroundTask.expirationHandler == nil)
        #expect(backgroundSchedulerMock.didCallSubmitTaskRequest)
        let capturedSubmittedTaskRequest = try #require(backgroundSchedulerMock.capturedSubmittedTaskRequest)
        let earliestBeginDate = try #require(capturedSubmittedTaskRequest.earliestBeginDate)
        #expect(capturedSubmittedTaskRequest.identifier == identifier)
        #expect(abs(earliestBeginDate.timeIntervalSince1970 - Date(timeIntervalSinceNow: .minutes(datasetInfo.updateFrequency)).timeIntervalSince1970) < tolerance)
    }

    @MainActor
    @Test(
        "Execute Background Task When Dataset Needs To Update",
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

    @MainActor
    @Test(
        "Check Expiration Handler Cancel Task",
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

    @MainActor
    @Test("Start Background Update Task When User Turns On the Feature And Background Tasks Are Available")
    func whenUserTurnsOnProtectionThenStartBackgroundUpdateTask() {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false
        setupSUT(updateManagerMock: updateManagerMock, featureFlaggerMock: featureFlaggerMock, userPreferencesManagerMock: userPreferencesManagerMock)
        sut.registerBackgroundRefreshTaskHandler()
        #expect(!backgroundSchedulerMock.didCallSubmitTaskRequest)
        #expect(backgroundSchedulerMock.capturedSubmittedTaskRequest == nil)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // TRUE
        preferencesScheduler.advance(by: .seconds(1))
        #expect(backgroundSchedulerMock.didCallSubmitTaskRequest)
        #expect(backgroundSchedulerMock.capturedSubmittedTaskRequest != nil)
    }

    @MainActor
    @Test(
        "Do Not Start Background Update Task When User Turns On the Feature And Background Tasks Are Not Available",
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
        sut.registerBackgroundRefreshTaskHandler()
        #expect(!backgroundSchedulerMock.didCallSubmitTaskRequest)
        #expect(backgroundSchedulerMock.capturedSubmittedTaskRequest == nil)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true

        // TRUE
        #expect(!backgroundSchedulerMock.didCallSubmitTaskRequest)
        #expect(backgroundSchedulerMock.capturedSubmittedTaskRequest == nil)
    }

    @MainActor
    @Test("Stop Background Update Task When User Turns Off the Feature")
    func whenUserTurnsOffProtectionThenStopBackgroundUpdateTask() {
        // GIVEN
        featureFlaggerMock.isMaliciousSiteProtectionEnabled = true
        setupSUT(featureFlaggerMock: featureFlaggerMock)
        sut.registerBackgroundRefreshTaskHandler()
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = true
        preferencesScheduler.advance(by: .seconds(1))
        #expect(!backgroundSchedulerMock.didCallCancelTaskRequestWithIdentifier)

        // WHEN
        userPreferencesManagerMock.isMaliciousSiteProtectionOn = false

        // TRUE
        preferencesScheduler.advance(by: .seconds(1))
        #expect(backgroundSchedulerMock.didCallCancelTaskRequestWithIdentifier)
    }

    @MainActor
    @Test(
        "Test Background Task Is Not Executed If Fetch is In Progress",
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
        sut.registerBackgroundRefreshTaskHandler()
        let launchHandler = try #require(backgroundSchedulerMock.launchHandlers[identifier])
        #expect(backgroundTask.expirationHandler == nil)

        // WHEN
        let firstCallTask = sut.startFetching()

        // THEN
         #expect(sut.isDatasetsFetchInProgress)

        // WHEN
        launchHandler?(backgroundTask)

        // THEN
        await firstCallTask.value

        // THEN
        #expect(updateManagerMock.updateCallCount == 2)
        #expect(updateManagerMock.updateDatasets[.hashPrefixSet] == true)
        #expect(updateManagerMock.updateDatasets[.filterSet] == true)
    }

}

// Workaround to wait on unstructured task in tests
private final class Expectation {
    private var isFulfilled = false
    private var isFulfilledCalled: Bool = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var isInverted: Bool

    init(isInverted: Bool = false) {
        self.isInverted = isInverted
    }

    func fulfill() {
        isFulfilledCalled = true

        if isInverted {
            isFulfilled = false
        } else {
            isFulfilled = true
        }

        continuation?.resume()
    }

    func wait(timeout: TimeInterval) async -> Bool {
        if !isInverted && isFulfilled {
            return true
        }

        if isInverted && isFulfilledCalled {
            return false
        }

        let task = Task {
            try? await Task.sleep(interval: timeout)
            continuation?.resume()
        }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }

        task.cancel()

        return isInverted ? !isFulfilledCalled : isFulfilled
    }
}
