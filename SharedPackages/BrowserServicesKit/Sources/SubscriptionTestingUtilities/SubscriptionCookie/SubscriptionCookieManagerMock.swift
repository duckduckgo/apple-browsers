//
//  SubscriptionCookieManagerMock.swift
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
import Common
@testable import Subscription

public final class SubscriptionCookieManagerMock: SubscriptionCookieManaging {

    public var lastRefreshDate: Date?
    public init() {}
    public func enableSettingSubscriptionCookie() { }
    public func disableSettingSubscriptionCookie() async { }
    public func refreshSubscriptionCookie() async { }
    public func resetLastRefreshDate() { }
}

public final class SubscriptionCookieManagerMockV2: SubscriptionCookieManaging {

    public var lastRefreshDate: Date?
    public init() {}
    public func enableSettingSubscriptionCookie() { }
    public func disableSettingSubscriptionCookie() async { }
    public func refreshSubscriptionCookie() async { }
    public func resetLastRefreshDate() { }
}

public final class MockSubscriptionCookieManagerEventPixelMapping: EventMapping<SubscriptionCookieManagerEvent> {

    public init() {
        super.init { _, _, _, _ in
        }
    }

    override init(mapping: @escaping EventMapping<SubscriptionCookieManagerEvent>.Mapping) {
        fatalError("Use init()")
    }
}
