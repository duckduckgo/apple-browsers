//
//  CrashCollectionService.swift
//  DuckDuckGo
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

import Common
import FoundationExtensions
import Core
import Crashes
import PrivacyConfig
import FeatureFlags_iOS
import PixelKit

final class CrashCollectionService {

    private let appSettings: AppSettings
    private let application: UIApplication

    private lazy var crashCollection = CrashCollection(crashReportSender: CrashReportSender(platform: .iOS,
                                                                                            pixelEvents: CrashReportSender.pixelEvents),
                                                       crashCollectionStorage: UserDefaults())
    private lazy var crashReportUploaderOnboarding = CrashCollectionOnboarding(appSettings: appSettings)

    init(appSettings: AppSettings = AppUserDefaults(),
         application: UIApplication = UIApplication.shared,
         featureFlagger: FeatureFlagger) {
        self.appSettings = appSettings
        self.application = application

        let isCallStackLimitingEnabled = featureFlagger.isFeatureOn(.crashCollectionLimitCallStackTreeDepth)
        let callStackDepthLimit: Int? = isCallStackLimitingEnabled ? 250 : nil

        crashCollection.startAttachingCrashLogMessages(callStackDepthLimit: callStackDepthLimit) { [weak self] pixelParameters, payloads, sendReport in
            pixelParameters.forEach { params in

                // Calculate appIdentifier for what crashed - nil for main bundle, otherwise the app identifier is the bundle identifier minus the main bundle identifier.
                var params = params
                var appIdentifier: String?
                if let bundle = params.removeValue(forKey: .bundle),
                   let mainBundle = Bundle.main.bundleIdentifier {
                    if bundle != mainBundle {
                        appIdentifier = bundle.dropping(prefix: mainBundle).removingCharacters(in: .punctuationCharacters).lowercased()
                    }
                }

                let additionalParameters = Dictionary(uniqueKeysWithValues: params.map { ($0.key.rawValue, $0.value) })
                PixelKit.fire(Pixel.Event.dbCrashDetected(appIdentifier: appIdentifier),
                              options: PixelKit.Options(additionalParameters: additionalParameters, includeAppVersionParameter: false))

                // Each crash comes with an `appVersion` parameter representing the version that the crash occurred on.
                // This is to disambiguate the situation where a crash occurs, but isn't sent until the next update.
                // If for some reason the parameter can't be found, fall back to the current version.
                if let crashAppVersion = params[.appVersion] {
                    let dailyParameters = [PixelParameters.appVersion: crashAppVersion]
                    // `includeAppVersionParameter: false` so PixelKit does not overwrite the crash's
                    // own `appVersion` with the current one. Legacy `Pixel.fire` only filled the
                    // parameter in when the caller had not already set it.
                    PixelKit.fire(Pixel.Event.dbCrashDetectedDaily(appIdentifier: appIdentifier),
                                  frequency: .legacyDailyNoSuffix,
                                  options: PixelKit.Options(additionalParameters: dailyParameters,
                                                            includeAppVersionParameter: false))
                } else {
                    PixelKit.fire(Pixel.Event.dbCrashDetectedDaily(appIdentifier: appIdentifier), frequency: .legacyDailyNoSuffix)
                }
            }

            // Async dispatch because rootViewController may otherwise be nil here
            DispatchQueue.main.async {
                guard let viewController = self?.application.firstKeyWindow?.rootViewController else { return }
                self?.crashReportUploaderOnboarding.presentOnboardingIfNeeded(for: payloads, from: viewController, sendReport: sendReport)
            }
        }
    }

}
