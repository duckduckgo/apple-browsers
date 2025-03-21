//
//  RemoteMessagingAvailabilityProviding.swift
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

import BrowserServicesKit
import Combine
import Foundation

/**
 * This protocol provides abstraction for the RMF feature flag.
 */
public protocol RemoteMessagingAvailabilityProviding {
    var isRemoteMessagingAvailable: Bool { get }

    var isRemoteMessagingAvailablePublisher: AnyPublisher<Bool, Never> { get }
}

/**
 * This struct exposes RMF feature flag from Privacy Config.
 *
 * We're using a struct like this because PrivacyConfigurationManaging (a protocol from another Swift module)
 * can't be extended with conformance to a protocol from this Swift module.
 */
public struct PrivacyConfigurationRemoteMessagingAvailabilityProvider: RemoteMessagingAvailabilityProviding {
    public init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    public var isRemoteMessagingAvailable: Bool {
        privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .remoteMessaging)
    }

    /**
     * This publisher is guaranteed to emit values without duplicates. Events are emitted on an arbitrary thread.
     */
    public var isRemoteMessagingAvailablePublisher: AnyPublisher<Bool, Never> {
        privacyConfigurationManager.updatesPublisher
            .dropFirst() // skip initial event emitted from PrivacyConfigurationManager initializer's `reload`
            .map { _ in isRemoteMessagingAvailable }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private var privacyConfigurationManager: PrivacyConfigurationManaging
}
