//
//  CrashReporter.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Common
import Crashes
import Foundation
import PixelKit

final class CrashReporter {

    init(internalUserDecider: InternalUserDecider) {
        self.internalUserDecider = internalUserDecider
    }

    private let internalUserDecider: InternalUserDecider
    private let reader = CrashReportReader()
    private lazy var sender = CrashReportSender(platform: .macOS, pixelEvents: CrashReportSender.pixelEvents)
    private lazy var crcidManager = CRCIDManager()
    private lazy var promptPresenter = CrashReportPromptPresenter()

    @UserDefaultsWrapper(key: .lastCrashReportCheckDate, defaultValue: nil)
    private var lastCheckDate: Date?

    func checkForNewReports() async {
#if !DEBUG
        guard let lastCheckDate = lastCheckDate else {
            // Initial run
            self.lastCheckDate = Date()
            return
        }

        let crashReports = reader.getCrashReports(since: lastCheckDate)
        self.lastCheckDate = Date()

        guard let latest = crashReports.last else {
            // No new crash reports
            return
        }

        for crash in crashReports {
            let appIdentifier = CrashPixelAppIdentifier(crash.bundleID)
            if let appVersion = crash.appVersion {
                let parameters = [PixelKit.Parameters.appVersion: appVersion]
                PixelKit.fire(GeneralPixel.crash(appIdentifier: appIdentifier), frequency: .dailyAndStandard, withAdditionalParameters: parameters, includeAppVersionParameter: false)
            } else {
                PixelKit.fire(GeneralPixel.crash(appIdentifier: appIdentifier), frequency: .dailyAndStandard)
            }
        }

        if internalUserDecider.isInternalUser {
            await send(crashReports)
        } else if await promptPresenter.showPrompt(for: latest) == .allow {
            await send(crashReports)
        }
#endif
    }

    private func send(_ crashReports: [CrashReport]) async {
        for crashReport in crashReports {
            guard let contentData = crashReport.contentData else {
                assertionFailure("CrashReporter: Can't get the content of the crash report")
                continue
            }
            let result = await sender.send(contentData, crcid: crcidManager.crcid)
            crcidManager.handleCrashSenderResult(result: result.result, response: result.response)
        }
    }
}
