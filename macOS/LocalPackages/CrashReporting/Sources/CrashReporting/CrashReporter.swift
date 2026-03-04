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

import Common
import Crashes
import CrashReportingShared
import Foundation
import Persistence
import PrivacyConfig

extension CrashReportingFactory: SparkleCrashReportingFactory {
    public static func instantiate(internalUserDecider: InternalUserDecider,
                                   keyValueStore: any ThrowingKeyValueStoring,
                                   crashSenderPixelEvents: EventMapping<CrashReportSenderError>?,
                                   fireCrashPixel: @escaping (_ bundleID: String?, _ appVersion: String?, _ failedToReadCrashVersion: Bool) -> Void,
                                   fireFailedToReadContentsPixel: @escaping () -> Void,
                                   promptForConsent: @escaping (CrashReportPresenting) async -> Bool) -> any CrashReporting {
        CrashReporter(internalUserDecider: internalUserDecider,
                      keyValueStore: keyValueStore,
                      crashSenderPixelEvents: crashSenderPixelEvents,
                      fireCrashPixel: fireCrashPixel,
                      fireFailedToReadContentsPixel: fireFailedToReadContentsPixel,
                      promptForConsent: promptForConsent)
    }
}

public final class CrashReporter: CrashReporting {
    private let internalUserDecider: InternalUserDecider
    private let fireCrashPixel: (_ bundleID: String?, _ appVersion: String?, _ failedToReadCrashVersion: Bool) -> Void
    private let fireFailedToReadContentsPixel: () -> Void
    private let promptForConsent: (CrashReportPresenting) async -> Bool
    private let settings: any ThrowingKeyedStoring<CrashReportingSettings>

    private let reader = CrashReportReader()
    private let sender: CrashReportSender
    private let crcidManager = CRCIDManager()

    public init(internalUserDecider: InternalUserDecider,
                keyValueStore: any ThrowingKeyValueStoring,
                crashSenderPixelEvents: EventMapping<CrashReportSenderError>?,
                fireCrashPixel: @escaping (_ bundleID: String?, _ appVersion: String?, _ failedToReadCrashVersion: Bool) -> Void,
                fireFailedToReadContentsPixel: @escaping () -> Void,
                promptForConsent: @escaping (CrashReportPresenting) async -> Bool) {
        self.internalUserDecider = internalUserDecider
        self.settings = keyValueStore.throwingKeyedStoring()
        self.sender = CrashReportSender(platform: .macOS, pixelEvents: crashSenderPixelEvents)
        self.fireCrashPixel = fireCrashPixel
        self.fireFailedToReadContentsPixel = fireFailedToReadContentsPixel
        self.promptForConsent = promptForConsent
    }

    public func start() async {
        let lastCheckDate = try? settings.lastCrashReportCheckDate
        guard let lastCheckDate else {
            try? settings.set(Date(), for: \.lastCrashReportCheckDate)
            return
        }

        let crashReports = reader.getCrashReports(since: lastCheckDate)
        try? settings.set(Date(), for: \.lastCrashReportCheckDate)

        guard let latest = crashReports.last else {
            // No new crash reports
            return
        }

        for crash in crashReports {
            if let appVersion = crash.appVersion {
                fireCrashPixel(crash.bundleID, appVersion, /*failedToReadCrashVersion:*/ false)
            } else {
                fireCrashPixel(crash.bundleID, nil, /*failedToReadCrashVersion:*/ true)
            }
        }

        if internalUserDecider.isInternalUser {
            await send(crashReports)
            return
        } else if await promptForConsent(latest) {
            await send(crashReports)
        }
    }

    private func send(_ crashReports: [CrashReport]) async {
        for crashReport in crashReports {
            guard let contentData = crashReport.contentData else {
                assertionFailure("CrashReporter: Can't get the content of the crash report")
                fireFailedToReadContentsPixel()
                continue
            }
            let result = await sender.send(contentData, crcid: crcidManager.crcid)
            crcidManager.handleCrashSenderResult(result: result.result, response: result.response)
        }
    }

}
