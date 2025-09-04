//
//  DataBrokerProtectionAgentManagerTests.swift
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

import XCTest
import Configuration
import Persistence
@testable import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import BrowserServicesKit

final class DataBrokerProtectionAgentManagerTests: XCTestCase {

    private var sut: DataBrokerProtectionAgentManager!

    private var mockActivityScheduler: MockDataBrokerProtectionBackgroundActivityScheduler!
    private var mockEventsHandler: MockOperationEventsHandler!
    private var mockNotificationService: MockUserNotificationService!
    private var mockQueueManager: MockBrokerProfileJobQueueManager!
    private var mockDataManager: MockDataBrokerProtectionDataManager!
    private var mockIPCServer: MockIPCServer!
    private var mockSharedPixelsHandler: DataBrokerProtectionCoreTestsUtils.MockPixelHandler!
    private var mockPixelHandler: MockPixelHandler!
    private var mockDependencies: MockBrokerProfileJobDependencies!
    private var mockProfile: DataBrokerProtectionProfile!
    private var mockAgentStopper: MockAgentStopper!
    private var mockConfigurationManager: MockConfigurationManager!
    private var mockPrivacyConfigurationManager: DBPPrivacyConfigurationManager!
    private var mockAuthenticationManager: MockAuthenticationManager!
    private var mockFreemiumDBPUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockBrokerUpdater: MockBrokerJSONService!
    private var mockInternalUserDecider: InternalUserDecider!
    private var mockEmailConfirmationDataService: MockEmailConfirmationDataService!

    override func setUpWithError() throws {

        mockSharedPixelsHandler = DataBrokerProtectionCoreTestsUtils.MockPixelHandler()
        mockPixelHandler = MockPixelHandler()
        mockActivityScheduler = MockDataBrokerProtectionBackgroundActivityScheduler()
        mockEventsHandler = MockOperationEventsHandler()
        mockNotificationService = MockUserNotificationService()
        mockAuthenticationManager = MockAuthenticationManager()
        mockAgentStopper = MockAgentStopper()
        mockConfigurationManager = MockConfigurationManager()
        let mockInternalUserStore = InternalUserDeciderStoreMock(isInternalUser: false)
        mockInternalUserDecider = DefaultInternalUserDecider(store: mockInternalUserStore)
        mockPrivacyConfigurationManager = DBPPrivacyConfigurationManager(internalUserDecider: mockInternalUserDecider)
        mockBrokerUpdater = MockBrokerJSONService()

        let mockDatabase = MockDatabase()
        let mockMismatchCalculator = MockMismatchCalculator(database: mockDatabase, pixelHandler: mockSharedPixelsHandler)
        mockQueueManager = MockBrokerProfileJobQueueManager(
            jobQueue: MockBrokerProfileJobQueue(),
            jobProvider: MockDataBrokerOperationsCreator(),
            mismatchCalculator: mockMismatchCalculator,
            pixelHandler: mockSharedPixelsHandler)

        mockIPCServer = MockIPCServer(machServiceName: "")

        mockDataManager = MockDataBrokerProtectionDataManager(database: mockDatabase)

        mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.database = mockDatabase
        mockDependencies.pixelHandler = mockSharedPixelsHandler
        mockDependencies.eventsHandler = mockEventsHandler

        mockProfile = DataBrokerProtectionProfile(
            names: [],
            addresses: [],
            phones: [],
            birthYear: 1992)

        mockFreemiumDBPUserStateManager = MockFreemiumDBPUserStateManager()
        mockEmailConfirmationDataService = MockEmailConfirmationDataService()
    }

    func testWhenAgentStart_andProfileExists_andUserIsNotFreemium_thenActivityIsScheduled_andScheduledAllOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = mockProfile
        mockAuthenticationManager.isUserAuthenticatedValue = true
        mockFreemiumDBPUserStateManager.didActivate = false

        let schedulerStartedExpectation = XCTestExpectation(description: "Scheduler started")
        var schedulerStarted = false
        mockActivityScheduler.startSchedulerCompletion = {
            schedulerStarted = true
            schedulerStartedExpectation.fulfill()
        }

        let scanCalledExpectation = XCTestExpectation(description: "Scan called")
        var startScheduledScansCalled = false
        mockQueueManager.startScheduledAllOperationsIfPermittedCalledCompletion = {
            startScheduledScansCalled = true
            scanCalledExpectation.fulfill()
        }

        // When
        sut.agentFinishedLaunching()

        // Then
        await fulfillment(of: [scanCalledExpectation, schedulerStartedExpectation], timeout: 1.0)
        XCTAssertTrue(schedulerStarted)
        XCTAssertTrue(startScheduledScansCalled)
    }

    func testWhenAgentStart_andProfileExists_andUserIsFreemium_thenActivityIsScheduled_andScheduledScanOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = mockProfile
        mockFreemiumDBPUserStateManager.didActivate = true

        let schedulerStartedExpectation = XCTestExpectation(description: "Scheduler started")
        var schedulerStarted = false
        mockActivityScheduler.startSchedulerCompletion = {
            schedulerStarted = true
            schedulerStartedExpectation.fulfill()
        }

        let scanCalledExpectation = XCTestExpectation(description: "Scan called")
        var startScheduledScansCalled = false
        mockQueueManager.startScheduledScanOperationsIfPermittedCalledCompletion = {
            startScheduledScansCalled = true
            scanCalledExpectation.fulfill()
        }

        // When
        sut.agentFinishedLaunching()

        // Then
        await fulfillment(of: [scanCalledExpectation, schedulerStartedExpectation], timeout: 1.0)
        XCTAssertTrue(schedulerStarted)
        XCTAssertTrue(startScheduledScansCalled)
    }

    func testWhenAgentStart_andProfileDoesNotExist_andUserIsFreemium_thenActivityIsNotScheduled_andStopAgentIsCalled() async throws {
        // Given
        let mockStopAction = MockDataProtectionStopAction()
        let agentStopper = DefaultDataBrokerProtectionAgentStopper(dataManager: mockDataManager,
                                                                   entitlementMonitor: DataBrokerProtectionEntitlementMonitor(),
                                                                   authenticationManager: MockAuthenticationManager(),
                                                                   pixelHandler: mockPixelHandler,
                                                                   stopAction: mockStopAction, freemiumDBPUserStateManager: MockFreemiumDBPUserStateManager())
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: agentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = nil
        mockFreemiumDBPUserStateManager.didActivate = true

        let stopAgentExpectation = XCTestExpectation(description: "Stop agent expectation")

        var stopAgentWasCalled = false
        mockStopAction.stopAgentCompletion = {
            stopAgentWasCalled = true
            stopAgentExpectation.fulfill()
        }

        // When
        sut.agentFinishedLaunching()
        await fulfillment(of: [stopAgentExpectation], timeout: 1.0)

        // Then
        XCTAssertTrue(stopAgentWasCalled)
    }

    func testWhenAgentStart_thenPrerequisitesAreValidated_andEntitlementsAreMonitored() async {
        // Given
        let mockAgentStopper = MockAgentStopper()

        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = nil

        let preRequisitesExpectation = XCTestExpectation(description: "preRequisitesExpectation expectation")
        var runPrerequisitesWasCalled = false
        mockAgentStopper.validateRunPrerequisitesCompletion = {
            runPrerequisitesWasCalled = true
            preRequisitesExpectation.fulfill()
        }

        let monitorEntitlementExpectation = XCTestExpectation(description: "monitorEntitlement expectation")
        var monitorEntitlementWasCalled = false
        mockAgentStopper.monitorEntitlementCompletion = {
            monitorEntitlementWasCalled = true
            monitorEntitlementExpectation.fulfill()
        }

        // When
        sut.agentFinishedLaunching()
        await fulfillment(of: [preRequisitesExpectation, monitorEntitlementExpectation], timeout: 1.0)

        // Then
        XCTAssertTrue(runPrerequisitesWasCalled)
        XCTAssertTrue(monitorEntitlementWasCalled)
    }

    func testWhenActivitySchedulerTriggers_andUserIsNotFreemium_thenScheduledAllOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = mockProfile
        mockAuthenticationManager.isUserAuthenticatedValue = true
        mockFreemiumDBPUserStateManager.didActivate = false

        var startScheduledScansCalled = false
        mockQueueManager.startScheduledAllOperationsIfPermittedCalledCompletion = {
            startScheduledScansCalled = true
        }

        // When
        await mockActivityScheduler.triggerDelegateCall()

        // Then
        XCTAssertTrue(startScheduledScansCalled)
    }

    func testWhenActivitySchedulerTriggers_andUserIsFreemium_thenScheduledScanOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = mockProfile
        mockFreemiumDBPUserStateManager.didActivate = true

        var startScheduledScansCalled = false
        mockQueueManager.startScheduledScanOperationsIfPermittedCalledCompletion = {
            startScheduledScansCalled = true
        }

        // When
        await mockActivityScheduler.triggerDelegateCall()

        // Then
        XCTAssertTrue(startScheduledScansCalled)
    }

    func testWhenProfileSaved_andUserIsNotFreemium_thenImmediateOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = mockProfile
        mockFreemiumDBPUserStateManager.didActivate = false

        var startImmediateScansCalled = false
        mockQueueManager.startImmediateScanOperationsIfPermittedCalledCompletion = {
            startImmediateScansCalled = true
        }

        // When
        await sut.profileSaved()

        // Then
        XCTAssertTrue(startImmediateScansCalled)
    }

    func testWhenProfileSaved_andUserIsFreemium_thenImmediateOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockDataManager.profileToReturn = mockProfile
        mockFreemiumDBPUserStateManager.didActivate = true

        var startImmediateScansCalled = false
        mockQueueManager.startImmediateScanOperationsIfPermittedCalledCompletion = {
            startImmediateScansCalled = true
        }

        // When
        await sut.profileSaved()

        // Then
        XCTAssertTrue(startImmediateScansCalled)
    }

    func testWhenProfileSaved_thenEventFired() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockEventsHandler.reset()

        // When
        await sut.profileSaved()

        // Then
        XCTAssertTrue(mockEventsHandler.profileSavedFired)
    }

    func testWhenProfileSaved_andScansCompleted_andNoScanError_thenEventFired() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockEventsHandler.reset()

        // When
        await sut.profileSaved()

        // Then
        XCTAssertTrue(mockEventsHandler.firstScanCompletedFired)
    }

    func testWhenProfileSaved_andScansCompleted_andScanError_thenEventNotFired() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockEventsHandler.reset()
        mockQueueManager.startImmediateScanOperationsIfPermittedCompletionError = DataBrokerProtectionJobsErrorCollection(oneTimeError: NSError(domain: "test", code: 10))

        // When
        await sut.profileSaved()

        // Then
        XCTAssertFalse(mockEventsHandler.firstScanCompletedFired)
    }

    func testWhenProfileSaved_andScansCompleted_andHasMatches_thenEventFired() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockEventsHandler.reset()
        mockDataManager.shouldReturnHasMatches = true

        // When
        await sut.profileSaved()

        // Then
        XCTAssertTrue(mockEventsHandler.firstScanCompletedAndMatchesFoundFired)
    }

    func testWhenProfileSaved_andScansCompleted_andHasNoMatches_thenEventNotFired() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockEventsHandler.reset()
        mockDataManager.shouldReturnHasMatches = false

        // When
        await sut.profileSaved()

        // Then
        XCTAssertFalse(mockEventsHandler.firstScanCompletedAndMatchesFoundFired)
    }

    func testWhenAppLaunched_andUserIsNotFreemium_thenScheduledAllOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockAuthenticationManager.isUserAuthenticatedValue = true
        mockFreemiumDBPUserStateManager.didActivate = false

        var startScheduledScansCalled = false
        mockQueueManager.startScheduledAllOperationsIfPermittedCalledCompletion = {
            startScheduledScansCalled = true
        }

        // When
        await sut.appLaunched()

        // Then
        XCTAssertTrue(startScheduledScansCalled)
    }

    func testWhenAppLaunched_andUserIsFreemium_thenScheduledScanOperationsRun() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockFreemiumDBPUserStateManager.didActivate = true

        var startScheduledScansCalled = false
        mockQueueManager.startScheduledScanOperationsIfPermittedCalledCompletion = {
            startScheduledScansCalled = true
        }

        // When
        await sut.appLaunched()

        // Then
        XCTAssertTrue(startScheduledScansCalled)
    }

    func testWhenFirePixelsCalled_andUserIsAuthenticated_thenPixelsAreFired() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockAuthenticationManager.isUserAuthenticatedValue = true
        mockFreemiumDBPUserStateManager.didActivate = false

        // When
        sut.fireMonitoringPixels()

        // Then
        XCTAssertNotNil(mockSharedPixelsHandler.lastFiredEvent)
    }

    func testWhenFirePixelsCalled_andUserIsNotAuthenticated_thenPixelsAreNotFired() async throws {
        // Given
        sut = DataBrokerProtectionAgentManager(
            eventsHandler: mockEventsHandler,
            activityScheduler: mockActivityScheduler,
            ipcServer: mockIPCServer,
            queueManager: mockQueueManager,
            dataManager: mockDataManager,
            emailConfirmationDataService: mockEmailConfirmationDataService,
            jobDependencies: mockDependencies,
            sharedPixelsHandler: mockSharedPixelsHandler,
            pixelHandler: mockPixelHandler,
            agentStopper: mockAgentStopper,
            configurationManager: mockConfigurationManager,
            brokerUpdater: mockBrokerUpdater,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            authenticationManager: mockAuthenticationManager,
            freemiumDBPUserStateManager: mockFreemiumDBPUserStateManager)

        mockAuthenticationManager.isUserAuthenticatedValue = false
        mockFreemiumDBPUserStateManager.didActivate = false

        // When
        sut.fireMonitoringPixels()

        // Then
        XCTAssertNil(mockSharedPixelsHandler.lastFiredEvent)
    }

}

struct MockConfigurationFetcher: ConfigurationFetching {
    func fetch(_ configuration: Configuration, isDebug: Bool) async throws {
        return
    }

    func fetch(all configurations: [Configuration]) async throws {
        return
    }
}

struct MockConfigurationStore: ConfigurationStoring {
    func loadData(for configuration: Configuration) -> Data? {
        return nil
    }

    func loadEtag(for configuration: Configuration) -> String? {
        return nil
    }

    func loadEmbeddedEtag(for configuration: Configuration) -> String? {
        return nil
    }

    mutating func saveData(_ data: Data, for configuration: Configuration) throws {
        return
    }

    mutating func saveEtag(_ etag: String, for configuration: Configuration) throws {
        return
    }

    func fileUrl(for configuration: Configuration) -> URL {
        return URL(string: "file:///\(configuration.rawValue)")!
    }

}

final class MockConfigurationManager: DefaultConfigurationManager {
    override init(fetcher: ConfigurationFetching = MockConfigurationFetcher(),
                  store: ConfigurationStoring = MockConfigurationStore(),
                  defaults: KeyValueStoring = UserDefaults()) {
        super.init(fetcher: fetcher, store: store, defaults: defaults)
    }
}

final class MockEmailConfirmationDataService: EmailConfirmationDataServiceProvider {
    func getConfirmationLink(from email: String,
                             numberOfRetries: Int,
                             pollingInterval: TimeInterval,
                             attemptId: UUID,
                             shouldRunNextStep: @escaping () -> Bool) async throws -> URL {
        URL(string: "https://example.com")!
    }

    func getEmailAndOptionallySaveToDatabase(dataBrokerId: Int64,
                                             dataBrokerURL: String,
                                             profileQueryId: Int64,
                                             extractedProfileId: Int64,
                                             attemptId: UUID) async throws -> EmailData {
        EmailData(pattern: "", emailAddress: "hello@example.com")
    }

    func checkForEmailConfirmationData() async throws {
    }
}
