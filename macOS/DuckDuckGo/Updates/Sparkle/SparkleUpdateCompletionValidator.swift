//
//  SparkleUpdateCompletionValidator.swift
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

import Foundation
import Persistence
import PixelKit
import Common

final class SparkleUpdateCompletionValidator {
    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings>

    init(settings: any ThrowingKeyedStoring<UpdateControllerSettings>) {
        self.settings = settings
    }

    /// Store metadata when update is about to happen (before app restarts)
    func storePendingUpdateMetadata(
        sourceVersion: String,
        sourceBuild: String,
        expectedVersion: String,
        expectedBuild: String,
        initiationType: String,
        updateConfiguration: String
    ) {
        try? settings.set(sourceVersion, for: \.pendingUpdateSourceVersion)
        try? settings.set(sourceBuild, for: \.pendingUpdateSourceBuild)
        try? settings.set(expectedVersion, for: \.pendingUpdateExpectedVersion)
        try? settings.set(expectedBuild, for: \.pendingUpdateExpectedBuild)
        try? settings.set(initiationType, for: \.pendingUpdateInitiationType)
        try? settings.set(updateConfiguration, for: \.pendingUpdateConfiguration)
    }

    /// Check if update completed successfully and fire pixel
    /// Called after ApplicationUpdateDetector.isApplicationUpdated()
    /// Always fires pixel for successful updates, using stored metadata when available
    func validateExpectations(
        updateStatus: AppUpdateStatus,
        currentVersion: String,
        currentBuild: String
    ) {
        // Ensure metadata is always cleared, regardless of outcome
        defer {
            clearPendingUpdateMetadata()
        }

        // Load metadata with "unknown" fallback for non-Sparkle updates
        let sourceVersion = (try? settings.pendingUpdateSourceVersion) ?? "unknown"
        let sourceBuild = (try? settings.pendingUpdateSourceBuild) ?? "unknown"
        let expectedVersion = (try? settings.pendingUpdateExpectedVersion) ?? "unknown"
        let expectedBuild = (try? settings.pendingUpdateExpectedBuild) ?? "unknown"
        let initiationType = (try? settings.pendingUpdateInitiationType) ?? "unknown"
        let updateConfiguration = (try? settings.pendingUpdateConfiguration) ?? "unknown"

        // Determine if this was a Sparkle-initiated update
        let updatedBySparkle = (try? settings.pendingUpdateSourceVersion) != nil &&
                                (try? settings.pendingUpdateSourceBuild) != nil &&
                                (try? settings.pendingUpdateExpectedVersion) != nil &&
                                (try? settings.pendingUpdateExpectedBuild) != nil &&
                                (try? settings.pendingUpdateInitiationType) != nil &&
                                (try? settings.pendingUpdateConfiguration) != nil

        // Get OS version for pixels
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Fire appropriate pixel based on update status
        switch updateStatus {
        case .updated:
            // Fire different pixels based on whether update was Sparkle-initiated
            if updatedBySparkle {
                // Success - Sparkle-initiated update completed
                PixelKit.fire(UpdateFlowPixels.updateApplicationSuccess(
                    sourceVersion: sourceVersion,
                    sourceBuild: sourceBuild,
                    targetVersion: currentVersion,
                    targetBuild: currentBuild,
                    initiationType: initiationType,
                    updateConfiguration: updateConfiguration,
                    osVersion: osVersionString
                ), frequency: .dailyAndCount)
            } else {
                // Unexpected - update detected outside Sparkle flow
                PixelKit.fire(UpdateFlowPixels.updateApplicationUnexpected(
                    targetVersion: currentVersion,
                    targetBuild: currentBuild,
                    osVersion: osVersionString
                ), frequency: .dailyAndCount)
            }

        default:
            // Only fire failure pixel if we expected an update
            guard updatedBySparkle else { return }

            let failureStatus = updateStatus == .downgraded ? "downgraded" : "noChange"

            PixelKit.fire(UpdateFlowPixels.updateApplicationFailure(
                sourceVersion: sourceVersion,
                sourceBuild: sourceBuild,
                expectedVersion: expectedVersion,
                expectedBuild: expectedBuild,
                actualVersion: currentVersion,
                actualBuild: currentBuild,
                failureStatus: failureStatus,
                initiationType: initiationType,
                updateConfiguration: updateConfiguration,
                osVersion: osVersionString
            ), frequency: .dailyAndCount)
        }
    }

    /// Clear pending update metadata
    /// Internal for testing
    func clearPendingUpdateMetadata() {
        try? settings.set(nil, for: \.pendingUpdateSourceVersion)
        try? settings.set(nil, for: \.pendingUpdateSourceBuild)
        try? settings.set(nil, for: \.pendingUpdateExpectedVersion)
        try? settings.set(nil, for: \.pendingUpdateExpectedBuild)
        try? settings.set(nil, for: \.pendingUpdateInitiationType)
        try? settings.set(nil, for: \.pendingUpdateConfiguration)
    }
}
