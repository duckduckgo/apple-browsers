//
//  UpdateControllerFactory+Sparkle.swift
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

import AppUpdaterShared
import BrowserServicesKit
import FeatureFlags
import Persistence
import PixelKit
import PrivacyConfig
import Subscription

/// Factory extension that provides the Sparkle updater implementation.
///
/// This extension is compiled into the SparkleAppUpdater package and provides
/// the Sparkle-specific update controller instantiation.
///
/// See `UpdateControllerFactory` in `UpdateController.swift` for details on
/// how `instantiate` is consumed.
extension UpdateControllerFactory: SparkleUpdateControllerFactory {
    public static func instantiate(internalUserDecider: InternalUserDecider,
                                   featureFlagger: FeatureFlagger,
                                   pixelFiring: PixelFiring?,
                                   notificationPresenter: any UpdateNotificationPresenting,
                                   keyValueStore: any ThrowingKeyValueStoring,
                                   allowCustomUpdateFeed: Bool,
                                   wideEvent: WideEventManaging,
                                   isOnboardingFinished: @escaping () -> Bool,
                                   openUpdatesPage: @escaping () -> Void) -> any SparkleUpdateControlling {
        return SparkleUpdateController(internalUserDecider: internalUserDecider,
                                       featureFlagger: featureFlagger,
                                       pixelFiring: pixelFiring,
                                       notificationPresenter: notificationPresenter,
                                       keyValueStore: keyValueStore,
                                       allowCustomUpdateFeed: allowCustomUpdateFeed,
                                       wideEvent: wideEvent,
                                       isOnboardingFinished: isOnboardingFinished,
                                       openUpdatesPage: openUpdatesPage)
    }
}
