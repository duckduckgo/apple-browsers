//
//  DataBrokerAuthenticationManagerBuilder.swift
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
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Subscription

final public class DataBrokerAuthenticationManagerBuilder {

    static func buildAuthenticationManager(subscriptionManager: any SubscriptionAuthV1toV2Bridge) -> DataBrokerProtectionAuthenticationManager {
        let settings = DataBrokerProtectionSettings(defaults: .dbp)
        let subscriptionManager = DataBrokerProtectionSubscriptionManager(subscriptionManager: subscriptionManager,
                                                                          runTypeProvider: settings,
                                                                          isAuthV2Enabled: settings.isAuthV2Enabled)
        return DataBrokerProtectionAuthenticationManager(subscriptionManager: subscriptionManager)
    }
}
