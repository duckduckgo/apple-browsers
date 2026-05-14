//
//  SubscriptionPixelType.swift
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
import Networking

public enum SubscriptionPixelType: Equatable {
    case invalidRefreshToken
    case subscriptionIsActive
    case getTokensError(AuthTokensCachePolicy, Error)
    case invalidRefreshTokenSignedOut
    case invalidRefreshTokenRecovered
    case purchaseSuccessAfterPendingTransaction
    case pendingTransactionApproved

    public static func == (lhs: SubscriptionPixelType, rhs: SubscriptionPixelType) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRefreshToken, .invalidRefreshToken),
            (.subscriptionIsActive, .subscriptionIsActive),
            (.invalidRefreshTokenSignedOut, .invalidRefreshTokenSignedOut),
            (.invalidRefreshTokenRecovered, .invalidRefreshTokenRecovered),
            (.getTokensError, .getTokensError),
            (.purchaseSuccessAfterPendingTransaction, .purchaseSuccessAfterPendingTransaction),
            (.pendingTransactionApproved, .pendingTransactionApproved):
            return true
        default:
            return false
        }
    }
}
