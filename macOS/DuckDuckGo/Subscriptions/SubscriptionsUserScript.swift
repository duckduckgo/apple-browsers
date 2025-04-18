//
//  SubscriptionsUserScript.swift
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

import Common
import UserScript

final class SubscriptionsUserScript: NSObject, Subfeature {

    enum MessageNames: String, CaseIterable {
        case handshake
        case subscriptionDetails
    }

    private let handler: SubscriptionsUserScriptHandling
    public let featureName: String = "subscriptions"
    weak var broker: UserScriptMessageBroker?
    private(set) var messageOriginPolicy: MessageOriginPolicy

    init(handler: SubscriptionsUserScriptHandling) {
        self.handler = handler
        var rules = [HostnameMatchingRule]()

        /// Default rule for DuckDuckGo Subscriptions
        rules.append(.exact(hostname: URL.duckDuckGo.absoluteString))
        rules.append(.exact(hostname: "abrown.duckduckgo.com"))

        self.messageOriginPolicy = .only(rules: rules)
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch MessageNames(rawValue: methodName) {
        case .handshake:
            return handler.handshake
        case .subscriptionDetails:
            return handler.subscriptionDetails
        default:
            return nil
        }
    }
}
