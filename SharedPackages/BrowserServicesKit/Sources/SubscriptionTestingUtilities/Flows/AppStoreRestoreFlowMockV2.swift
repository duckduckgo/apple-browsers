//
//  AppStoreRestoreFlowMockV2.swift
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
import Subscription

public final class AppStoreRestoreFlowMockV2: AppStoreRestoreFlowV2 {

    public var restoreAccountFromPastPurchaseResult: Result<String, AppStoreRestoreFlowErrorV2>!
    public var restoreAccountFromPastPurchaseCalled: Bool = false
    public var restoreSubscriptionAfterExpiredRefreshTokenHandler: (() async throws -> Void)?

    public init() { }

    @discardableResult public func restoreAccountFromPastPurchase() async -> Result<String, AppStoreRestoreFlowErrorV2> {
        restoreAccountFromPastPurchaseCalled = true
        return restoreAccountFromPastPurchaseResult
    }

    public var restoreSubscriptionAfterExpiredRefreshTokenError: Error?
    public var restoreSubscriptionAfterExpiredRefreshTokenCalled: Bool = false
    public func restoreSubscriptionAfterExpiredRefreshToken() async throws {

        restoreSubscriptionAfterExpiredRefreshTokenCalled = true

        if let handler = restoreSubscriptionAfterExpiredRefreshTokenHandler {
            try await handler()
        }

        if let restoreSubscriptionAfterExpiredRefreshTokenError {
            throw restoreSubscriptionAfterExpiredRefreshTokenError
        }
    }
}
