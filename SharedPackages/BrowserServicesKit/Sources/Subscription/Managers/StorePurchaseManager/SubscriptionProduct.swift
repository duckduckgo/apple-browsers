//
//  SubscriptionProduct.swift
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

/// A protocol that defines the core functionality and properties of a subscription product.
/// Conforming types must provide information about pricing, description, and subscription terms.
@available(macOS 12.0, iOS 15.0, *)
public protocol SubscriptionProduct: Equatable {
    /// The unique identifier of the product.
    var id: String { get }

    /// The user-facing name of the product.
    var displayName: String { get }

    /// The formatted price that should be displayed to users.
    var displayPrice: String { get }

    /// A detailed description of the product.
    var description: String { get }

    /// Indicates whether this is a monthly subscription.
    var isMonthly: Bool { get }

    /// Indicates whether this is a yearly subscription.
    var isYearly: Bool { get }

    /// The introductory offer associated with this subscription, if any.
    var introductoryOffer: SubscriptionProductIntroductoryOffer? { get }

    /// A Boolean value that indicates whether this is a Free Trial product.
    var isFreeTrialProduct: Bool { get }

    /// Whether the user is eligible for an introductory offer.
    var isEligibleForFreeTrial: Bool { get }

    /// Refreshes the free trial eligibility status
    /// - Returns: The updated eligibility status
    mutating func refreshFreeTrialEligibility() async -> Bool

    /// Initiates a purchase of the subscription with the specified options.
    /// - Parameter options: A set of options to configure the purchase.
    /// - Returns: The result of the purchase attempt.
    /// - Throws: An error if the purchase fails.
    func purchase(options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult
}
@available(macOS 12.0, iOS 15.0, *)
public struct AppStoreSubscriptionProduct: SubscriptionProduct {
    /// The underlying StoreKit Product
    private let product: any StoreProduct

    // MARK: - SubscriptionProduct Conformance

    /// The unique identifier of the product, forwarded from the underlying store product.
    public var id: String { product.id }
    /// The user-facing name of the product, forwarded from the underlying store product.
    public var displayName: String { product.displayName }
    /// The formatted price that should be displayed to users, forwarded from the underlying store product.
    public var displayPrice: String { product.displayPrice }
    /// A detailed description of the product, forwarded from the underlying store product.
    public var description: String { product.description }
    /// Indicates whether this is a monthly subscription, forwarded from the underlying store product.
    public var isMonthly: Bool { product.isMonthly }
    /// Indicates whether this is a yearly subscription, forwarded from the underlying store product.
    public var isYearly: Bool { product.isYearly }
    /// The introductory offer associated with this subscription, forwarded from the underlying store product.
    public var introductoryOffer: (any SubscriptionProductIntroductoryOffer)? {
        product.introductoryOffer
    }
    /// A Boolean value indicating whether this product relates to a free trial, forwarded from the underlying store product.
    public var isFreeTrialProduct: Bool { product.isFreeTrialProduct }

    /// User eligibility for free trial
    public var isEligibleForFreeTrial: Bool

    /// Creates an AppStoreSubscriptionProduct with cached eligibility state
    /// - Parameters:
    ///   - product: The StoreProduct to wrap
    ///   - cachedEligibility: Initial cached eligibility state (defaults to false)
    public init(product: any StoreProduct, freeTrialEligibility: Bool = false) {
        self.product = product
        self.isEligibleForFreeTrial = freeTrialEligibility
    }

    /// Creates an AppStoreSubscriptionProduct and asynchronously determines eligibility
    /// - Parameter product: The StoreProduct to wrap
    public static func create(product: any StoreProduct) async -> AppStoreSubscriptionProduct {
        let isEligible: Bool

        guard product.isFreeTrialProduct else {
            isEligible = false
            return AppStoreSubscriptionProduct(product: product, freeTrialEligibility: isEligible)
        }

        isEligible = await product.isEligibleForFreeTrial
        return AppStoreSubscriptionProduct(product: product, freeTrialEligibility: isEligible)
    }

    /// Refreshes the free trial eligibility status from the underlying product
    /// - Returns: The updated eligibility status
    @discardableResult
    public mutating func refreshFreeTrialEligibility() async -> Bool {
        guard product.isFreeTrialProduct else {
            isEligibleForFreeTrial = false
            return false
        }

        let updatedEligibility = await product.isEligibleForFreeTrial
        isEligibleForFreeTrial = updatedEligibility
        return updatedEligibility
    }

    public func purchase(options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult {
        return try await product.purchase(options: options)
    }

    public static func == (lhs: AppStoreSubscriptionProduct, rhs: AppStoreSubscriptionProduct) -> Bool {
        return lhs.product.id == rhs.product.id
    }
}

/// Protocol that captures the Product interface needed by AppStoreSubscriptionProduct
@available(macOS 12.0, iOS 15.0, *)
public protocol StoreProduct {
    /// The unique identifier of the store product.
    var id: String { get }
    /// The user-facing name of the product as it appears in the store.
    var displayName: String { get }
    /// The formatted price string that should be displayed to users, including currency symbols.
    var displayPrice: String { get }
    /// A detailed description of the product and its features.
    var description: String { get }
    /// A Boolean value indicating whether this is a monthly subscription product.
    var isMonthly: Bool { get }
    /// A Boolean value indicating whether this is a yearly subscription product.
    var isYearly: Bool { get }
    /// The introductory offer associated with this subscription product, if available.
    var introductoryOffer: (any SubscriptionProductIntroductoryOffer)? { get }
    /// A Boolean value indicating whether this product relates to a free trial offer.
    var isFreeTrialProduct: Bool { get }
    /// Asynchronously determines whether the user is eligible for an introductory offer.
    var isEligibleForFreeTrial: Bool { get async }
    /// Initiates a purchase of the product with the specified options.
    /// - Parameter options: A set of options to configure the purchase behavior.
    /// - Returns: The result of the purchase attempt.
    /// - Throws: An error if the purchase fails or encounters issues.
    func purchase(options: Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult
}

/// Extends StoreKit's Product to conform to StoreProduct.
@available(macOS 12.0, iOS 15.0, *)
extension Product: StoreProduct {
    /// Determines if this is a monthly subscription by checking if the subscription period
    /// is exactly one month.
    public var isMonthly: Bool {
        guard let subscription else { return false }
        return subscription.subscriptionPeriod.unit == .month &&
        subscription.subscriptionPeriod.value == 1
    }

    /// Determines if this is a yearly subscription by checking if the subscription period
    /// is exactly one year.
    public var isYearly: Bool {
        guard let subscription else { return false }
        return subscription.subscriptionPeriod.unit == .year &&
        subscription.subscriptionPeriod.value == 1
    }

    /// Returns the introductory offer for this subscription if available.
    public var introductoryOffer: (any SubscriptionProductIntroductoryOffer)? {
        subscription?.introductoryOffer
    }

    /// A Boolean value that indicates whether the subscription product is one which relates to a Free Trial.
    ///
    /// This property returns `true` if the subscription has an associated introductory offer marked as a free trial
    /// or if the subscription's identifier contains the designated free trial identifer.
    /// If neither condition is met, the property returns `false`.
    public var isFreeTrialProduct: Bool {
        return subscription?.introductoryOffer?.isFreeTrial ?? false || id.contains(StoreSubscriptionConstants.freeTrialIdentifer)
    }

    /// Asynchronously checks if the user is eligible for an introductory offer.
    public var isEligibleForFreeTrial: Bool {
        get async {
            guard let subscription else { return false }
            return await subscription.isEligibleForIntroOffer
        }
    }

    /// Implements Equatable by comparing product IDs.
    public static func == (lhs: Product, rhs: Product) -> Bool {
        return lhs.id == rhs.id
    }
}
