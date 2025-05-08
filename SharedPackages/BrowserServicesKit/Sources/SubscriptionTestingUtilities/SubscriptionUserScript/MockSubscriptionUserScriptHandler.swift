//
//  MockSubscriptionUserScriptHandler.swift
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

@testable import Subscription
import UserScript

public final class MockSubscriptionUserScriptHandler: SubscriptionUserScriptHandling {

    public init() {}

    public var handshakeCallCount = 0
    public var subscriptionDetailsCallCount = 0

    public var handshake: (Any, any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.HandshakeResponse = { _, _ in .init(availableMessages: [.subscriptionDetails], platform: .ios) }
    public var subscriptionDetails: (Any, any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.SubscriptionDetails = { _, _ in .notSubscribed }

    public func handshake(params: Any, message: any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.HandshakeResponse {
        handshakeCallCount += 1
        return try await handshake(params, message)
    }

    public func subscriptionDetails(params: Any, message: any UserScriptMessage) async throws -> SubscriptionUserScript.DataModel.SubscriptionDetails {
        subscriptionDetailsCallCount += 1
        return try await subscriptionDetails(params, message)
    }
}
