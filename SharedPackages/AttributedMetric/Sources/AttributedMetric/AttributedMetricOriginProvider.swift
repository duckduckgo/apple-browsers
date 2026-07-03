//
//  AttributedMetricOriginProvider.swift
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

import Foundation

/// A type that provides the `origin` used to anonymously track installations without tracking retention.
public protocol AttributedMetricOriginProvider: AnyObject {
    /// A string representing the acquisition funnel.
    var origin: String? { get }
}

#if os(macOS)
public final class DefaultAttributedMetricOriginProvider: AttributedMetricOriginProvider {
    public let origin: String?

    /// Creates an instance with a closure that returns the raw origin string.
    /// - Parameter loadOrigin: A closure that returns the raw origin string from the bundle, or `nil` if absent.
    public init(loadOrigin: () -> String?) {
        origin = loadOrigin()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        return isEmpty ? nil : self
    }
}
#endif
