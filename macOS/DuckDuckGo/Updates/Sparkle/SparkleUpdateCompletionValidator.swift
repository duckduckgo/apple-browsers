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
import PixelKit
import Common

final class SparkleUpdateCompletionValidator {

    @UserDefaultsWrapper(key: .pendingUpdateSourceVersion, defaultValue: nil)
    private static var pendingUpdateSourceVersion: String?

    @UserDefaultsWrapper(key: .pendingUpdateSourceBuild, defaultValue: nil)
    private static var pendingUpdateSourceBuild: String?

    @UserDefaultsWrapper(key: .pendingUpdateExpectedVersion, defaultValue: nil)
    private static var pendingUpdateExpectedVersion: String?

    @UserDefaultsWrapper(key: .pendingUpdateExpectedBuild, defaultValue: nil)
    private static var pendingUpdateExpectedBuild: String?

    @UserDefaultsWrapper(key: .pendingUpdateInitiationType, defaultValue: nil)
    private static var pendingUpdateInitiationType: String?

    @UserDefaultsWrapper(key: .pendingUpdateConfiguration, defaultValue: nil)
    private static var pendingUpdateConfiguration: String?

    /// Store metadata when update is about to happen (before app restarts)
    static func storePendingUpdateMetadata(
        sourceVersion: String,
        sourceBuild: String,
        expectedVersion: String,
        expectedBuild: String,
        initiationType: String,
        updateConfiguration: String
    ) {
        pendingUpdateSourceVersion = sourceVersion
        pendingUpdateSourceBuild = sourceBuild
        pendingUpdateExpectedVersion = expectedVersion
        pendingUpdateExpectedBuild = expectedBuild
        pendingUpdateInitiationType = initiationType
        pendingUpdateConfiguration = updateConfiguration
    }

    /// Check if update completed successfully and fire pixel
    /// Called after ApplicationUpdateDetector.isApplicationUpdated()
    /// Always fires pixel for successful updates, using stored metadata when available
    static func validateExpectations(
        updateStatus: AppUpdateStatus,
        currentVersion: String,
        currentBuild: String
    ) {
        // Ensure metadata is always cleared, regardless of outcome
        defer {
            clearPendingUpdateMetadata()
        }

        // Load metadata with "unknown" fallback for non-Sparkle updates
        let sourceVersion = pendingUpdateSourceVersion ?? "unknown"
        let sourceBuild = pendingUpdateSourceBuild ?? "unknown"
        let expectedVersion = pendingUpdateExpectedVersion ?? "unknown"
        let expectedBuild = pendingUpdateExpectedBuild ?? "unknown"
        let initiationType = pendingUpdateInitiationType ?? "unknown"
        let updateConfiguration = pendingUpdateConfiguration ?? "unknown"

        // Determine if this was a Sparkle-initiated update
        let updatedBySparkle = pendingUpdateSourceVersion != nil &&
                                pendingUpdateSourceBuild != nil &&
                                pendingUpdateExpectedVersion != nil &&
                                pendingUpdateExpectedBuild != nil &&
                                pendingUpdateInitiationType != nil &&
                                pendingUpdateConfiguration != nil

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
                ))
            } else {
                // Unexpected - update detected outside Sparkle flow
                PixelKit.fire(UpdateFlowPixels.updateApplicationUnexpected(
                    targetVersion: currentVersion,
                    targetBuild: currentBuild,
                    osVersion: osVersionString
                ))
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
            ))
        }
    }

    /// Clear pending update metadata
    /// Internal for testing
    static func clearPendingUpdateMetadata() {
        pendingUpdateSourceVersion = nil
        pendingUpdateSourceBuild = nil
        pendingUpdateExpectedVersion = nil
        pendingUpdateExpectedBuild = nil
        pendingUpdateInitiationType = nil
        pendingUpdateConfiguration = nil
    }
}
