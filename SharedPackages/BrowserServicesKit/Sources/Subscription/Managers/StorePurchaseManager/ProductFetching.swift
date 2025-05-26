//
//  ProductFetching.swift
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

/// A protocol for types that can fetch subscription products.
@available(macOS 12.0, iOS 15.0, *)
public protocol ProductFetching {
    /// Fetches products for the specified identifiers.
    /// - Parameter identifiers: An array of product identifiers to fetch.
    /// - Returns: An array of subscription products.
    /// - Throws: An error if the fetch operation fails.
    func products(for identifiers: [String]) async throws -> [any SubscriptionProduct]
}

/// A default implementation of ProductFetching that uses StoreKit's standard product fetching.
@available(macOS 12.0, iOS 15.0, *)
public final class DefaultProductFetcher: ProductFetching {
    /// Initializes a new DefaultProductFetcher instance.
    public init() {}

    /// Fetches products using StoreKit's Product.products API.
    /// - Parameter identifiers: An array of product identifiers to fetch.
    /// - Returns: An array of subscription products.
    /// - Throws: An error if the fetch operation fails.
    public func products(for identifiers: [String]) async throws -> [any SubscriptionProduct] {
        return try await Product.products(for: identifiers)
    }
}
