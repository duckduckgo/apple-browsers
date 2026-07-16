//
//  LocalSubscriptionAccountSnapshot.swift
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

import Networking

public struct LocalSubscriptionAccountSnapshot: Equatable {

    public enum TokenState: Equatable {
        case present
        case missing
        case readError
    }

    public let tokenState: TokenState
    public let entitlements: [SubscriptionEntitlement]?

    public init(tokenState: TokenState, entitlements: [SubscriptionEntitlement]?) {
        self.tokenState = tokenState
        self.entitlements = entitlements
    }
}
