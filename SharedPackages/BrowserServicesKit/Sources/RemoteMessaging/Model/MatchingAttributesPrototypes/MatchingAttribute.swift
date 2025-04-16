//
//  MatchingAttribute.swift
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

enum RuleAttributes {
    static let min = "min"
    static let max = "max"
    static let value = "value"
    static let fallback = "fallback"
    static let since = "since"
}

enum MatchingAttributeDefaults {
    static let intDefaultValue = -1
    static let intDefaultMaxValue = Int.max
    static let stringDefaultValue = ""
}

public protocol MatchingAttribute {
    var fallback: Bool? { get }
}
