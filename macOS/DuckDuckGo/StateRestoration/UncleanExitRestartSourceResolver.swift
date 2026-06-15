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

    private let keyValueStore: any ThrowingKeyValueStoring
    private let crashReportReader: CrashReportReader
    private let mainBundleIdentifier: String?

    init(keyValueStore: any ThrowingKeyValueStoring,
         crashReportReader: CrashReportReader = CrashReportReader(),
         mainBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.keyValueStore = keyValueStore
        self.crashReportReader = crashReportReader
        self.mainBundleIdentifier = mainBundleIdentifier
    }

    func hasNewMainBrowserCrashReport() -> Bool {
        guard let mainBundleIdentifier else { return false }

        let settings = keyValueStore.throwingKeyedStoring() as any ThrowingKeyedStoring<CrashReportingSettings>
        guard let lastCheckDate = try? settings.lastCrashReportCheckDate else {
            return false
        }

        return crashReportReader.hasNewCrashReport(forBundleIdentifier: mainBundleIdentifier, since: lastCheckDate)
    }
}

final class UncleanExitRestartSourceResolver: UncleanExitRestartSourceResolving {

    private let keyValueStore: any ThrowingKeyValueStoring
    private let crashReportDetecting: CrashReportDetecting
    private let buildType: ApplicationBuildType
    private var sparklePendingUpdateSnapshot = false

    init(keyValueStore: any ThrowingKeyValueStoring,
         crashReportDetecting: CrashReportDetecting,
         buildType: ApplicationBuildType) {
        self.keyValueStore = keyValueStore
        self.crashReportDetecting = crashReportDetecting
        self.buildType = buildType
    }

    func captureSparklePendingUpdateSnapshot() {
        guard buildType.isSparkleBuild else {
            sparklePendingUpdateSnapshot = false
            return
        }

        let settings = keyValueStore.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        let hasSourceVersion = (try? settings.pendingUpdateSourceVersion) != nil
        let hasSourceBuild = (try? settings.pendingUpdateSourceBuild) != nil
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
            return .appUpdate
        }

        return .unknown
    }
}
