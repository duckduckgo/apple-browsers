//
//  SparkleDebugHelper.swift
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

import AppKit
import Common

/// Helper for testing Sparkle update pixels via debug menu
final class SparkleDebugHelper {

    /// Simulates a Sparkle-initiated update that completed successfully
    static func configureExpectedUpdateSuccess() {
        let currentVersion = AppVersion.shared.versionNumber
        let currentBuild = AppVersion.shared.buildNumber

        setPreviousVersion("1.0", build: "1")
        setPendingUpdateMetadata(
            sourceVersion: "1.0",
            sourceBuild: "1",
            expectedVersion: currentVersion,
            expectedBuild: currentBuild
        )

        showAlertAndQuit(
            title: "Update Success Test Configured",
            message: "The app will now quit. When you relaunch, the update success pixel will fire.\n\nExpected: Update from v1.0 (build 1) to \(currentVersion) (build \(currentBuild))"
        )
    }

    /// Simulates a Sparkle-initiated update that failed to complete
    static func configureUpdateFailure() {
        let currentVersion = AppVersion.shared.versionNumber
        let currentBuild = AppVersion.shared.buildNumber

        setPreviousVersion(currentVersion, build: currentBuild)
        setPendingUpdateMetadata(
            sourceVersion: "1.0",
            sourceBuild: "1",
            expectedVersion: "99.0",
            expectedBuild: "999999"
        )

        showAlertAndQuit(
            title: "Update Failure Test Configured",
            message: "The app will now quit. When you relaunch, the update failure pixel will fire.\n\nExpected: Update failure (expected v99.0, got \(currentVersion))"
        )
    }

    /// Simulates a manual/unplanned update (not initiated by Sparkle)
    static func configureUnexpectedUpdateSuccess() {
        let currentVersion = AppVersion.shared.versionNumber
        let currentBuild = AppVersion.shared.buildNumber

        setPreviousVersion("1.0", build: "1")
        // DO NOT set pending validator metadata - this simulates a manual/unplanned update

        showAlertAndQuit(
            title: "Unexpected Update Success Test Configured",
            message: "The app will now quit. When you relaunch, the update success pixel will fire with updatedBySparkle=false.\n\nExpected: Update from v1.0 (build 1) to \(currentVersion) (build \(currentBuild))\nType: Manual/unplanned (no Sparkle metadata)"
        )
    }

    // MARK: - Private Helpers

    private static func setPreviousVersion(_ version: String, build: String) {
        UserDefaults.standard.set(version, forKey: "previous.app.version")
        UserDefaults.standard.set(build, forKey: "previous.build")
    }

    private static func setPendingUpdateMetadata(
        sourceVersion: String,
        sourceBuild: String,
        expectedVersion: String,
        expectedBuild: String
    ) {
        UserDefaults.standard.set(sourceVersion, forKey: "pending.update.source.version")
        UserDefaults.standard.set(sourceBuild, forKey: "pending.update.source.build")
        UserDefaults.standard.set(expectedVersion, forKey: "pending.update.expected.version")
        UserDefaults.standard.set(expectedBuild, forKey: "pending.update.expected.build")
        UserDefaults.standard.set("manual", forKey: "pending.update.initiation.type")
        UserDefaults.standard.set("manual", forKey: "pending.update.configuration")
    }

    private static func showAlertAndQuit(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit Now")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}
