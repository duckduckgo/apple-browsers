//
//  Logger+Subscription.swift
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
import os.log

public extension Logger {
    private static let subscriptionSubsystem = "Subscription"
    static let subscription = Logger(subsystem: Self.subscriptionSubsystem, category: "")
    static let subscriptionAppStorePurchaseFlow = Logger(subsystem: Self.subscriptionSubsystem, category: "AppStorePurchaseFlow")
    static let subscriptionAppStoreRestoreFlow = Logger(subsystem: Self.subscriptionSubsystem, category: "AppStoreRestoreFlow")
    static let subscriptionStripePurchaseFlow = Logger(subsystem: Self.subscriptionSubsystem, category: "StripePurchaseFlow")
    static let subscriptionEndpointService = Logger(subsystem: Self.subscriptionSubsystem, category: "EndpointService")
    static let subscriptionStorePurchaseManager = Logger(subsystem: Self.subscriptionSubsystem, category: "StorePurchaseManager")
    static let subscriptionKeychain = Logger(subsystem: Self.subscriptionSubsystem, category: "KeyChain")
}
