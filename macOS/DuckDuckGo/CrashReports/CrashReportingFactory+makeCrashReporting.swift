//
//  CrashReportingFactory+makeCrashReporting.swift
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

import Crashes
import CrashReportingShared
import FeatureFlags
import Persistence
import PixelKit
import PrivacyConfig

extension CrashReportingFactory {

    private static func makeCrashReportSender(buildType: any ApplicationBuildType,
                                              platform: CrashCollectionPlatform) -> CrashReportSending {
        if buildType.isDebugBuild || buildType.isReviewBuild {
            return DebugCrashReportSender(platform: platform, pixelEvents: nil)
        }
        return CrashReportSender(platform: platform, pixelEvents: CrashReportSender.pixelEvents)
    }

    static func makeCrashReporting(internalUserDecider: InternalUserDecider,
                                   featureFlagger: FeatureFlagger,
                                   keyValueStore: any ThrowingKeyValueStoring,
                                   buildType: any ApplicationBuildType = StandardApplicationBuildType()) -> any CrashReporting {
        if buildType.isAppStoreBuild {
            guard #available(macOS 12.0, *) else {
                fatalError("App Store crash reporting requires macOS 12.0 or newer")
            }

            // `AppStoreCrashReportingFactory` conformance is implemented in
            // `LocalPackages/CrashReporting/Sources/AppStoreCrashCollection/AppStoreCrashCollection.swift`.
            // App Store build is linked against the `AppStoreCrashCollection` lib, providing this conformance.
            guard let appStoreFactory = self as? any AppStoreCrashReportingFactory.Type else {
                fatalError("Failed to instantiate app store crash reporting")
            }

            let sender = makeCrashReportSender(buildType: buildType, platform: .macOSAppStore)

            return appStoreFactory.instantiate(
                internalUserDecider: internalUserDecider,
                featureFlagger: featureFlagger,
                crashReportSender: sender,
                crashSenderPixelEvents: CrashReportSender.pixelEvents,
                fireCrashPixel: { parameters in
                    var updatedParameters = parameters
                    let appIdentifier = CrashPixelAppIdentifier(updatedParameters.removeValue(forKey: .bundle))
                    PixelKit.fire(GeneralPixel.crash(appIdentifier: appIdentifier),
                                  frequency: .dailyAndStandard,
                                  withAdditionalParameters: Dictionary(uniqueKeysWithValues: updatedParameters.map { ($0.key.rawValue, $0.value) }),
                                  includeAppVersionParameter: false)
                },
                promptForConsent: { payload in
                    await CrashReportPromptPresenter().showPrompt(for: CrashDataPayload(data: payload)) == .allow
                }
            )

        } else if buildType.isSparkleBuild {
            // `SparkleCrashReportingFactory` conformance is implemented in
            // `LocalPackages/CrashReporting/Sources/CrashReporting/CrashReporter.swift`.
            // Sparkle build is linked against the `CrashReporting` lib, providing this conformance.
            guard let crashReportingFactory = self as? any SparkleCrashReportingFactory.Type else {
                fatalError("Failed to instantiate sparkle crash reporting")
            }

            let sender = makeCrashReportSender(buildType: buildType, platform: .macOS)

            return crashReportingFactory.instantiate(
                internalUserDecider: internalUserDecider,
                keyValueStore: keyValueStore,
                crashReportSender: sender,
                crashSenderPixelEvents: CrashReportSender.pixelEvents,
                fireCrashPixel: { bundleID, appVersion, failedToReadCrashVersion in
                    let appIdentifier = CrashPixelAppIdentifier(bundleID)
                    if let appVersion {
                        PixelKit.fire(GeneralPixel.crash(appIdentifier: appIdentifier),
                                    frequency: .dailyAndStandard,
                                    withAdditionalParameters: [PixelKit.Parameters.appVersion: appVersion],
                                    includeAppVersionParameter: false)
                    } else {
                        let additionalParameters = failedToReadCrashVersion ? ["failedToReadCrashVersion": "true"] : [:]
                        PixelKit.fire(GeneralPixel.crash(appIdentifier: appIdentifier),
                                    frequency: .dailyAndStandard,
                                    withAdditionalParameters: additionalParameters)
                    }
                },
                fireFailedToReadContentsPixel: {
                    PixelKit.fire(GeneralPixel.crashReportingFailedToReadContents, frequency: .dailyAndStandard)
                },
                promptForConsent: { crashReport in
                    await CrashReportPromptPresenter().showPrompt(for: crashReport) == .allow
                }
            )

        } else {
            fatalError("Unsupported build type: \(buildType)")
        }
    }
}
