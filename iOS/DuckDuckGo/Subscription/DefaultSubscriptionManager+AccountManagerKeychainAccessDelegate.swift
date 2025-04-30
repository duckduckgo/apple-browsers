//
//  DefaultSubscriptionManager+AccountManagerKeychainAccessDelegate.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Core
import Subscription
import os.log

extension DefaultSubscriptionManager: @retroactive AccountManagerKeychainAccessDelegate {

    public func accountManagerKeychainAccessFailed(accessType: AccountKeychainAccessType, error: any Error) {

        guard let expectedError = error as? AccountKeychainAccessError else {
            assertionFailure("Unexpected error type: \(error)")
            Logger.subscription.fault("Unexpected error type: \(error)")
            return
        }

        let parameters = [PixelParameters.privacyProKeychainAccessType: accessType.rawValue,
                          PixelParameters.privacyProKeychainError: expectedError.errorDescription,
                          PixelParameters.source: KeychainErrorSource.browser.rawValue,
                          PixelParameters.authVersion: KeychainErrorAuthVersion.v1.rawValue]
        DailyPixel.fireDailyAndCount(pixel: .privacyProKeychainAccessError,
                                     pixelNameSuffixes: DailyPixel.Constant.legacyDailyPixelSuffixes,
                                     withAdditionalParameters: parameters)
    }
}
