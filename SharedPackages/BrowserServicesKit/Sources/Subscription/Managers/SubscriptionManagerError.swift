//
//  SubscriptionManagerError.swift
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

import Common
import FoundationExtensions

public enum SubscriptionManagerError: DDGError {
    /// The app has no `TokenContainer`
    case noTokenAvailable
    /// There was a failure while retrieving, updating or creating the `TokenContainer`
    case errorRetrievingTokenContainer(error: Error?)

    case confirmationHasInvalidSubscription
    case noProductsFound
    /// The customer portal URL returned by the server could not be parsed as a valid URL
    case invalidPortalURL
    /// No subscription is available locally (cache is empty) and the remote fetch failed
    case noLocalSubscription
    /// Invalid-token recovery could not be attempted: no recovery handler was configured, or the
    /// purchase platform cannot restore. Distinct from a recovery that ran and failed.
    case tokenRecoveryNotAttempted

    public static func == (lhs: SubscriptionManagerError, rhs: SubscriptionManagerError) -> Bool {
        switch (lhs, rhs) {
        case (.errorRetrievingTokenContainer(let lhsError), .errorRetrievingTokenContainer(let rhsError)):
            return String(describing: lhsError) == String(describing: rhsError)
        case (.confirmationHasInvalidSubscription, .confirmationHasInvalidSubscription),
            (.noProductsFound, .noProductsFound),
            (.noTokenAvailable, .noTokenAvailable),
            (.invalidPortalURL, .invalidPortalURL),
            (.noLocalSubscription, .noLocalSubscription),
            (.tokenRecoveryNotAttempted, .tokenRecoveryNotAttempted):
            return true
        default:
            return false
        }
    }

    public var description: String {
        switch self {
        case .noTokenAvailable: "No token available"
        case .errorRetrievingTokenContainer(error: let error): "Error retrieving token container: \(String(describing: error))"
        case .confirmationHasInvalidSubscription: "Confirmation has an invalid subscription"
        case .noProductsFound: "No products found"
        case .invalidPortalURL: "Invalid customer portal URL"
        case .noLocalSubscription: "No local subscription available"
        case .tokenRecoveryNotAttempted: "Token recovery was not attempted"
        }
    }

    public static var errorDomain: String { "com.duckduckgo.subscription.SubscriptionManagerError" }

    public var errorCode: Int {
        switch self {
        case .noTokenAvailable: 12000
        case .errorRetrievingTokenContainer: 12001
        case .confirmationHasInvalidSubscription: 12002
        case .noProductsFound: 12003
        case .invalidPortalURL: 12004
        case .noLocalSubscription: 12005
        case .tokenRecoveryNotAttempted: 12006
        }
    }

    public var underlyingError: (any Error)? {
        switch self {
        case .errorRetrievingTokenContainer(error: let error):
            return error
        default:
            return nil
        }
    }
}
