//
//  AppStoreCrashCollection.swift
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

import BrowserServicesKit
import Common
import Crashes
import CrashReportingShared
import FeatureFlags
import Foundation
import PrivacyConfig

extension CrashReportingFactory: AppStoreCrashReportingFactory {
    @available(macOS 12.0, *)
    public static func instantiate(internalUserDecider: InternalUserDecider,
                                   featureFlagger: FeatureFlagger,
                                   crashReportSender: CrashReportSending,
                                   crashSenderPixelEvents: EventMapping<CrashReportSenderError>?,
                                   fireCrashPixel: @escaping (_ parameters: [CrashReportPixelParameter: String]) -> Void,
                                   promptForConsent: @escaping (_ crashPayload: Data) async -> Bool) -> any CrashReporting {
        return AppStoreCrashCollection(internalUserDecider: internalUserDecider,
                                       featureFlagger: featureFlagger,
                                       crashReportSender: crashReportSender,
                                       fireCrashPixel: fireCrashPixel,
                                       promptForConsent: promptForConsent)
    }
}

@available(macOS 12.0, *)
public final class AppStoreCrashCollection: CrashReporting {

    private let crashReportSender: CrashReportSending
    private lazy var crashCollection = CrashCollection(crashReportSender: crashReportSender)
    private let internalUserDecider: InternalUserDecider
    private let featureFlagger: FeatureFlagger
    private let fireCrashPixel: (_ parameters: [CrashReportPixelParameter: String]) -> Void
    private let promptForConsent: (_ crashPayload: Data) async -> Bool

    public init(internalUserDecider: InternalUserDecider,
                featureFlagger: FeatureFlagger,
                crashReportSender: CrashReportSending,
                fireCrashPixel: @escaping (_ parameters: [CrashReportPixelParameter: String]) -> Void,
                promptForConsent: @escaping (_ crashPayload: Data) async -> Bool) {
        self.internalUserDecider = internalUserDecider
        self.featureFlagger = featureFlagger
        self.crashReportSender = crashReportSender
        self.fireCrashPixel = fireCrashPixel
        self.promptForConsent = promptForConsent
    }

    public func start() async {
        let isCallStackLimitingEnabled = featureFlagger.isFeatureOn(.crashCollectionLimitCallStackTreeDepth)
        let callStackDepthLimit: Int? = isCallStackLimitingEnabled ? 250 : nil

        crashCollection.startAttachingCrashLogMessages(callStackDepthLimit: callStackDepthLimit) { [weak self] pixelParameters, payloads, completion in
            guard let self else { return }

            pixelParameters.forEach { parameters in
                var updatedParameters = parameters
                updatedParameters[.appVersion] = CrashCollection.removeBuildNumber(from: updatedParameters[.appVersion])
                self.fireCrashPixel(updatedParameters)
            }

            guard let lastPayload = payloads.last else {
                return
            }

            if self.internalUserDecider.isInternalUser {
                completion()
            } else {
                Task { @MainActor in
                    if await self.promptForConsent(lastPayload) {
                        completion()
                    }
                }
            }
        }
    }
}
