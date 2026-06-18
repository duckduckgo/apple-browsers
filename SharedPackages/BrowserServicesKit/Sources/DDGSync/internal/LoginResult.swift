//
//  LoginResult.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

struct LoginResult: Sendable {
    let account: SyncAccount
    let devices: [RegisteredDevice]
    let keys: [ProtectedKey]?
    let accessCredentials: [AccessCredential]?

    init(account: SyncAccount, devices: [RegisteredDevice], keys: [ProtectedKey]? = nil, accessCredentials: [AccessCredential]? = nil) {
        self.account = account
        self.devices = devices
        self.keys = keys
        self.accessCredentials = accessCredentials
    }
}
