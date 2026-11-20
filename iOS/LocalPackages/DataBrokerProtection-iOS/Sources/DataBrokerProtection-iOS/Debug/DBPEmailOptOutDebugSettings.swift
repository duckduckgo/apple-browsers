//
//  DBPEmailOptOutDebugSettings.swift
//  DuckDuckGo
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

#if DEBUG
import Foundation

public struct DBPEmailOptOutDebugSettings {

    private static let isCanSendEmailForcedKey = "dbp-email-opt-out-debug-is-can-send-email-forced"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .dbp) {
        self.userDefaults = userDefaults
    }

    public var isCanSendEmailForced: Bool {
        get { userDefaults.bool(forKey: Self.isCanSendEmailForcedKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.isCanSendEmailForcedKey) }
    }
}
#endif
