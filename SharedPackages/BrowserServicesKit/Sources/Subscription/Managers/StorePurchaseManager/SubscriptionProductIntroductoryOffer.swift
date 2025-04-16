//
//  SubscriptionProductIntroductoryOffer.swift
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
import StoreKit

/// A protocol that defines the properties of an introductory offer for a subscription product.
/// Use this protocol to represent trial periods, introductory prices, or other special offers.
@available(macOS 12.0, iOS 15.0, *)
public protocol SubscriptionProductIntroductoryOffer {
    /// The unique identifier of the introductory offer.
    var id: String? { get }

    /// The formatted price of the offer that should be displayed to users.
    var displayPrice: String { get }

    /// The duration of the offer in days.
    var periodInDays: Int { get }

    /// Indicates whether this offer represents a free trial period.
    var isFreeTrial: Bool { get }
}

/// Extends StoreKit's Product.SubscriptionOffer to conform to SubscriptionProductIntroductoryOffer.
@available(macOS 12.0, iOS 15.0, *)
extension Product.SubscriptionOffer: SubscriptionProductIntroductoryOffer {
    /// Calculates the total number of days in the offer period by multiplying
    /// the base period length by the period count.
    public var periodInDays: Int {
        period.periodInDays * periodCount
    }

    /// Determines if this offer represents a free trial based on the payment mode.
    public var isFreeTrial: Bool {
        paymentMode == .freeTrial
    }
}

@available(macOS 12.0, iOS 15.0, *)
private extension Product.SubscriptionPeriod {

    var periodInDays: Int {
        switch unit {
        case .day: return value
        case .week: return value * 7
        case .month: return value * 30
        case .year: return value * 365
        @unknown default:
            return value
        }
    }
}
