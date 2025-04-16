//
//  SubscriptionTokenKeychainStorage+LegacyAuthTokenStoring.swift
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
import Networking
import os.log

extension SubscriptionTokenKeychainStorage: LegacyAuthTokenStoring {

    public var token: String? {
        get {
            do {
                return try getAccessToken()
            } catch {
                if let error = error as? AccountKeychainAccessError {
                    errorHandler?(AccountKeychainAccessType.getAuthToken, error)
                } else {
                    assertionFailure("Unexpected error: \(error)")
                    Logger.subscriptionKeychain.fault("Unexpected error: \(error, privacy: .public)")
                }
            }
            return nil
        }
        set(newValue) {
            do {
                guard let newValue else {
                    try removeAccessToken()
                    return
                }
                try store(accessToken: newValue)
            } catch {
                Logger.subscriptionKeychain.fault("Failed to set TokenContainer: \(error, privacy: .public)")
                if let error = error as? AccountKeychainAccessError {
                    errorHandler?(AccountKeychainAccessType.storeAuthToken, error)
                } else {
                    assertionFailure("Unexpected error: \(error)")
                    Logger.subscriptionKeychain.fault("Unexpected error: \(error, privacy: .public)")
                }
            }
        }
    }
}
