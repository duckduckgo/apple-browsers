//
//  NetworkProtectionKeychainTokenStore+LegacyAuthTokenStoring.swift
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

import Foundation
import Networking

extension NetworkProtectionKeychainTokenStore: LegacyAuthTokenStoring {

    public var token: String? {
        get {
            var token: String?
            // extremely ugly hack, will be removed as soon auth v1 is removed
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                token = try await fetchToken() // Warning in macOS, will be removed alongside AuthV1
                semaphore.signal()
            }
            semaphore.wait()
            return token
        }
        set(newValue) {
            do {
                guard let newValue else {
                    try deleteToken()
                    return
                }
                try store(newValue)
            } catch {
                assertionFailure("Failed set token: \(error)")
            }
        }
    }
}
