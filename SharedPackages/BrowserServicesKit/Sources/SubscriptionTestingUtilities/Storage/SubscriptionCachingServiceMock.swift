//
//  SubscriptionCachingServiceMock.swift
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

import Foundation
import Subscription

public final class SubscriptionCachingServiceMock: SubscriptionCachingService {

    public var cachedSubscription: DuckDuckGoSubscription?
    public var setCalled: Bool = false
    public var resetCalled: Bool = false

    public var isPresent: Bool { cachedSubscription != nil }

    public init(cachedSubscription: DuckDuckGoSubscription? = nil) {
        self.cachedSubscription = cachedSubscription
    }

    public func get() async -> DuckDuckGoSubscription? {
        return cachedSubscription
    }

    public func set(_ subscription: DuckDuckGoSubscription) async {
        setCalled = true
        cachedSubscription = subscription
    }

    public func reset() {
        resetCalled = true
        cachedSubscription = nil
    }
}
