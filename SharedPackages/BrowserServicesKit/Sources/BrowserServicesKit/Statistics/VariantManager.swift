//
//  VariantManager.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

/// Define new experimental features by extending the struct in client project.
public struct FeatureName: RawRepresentable, Equatable {

    public var rawValue: String

    // Used for unit tests
    public static let dummy = FeatureName(rawValue: "dummy")

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

}

public protocol VariantManager {

    var currentVariant: Variant? { get }
    func assignVariantIfNeeded(_ newInstallCompletion: (VariantManager) -> Void)
    func isSupported(feature: FeatureName) -> Bool

}

public protocol Variant {

    var name: String { get set }
    var weight: Int { get set }
    var isIncluded: () -> Bool { get set }
    var features: [FeatureName] { get set }

}
