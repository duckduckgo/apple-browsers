//
//  StringRangeMatching.swift
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

protocol StringRangeMatching: MatchingAttribute, Equatable {
    var min: String { get set }
    var max: String { get set }
    var value: String { get set }
    var fallback: Bool? { get set }

    static var defaultMaxValue: String { get }

    init(min: String, max: String, value: String, fallback: Bool?)
}

extension StringRangeMatching {

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else {
            self.init(fallback: nil)
            return
        }

        let min = jsonMatchingAttribute[RuleAttributes.min] as? String ?? MatchingAttributeDefaults.stringDefaultValue
        let max = jsonMatchingAttribute[RuleAttributes.max] as? String ?? Self.defaultMaxValue
        let value = jsonMatchingAttribute[RuleAttributes.value] as? String ?? MatchingAttributeDefaults.stringDefaultValue
        let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool

        self.init(min: min, max: max, value: value, fallback: fallback)
    }

    init(fallback: Bool?) {
        self.init(
            min: MatchingAttributeDefaults.stringDefaultValue,
            max: Self.defaultMaxValue,
            value: MatchingAttributeDefaults.stringDefaultValue,
            fallback: fallback
        )
    }

    func evaluate(for value: String) -> EvaluationResult {
        guard self.value == MatchingAttributeDefaults.stringDefaultValue else {
            return StringMatchingAttribute(self.value).matches(value: value)
        }
        return RangeStringNumericMatchingAttribute(min: min, max: max).matches(value: value)
    }
}
