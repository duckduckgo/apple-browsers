//
//  MockVariant.swift
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

import BrowserServicesKit
import Foundation

public class MockVariant: Variant {
    public var name: String
    public var weight: Int
    public var isIncluded: () -> Bool
    public var features: [FeatureName]

    public init(name: String, weight: Int, isIncluded: @escaping () -> Bool, features: [FeatureName]) {
        self.name = name
        self.weight = weight
        self.isIncluded = isIncluded
        self.features = features
    }
}
