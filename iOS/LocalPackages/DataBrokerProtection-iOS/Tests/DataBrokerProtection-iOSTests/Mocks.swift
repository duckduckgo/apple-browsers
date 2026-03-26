//
//  Mocks.swift
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
import SwiftUI
@testable import DataBrokerProtection_iOS
import DataBrokerProtectionCore

final class MockDataBrokerProtectionUserNotificationService: DataBrokerProtectionUserNotificationService {
    func requestNotificationPermission() {}
    func sendFirstScanCompletedNotification() {}
    func sendFirstRemovedNotificationIfPossible() {}
    func sendAllInfoRemovedNotificationIfPossible() {}
    func scheduleCheckInNotificationIfPossible() {}
    func sendGoToMarketFirstScanNotificationIfPossible() async {}
    func resetFirstScanCompletedNotificationState() {}
    func resetAllNotificationStatesForDebug() {}
}

final class MockDataBrokerProtectionSubscriptionManaging: DataBrokerProtectionSubscriptionManaging {
    func accessToken() async -> String? { nil }
    func hasValidEntitlement() async throws -> Bool { false }
    func isUserEligibleForFreeTrial() -> Bool { false }
}

final class MockContinuedProcessingCoordinator: DBPContinuedProcessingCoordinating {
    var didCallStartInitialRun = false
    var _hasAttachedTask = false
    var startInitialRunError: Error?
    var onEvent: ((DBPContinuedProcessingEvent) -> Void)?
    private(set) var receivedScanPlan: DBPContinuedProcessingPlans.InitialScanPlan?

    func hasAttachedTask() async -> Bool {
        _hasAttachedTask
    }

    func startInitialRun(scanPlan: DBPContinuedProcessingPlans.InitialScanPlan) async throws {
        didCallStartInitialRun = true
        receivedScanPlan = scanPlan

        if let startInitialRunError {
            throw startInitialRunError
        }
    }

    func didEmit(event: DBPContinuedProcessingEvent) async {
        onEvent?(event)
    }

    func reset() {
        didCallStartInitialRun = false
        _hasAttachedTask = false
        startInitialRunError = nil
        receivedScanPlan = nil
        onEvent = nil
    }
}

final class MockContinuedProcessingCoordinatorDelegate: DBPContinuedProcessingDelegate {
    var didCallCoordinatorDidStartRun = false
    var didCallCoordinatorDidFinishRun = false
    var didCallCoordinatorIsReadyForScanOperations = false
    var didCallCoordinatorIsReadyForOptOutOperations = false
    var didCallCoordinatorDidRequestStopOperations = false
    var optOutPlanToReturn: DBPContinuedProcessingPlans.OptOutPlan?
    var optOutPlanError: Error?
    var scanJobTimeoutToReturn: TimeInterval = .minutes(3)

    func coordinatorDidStartRun() {
        didCallCoordinatorDidStartRun = true
    }

    func coordinatorDidFinishRun() {
        didCallCoordinatorDidFinishRun = true
    }

    func coordinatorIsReadyForScanOperations() async {
        didCallCoordinatorIsReadyForScanOperations = true
    }

    func coordinatorIsReadyForOptOutOperations() {
        didCallCoordinatorIsReadyForOptOutOperations = true
    }

    func coordinatorDidRequestStopOperations() {
        didCallCoordinatorDidRequestStopOperations = true
    }

    func continuedProcessingScanJobTimeout() -> TimeInterval {
        scanJobTimeoutToReturn
    }

    func makeContinuedProcessingOptOutPlan() throws -> DBPContinuedProcessingPlans.OptOutPlan {
        if let optOutPlanError { throw optOutPlanError }
        return optOutPlanToReturn ?? DBPContinuedProcessingPlans.OptOutPlan(optOutJobIDs: [])
    }

    func reset() {
        didCallCoordinatorDidStartRun = false
        didCallCoordinatorDidFinishRun = false
        didCallCoordinatorIsReadyForScanOperations = false
        didCallCoordinatorIsReadyForOptOutOperations = false
        didCallCoordinatorDidRequestStopOperations = false
        optOutPlanToReturn = nil
        optOutPlanError = nil
    }
}
