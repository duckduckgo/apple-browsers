//
//  SparkleUpdateWideEvent.swift
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

#if SPARKLE

import Common
import Foundation
import PixelKit
import PrivacyConfig
import os.log

/// Orchestrates Wide Event tracking for Sparkle update cycles.
///
/// This class manages the complete lifecycle of an update flow from initial check through
/// completion or cancellation, coordinating with `WideEventManager` to persist flow state
/// and timing measurements.
///
/// ## Scope and Responsibilities
///
/// - Manages the lifecycle of a single update flow from check through completion
/// - Coordinates timing measurements for each phase (check, download, extraction)
/// - Handles edge cases: overlapping flows, app termination, abandoned sessions
/// - Does NOT own the WideEventManager (injected dependency)
/// - Does NOT interact with Sparkle directly (receives updates from SparkleUpdateController)
///
/// ## Edge Cases
///
/// - **Overlapping flows**: When a new flow starts while an existing one is pending, the existing
///   flow is completed as "incomplete" to prevent orphaned flows in storage
/// - **App termination**: Active flows are cancelled with `appQuit` reason to distinguish from
///   user-initiated cancellations
/// - **Abandoned flows**: Flows from previous sessions found at app launch are marked "abandoned"
final class SparkleUpdateWideEvent {
    private let wideEventManager: WideEventManaging
    private let internalUserDecider: InternalUserDecider
    private var currentFlowID: String?
    var areAutomaticUpdatesEnabled: Bool

    @UserDefaultsWrapper(key: .lastSuccessfulUpdateDate, defaultValue: nil)
    static var lastSuccessfulUpdateDate: Date?

    init(wideEventManager: WideEventManaging,
         internalUserDecider: InternalUserDecider,
         areAutomaticUpdatesEnabled: Bool) {
        self.wideEventManager = wideEventManager
        self.internalUserDecider = internalUserDecider
        self.areAutomaticUpdatesEnabled = areAutomaticUpdatesEnabled
    }

    /// Starts tracking a new update flow.
    ///
    /// If an existing flow is in progress, it will be completed as "incomplete" before starting
    /// the new flow. This prevents accumulation of orphaned flows in WideEventManager's storage.
    ///
    /// - Parameter initiationType: How the update was initiated (automatic background check or manual user action)
    ///
    /// - Note: Edge case handled - User triggers manual check while automatic check is in progress,
    ///   or automatic check starts while previous manual check hasn't completed.
    func startFlow(initiationType: UpdateWideEventData.InitiationType) {
        // Complete any existing pending flow
        if let existingFlowID = currentFlowID,
           var existingFlow = wideEventManager.getFlowData(UpdateWideEventData.self, globalID: existingFlowID) {
            existingFlow.totalDuration?.complete()
            existingFlow.downloadDuration?.complete()
            existingFlow.extractionDuration?.complete()
            wideEventManager.completeFlow(existingFlow, status: .unknown(reason: "incomplete")) { _, _ in }
            Logger.updates.log("Completed previous WideEvent flow as incomplete")
        }

        // Start new flow
        let globalID = UUID().uuidString
        currentFlowID = globalID

        var eventData = UpdateWideEventData(
            fromVersion: AppVersion.shared.versionNumber,
            fromBuild: AppVersion.shared.buildNumber,
            initiationType: initiationType,
            updateConfiguration: areAutomaticUpdatesEnabled ? .automatic : .manual,
            isInternalUser: internalUserDecider.isInternalUser,
            contextData: WideEventContextData(name: "sparkle_update"),
            appData: WideEventAppData(),
            globalData: WideEventGlobalData(id: globalID)
        )
        eventData.totalDuration = .startingNow()
        eventData.updateCheckDuration = .startingNow()
        eventData.lastKnownStep = .updateCheckStarted

        wideEventManager.startFlow(eventData)
    }

    func getCurrentFlowData() -> UpdateWideEventData? {
        guard let globalID = currentFlowID else { return nil }
        return wideEventManager.getFlowData(UpdateWideEventData.self, globalID: globalID)
    }

    func didStartUpdateCheck() {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.lastKnownStep = .updateCheckStarted
        }
    }

    func didFindUpdate(version: String, build: String, isCritical: Bool) {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.toVersion = version
            data.toBuild = build
            data.updateType = isCritical ? .critical : .regular
            data.updateCheckDuration?.complete()
            data.lastKnownStep = .updateFound

            // Add time since last update if available (bucketed for privacy)
            if let lastUpdateDate = Self.lastSuccessfulUpdateDate {
                data.timeSinceLastUpdateBucket = UpdateWideEventData.TimeSinceUpdateBucket(from: lastUpdateDate)
            }
        }
    }

    func didFindNoUpdate() {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.updateCheckDuration?.complete()
            data.lastKnownStep = .noUpdateFound
        }
        Logger.updates.debug("Update WideEvent: no update found, check phase complete")
    }

    func didStartDownload() {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.downloadDuration = .startingNow()
            data.lastKnownStep = .downloadStarted
        }
    }

    func didCompleteDownload() {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.downloadDuration?.complete()
            data.lastKnownStep = .downloadCompleted
        }
    }

    func didStartExtraction() {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.extractionDuration = .startingNow()
            data.lastKnownStep = .extractionStarted
        }
    }

    func didCompleteExtraction() {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.extractionDuration?.complete()
            data.lastKnownStep = .extractionCompleted
        }
    }

    func didInitiateRestart() {
        guard let globalID = currentFlowID else { return }
        wideEventManager.updateFlow(globalID: globalID) { (data: inout UpdateWideEventData) in
            data.lastKnownStep = .restartingToUpdate
        }
    }

    /// Completes the current flow with final status.
    ///
    /// Completes all active timing measurements and adds disk space information on failures
    /// to help diagnose whether insufficient disk space caused the failure.
    ///
    /// - Parameters:
    ///   - status: The final status of the update flow (success, failure, cancelled, unknown)
    ///   - error: Optional error that caused the failure
    func completeFlow(status: WideEventStatus, error: Error? = nil) {
        guard let globalID = currentFlowID,
              let flowData = wideEventManager.getFlowData(UpdateWideEventData.self, globalID: globalID) else {
            return
        }
        defer { currentFlowID = nil }

        var data = flowData
        data.totalDuration?.complete()
        data.downloadDuration?.complete()
        data.extractionDuration?.complete()

        if let error = error {
            data.errorData = WideEventErrorData(error: error)
        }

        // Add disk space on failure
        if case .failure = status {
            data.diskSpaceRemainingBytes = UpdateWideEventData.getAvailableDiskSpace()
        }

        wideEventManager.completeFlow(data, status: status) { success, error in
            if success {
                Logger.updates.log("Update WideEvent completed successfully with status: \(status.description)")
            } else {
                Logger.updates.error("Update WideEvent failed to send: \(String(describing: error))")
            }
        }
    }

    /// Cancels the current flow with a specific reason.
    ///
    /// Completes all active timing measurements and records the cancellation reason for analytics.
    ///
    /// - Parameter reason: Why the flow was cancelled (e.g., user dismissed, settings changed, app quit)
    func cancelFlow(reason: UpdateWideEventData.CancellationReason) {
        guard let globalID = currentFlowID,
              let flowData = wideEventManager.getFlowData(UpdateWideEventData.self, globalID: globalID) else {
            return
        }
        defer { currentFlowID = nil }

        let data = flowData
        data.cancellationReason = reason
        data.totalDuration?.complete()
        data.downloadDuration?.complete()
        data.extractionDuration?.complete()

        wideEventManager.completeFlow(data, status: .cancelled) { success, error in
            if success {
                Logger.updates.log("Update WideEvent cancelled with reason: \(reason.rawValue)")
            } else {
                Logger.updates.error("Update WideEvent cancellation failed to send: \(String(describing: error))")
            }
        }
    }

    /// Handles app termination for update tracking.
    ///
    /// Checks the flow's last known step to determine the correct completion status:
    /// - `.restartingToUpdate` → success (user clicked "Restart to Update")
    /// - `.extractionCompleted` → success (update ready, will install on quit)
    /// - Anything else → cancellation (user quit during active check/download)
    func handleAppTermination() {
        guard let globalID = currentFlowID,
              let flowData = wideEventManager.getFlowData(UpdateWideEventData.self, globalID: globalID) else { return }

        switch flowData.lastKnownStep {
        case .restartingToUpdate:
            completeFlow(status: .success(reason: UpdateWideEventData.SuccessReason.restartingToUpdate.rawValue))
        case .extractionCompleted:
            completeFlow(status: .success(reason: UpdateWideEventData.SuccessReason.installingOnQuit.rawValue))
        default:
            cancelFlow(reason: .appQuit)
        }
    }

}

// MARK: - Cleanup

extension SparkleUpdateWideEvent {
    /// Cleans up abandoned flows from previous sessions.
    ///
    /// Any pending update flows found at app launch are from previous sessions that were
    /// interrupted (app crashed, force quit, or system shutdown during update). These are
    /// marked as "abandoned" to help measure update reliability across sessions.
    ///
    /// This method is synchronous and uses the callback-based completeFlow to avoid
    /// async coordination issues during initialization.
    func cleanupAbandonedFlows() {
        let pending: [UpdateWideEventData] = wideEventManager.getAllFlowData(UpdateWideEventData.self)

        // Any pending update pixels at app startup are considered abandoned,
        // since they represent flows from a previous session that were interrupted.
        for data in pending {
            wideEventManager.completeFlow(data, status: .unknown(reason: "abandoned")) { _, _ in }
        }
    }
}

#endif
