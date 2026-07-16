//
//  DataBrokerProtectionIOSManagerAuthGateTests.swift
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
import Common
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtection_iOS

@MainActor
final class DataBrokerProtectionIOSManagerAuthGateTests: XCTestCase {

    // MARK: - validateRunPrerequisites

    func testValidatePrerequisites_authenticatedWithEntitlement_returnsTrue() async {
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = true
        dependencies.authenticationManager.hasValidEntitlementValue = true

        let result = await sut.validateRunPrerequisites()

        XCTAssertTrue(result)
    }

    func testValidatePrerequisites_unauthenticatedNotActivated_returnsFalse() async {
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = false

        let result = await sut.validateRunPrerequisites()

        XCTAssertFalse(result)
    }

    func testValidatePrerequisites_unauthenticatedButActivated_returnsTrue() async {
        let featureFlagger = MockDBPFeatureFlagger(isFreemiumPIREnabled: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        let result = await sut.validateRunPrerequisites()

        XCTAssertTrue(result)
    }

    func testValidatePrerequisites_unauthenticatedActivatedButFlagOff_returnsFalse() async {
        let featureFlagger = MockDBPFeatureFlagger(isFreemiumPIREnabled: false)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        let result = await sut.validateRunPrerequisites()

        XCTAssertFalse(result)
    }

    func testValidatePrerequisites_noProfile_returnsFalse() async {
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.profile = nil
        dependencies.freemiumDBPUserStateManager.didActivate = true

        let result = await sut.validateRunPrerequisites()

        XCTAssertFalse(result)
    }

    func testValidatePrerequisitesUsingCachedProfileState_authenticatedWithEntitlementAndCachedProfile_returnsTrueWhenDatabaseProfileIsMissing() async {
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.profile = nil
        dependencies.authenticationManager.isUserAuthenticatedValue = true
        dependencies.authenticationManager.hasValidEntitlementValue = true

        let result = await sut.validateRunPrerequisites(usingCachedProfileState: .hasProfile)

        XCTAssertTrue(result)
    }

    func testValidatePrerequisitesUsingCachedProfileState_noProfile_returnsFalse() async {
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = true
        dependencies.authenticationManager.hasValidEntitlementValue = true

        let result = await sut.validateRunPrerequisites(usingCachedProfileState: .noProfile)

        XCTAssertFalse(result)
    }

    func testValidatePrerequisitesUsingCachedProfileState_unauthenticatedActivatedButFreemiumFlagOff_returnsFalse() async {
        let featureFlagger = MockDBPFeatureFlagger(isFreemiumPIREnabled: false)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = nil
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        let result = await sut.validateRunPrerequisites(usingCachedProfileState: .hasProfile)

        XCTAssertFalse(result)
    }

    // MARK: - appDidBecomeActive

    func testAppDidBecomeActive_authenticatedWithProfile_startsScanOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = true

        await sut.appDidBecomeActive()

        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testAppDidBecomeActive_unauthenticatedNotActivated_doesNotStartOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = false

        await sut.appDidBecomeActive()

        XCTAssertFalse(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    func testAppDidBecomeActive_unauthenticatedButActivated_startsScanOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: true,
                                                    isFreemiumPIREnabled: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        await sut.appDidBecomeActive()

        XCTAssertTrue(dependencies.queueManager.didCallStartImmediateScanOperationsIfPermitted)
    }

    // MARK: - handleBGProcessingTask routing

    func testHandleBGProcessingTask_authenticated_startsAllOperations() async {
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = true
        dependencies.authenticationManager.hasValidEntitlementValue = true

        let mockTask = MockBGTask()
        sut.handleBGProcessingTask(task: mockTask)

        // Wait for the async Task inside handleBGProcessingTask to execute
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertTrue(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledScanOperationsIfPermitted)
    }

    func testHandleBGProcessingTask_freemiumActivated_startsScanOnlyOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isFreemiumPIREnabled: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        let mockTask = MockBGTask()
        sut.handleBGProcessingTask(task: mockTask)

        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(dependencies.queueManager.didCallStartScheduledScanOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
    }

    func testHandleBGProcessingTask_freemiumActivatedWithinBackgroundScanWindow_startsScanOnlyOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isFreemiumPIREnabled: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true
        dependencies.freemiumDBPUserStateManager.firstProfileSavedTimestamp = Date()
            .addingTimeInterval(-.days(6))

        let mockTask = MockBGTask()
        sut.handleBGProcessingTask(task: mockTask)

        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(dependencies.queueManager.didCallStartScheduledScanOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
    }

    func testHandleBGProcessingTask_freemiumActivatedAfterBackgroundScanWindow_doesNotStartOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isFreemiumPIREnabled: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true
        dependencies.freemiumDBPUserStateManager.firstProfileSavedTimestamp = Date()
            .addingTimeInterval(-.days(8))

        let mockTask = MockBGTask()
        sut.handleBGProcessingTask(task: mockTask)

        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledScanOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
        XCTAssertEqual(mockTask.completedSuccess, true)

        let backgroundTaskEvents = dependencies.database.backgroundTaskEventsToReturn
        XCTAssertEqual(backgroundTaskEvents.map(\.eventType), [.started, .completed])
        XCTAssertEqual(backgroundTaskEvents.first?.sessionId, backgroundTaskEvents.last?.sessionId)
        XCTAssertNotNil(backgroundTaskEvents.last?.metadata)
    }

    // MARK: - dashboardDidOpen routing

    func testDashboardDidOpen_authenticated_startsAllOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: false)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = true

        // Seed currentRunIsFreeScan by triggering appDidBecomeActive first
        // (mirrors real usage: app foregrounds → user navigates to dashboard)
        await sut.appDidBecomeActive()
        dependencies.queueManager.reset()  // clear calls from appDidBecomeActive

        sut.dashboardDidOpen()

        XCTAssertTrue(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
    }

    func testDashboardDidOpen_freemium_startsScanOnlyOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: false,
                                                    isFreemiumPIREnabled: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        // Seed currentRunIsFreeScan via appDidBecomeActive (mirrors real usage)
        await sut.appDidBecomeActive()
        dependencies.queueManager.reset()

        sut.dashboardDidOpen()

        XCTAssertTrue(dependencies.queueManager.didCallStartScheduledScanOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
    }

    // MARK: - makeContinuedProcessingOptOutPlan

    func testMakeContinuedProcessingOptOutPlan_authenticated_returnsRealPlan() async throws {
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager()
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = true
        dependencies.authenticationManager.hasValidEntitlementValue = true

        // Seed currentRunIsFreeScan = false (authenticated)
        await sut.appDidBecomeActive()

        // Set up opt-out data so the plan would be non-empty
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate, brokerId: 1, profileQueryId: 1, preferredRunDate: .now)]
            )
        ]

        let plan = try sut.makeContinuedProcessingOptOutPlan()

        XCTAssertGreaterThan(plan.optOutCount, 0)
    }

    func testDashboardDidOpen_freemiumFlagOff_startsAllOperations() async {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: false,
                                                    isFreemiumPIREnabled: false)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        // Seed currentRunIsFreeScan = true via appDidBecomeActive
        // (flag is off, so appDidBecomeActive returns early, but currentRunIsFreeScan is already set)
        await sut.appDidBecomeActive()
        dependencies.queueManager.reset()

        sut.dashboardDidOpen()

        // With flag off, should NOT route to scan-only even though currentRunIsFreeScan is true
        XCTAssertTrue(dependencies.queueManager.didCallStartScheduledAllOperationsIfPermitted)
        XCTAssertFalse(dependencies.queueManager.didCallStartScheduledScanOperationsIfPermitted)
    }

    func testMakeContinuedProcessingOptOutPlan_freemiumFlagOff_returnsRealPlan() async throws {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: false,
                                                    isFreemiumPIREnabled: false)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        // Seed currentRunIsFreeScan = true
        await sut.appDidBecomeActive()

        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate, brokerId: 1, profileQueryId: 1, preferredRunDate: .now)]
            )
        ]

        let plan = try sut.makeContinuedProcessingOptOutPlan()

        // With flag off, should return real plan even though currentRunIsFreeScan is true
        XCTAssertGreaterThan(plan.optOutCount, 0)
    }

    func testMakeContinuedProcessingOptOutPlan_freemium_returnsEmptyPlan() async throws {
        let featureFlagger = MockDBPFeatureFlagger(isForegroundRunningOnAppActiveFeatureOn: false,
                                                    isFreemiumPIREnabled: true)
        let (sut, dependencies) = DBPContinuedProcessingTestUtils.makeTestIOSManager(featureFlagger: featureFlagger)
        dependencies.database.profile = DBPContinuedProcessingTestUtils.makeProfile()
        dependencies.authenticationManager.isUserAuthenticatedValue = false
        dependencies.freemiumDBPUserStateManager.didActivate = true

        // Seed currentRunIsFreeScan = true (free user)
        await sut.appDidBecomeActive()

        // Set up opt-out data — should be ignored for free users
        dependencies.database.brokerProfileQueryDataToReturn = [
            DBPContinuedProcessingTestUtils.makeBrokerProfileQueryData(
                brokerId: 1,
                profileQueryId: 1,
                optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate, brokerId: 1, profileQueryId: 1, preferredRunDate: .now)]
            )
        ]

        let plan = try sut.makeContinuedProcessingOptOutPlan()

        XCTAssertEqual(plan.optOutCount, 0)
    }
}
