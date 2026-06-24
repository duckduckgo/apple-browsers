//
//  UncleanExitRestartSourceResolver.swift
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

import AppUpdaterShared
import CrashReporting
import CrashReportingShared
import Foundation
import Persistence

protocol UncleanExitRestartSourceResolving {
    func captureSparklePendingUpdateSnapshot()
    func resolve(updateStatus: AppUpdateStatus) -> UncleanExitRestartSource
}

protocol CrashReportDetecting {
    func hasNewMainBrowserCrashReport() -> Bool
}

final class MainBrowserCrashReportDetector: CrashReportDetecting {

    private let settings: any ThrowingKeyedStoring<CrashReportingSettings>
    private let crashReportReader: CrashReportReader
    private let buildType: ApplicationBuildType
    private let mainBundleIdentifier: String?

    init(settings: any ThrowingKeyedStoring<CrashReportingSettings>,
         buildType: ApplicationBuildType,
         crashReportReader: CrashReportReader = CrashReportReader(),
         mainBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.settings = settings
        self.buildType = buildType
        self.crashReportReader = crashReportReader
        self.mainBundleIdentifier = mainBundleIdentifier
    }

    func hasNewMainBrowserCrashReport() -> Bool {
        guard buildType.isSparkleBuild, let mainBundleIdentifier else { return false }

        guard let lastCheckDate = try? settings.lastCrashReportCheckDate else {
            return false
        }

        return crashReportReader.hasNewCrashReport(forBundleIdentifier: mainBundleIdentifier, since: lastCheckDate)
    }
}

final class UncleanExitRestartSourceResolver: UncleanExitRestartSourceResolving {

    private let updateControllerSettings: any ThrowingKeyedStoring<UpdateControllerSettings>
    private let crashReportDetecting: CrashReportDetecting
    private let buildType: ApplicationBuildType
    private var sparklePendingUpdateSnapshot = false

    init(updateControllerSettings: any ThrowingKeyedStoring<UpdateControllerSettings>,
         crashReportDetecting: CrashReportDetecting,
         buildType: ApplicationBuildType) {
        self.updateControllerSettings = updateControllerSettings
        self.crashReportDetecting = crashReportDetecting
        self.buildType = buildType
    }

    func captureSparklePendingUpdateSnapshot() {
        guard buildType.isSparkleBuild else {
            sparklePendingUpdateSnapshot = false
            return
        }

        let hasSourceVersion = (try? updateControllerSettings.pendingUpdateSourceVersion) != nil
        let hasSourceBuild = (try? updateControllerSettings.pendingUpdateSourceBuild) != nil
        sparklePendingUpdateSnapshot = hasSourceVersion && hasSourceBuild
    }

    func resolve(updateStatus: AppUpdateStatus) -> UncleanExitRestartSource {
        if crashReportDetecting.hasNewMainBrowserCrashReport() {
            return .crash
        }

        if buildType.isSparkleBuild, sparklePendingUpdateSnapshot {
            return .appUpdate
        }

        if buildType.isAppStoreBuild, updateStatus == .updated || updateStatus == .downgraded {
            return .unknownWithAppUpdate
        }

        return .unknown
    }
}
