//
//  NumericRangeMatching.swift
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

public protocol NumericRangeMatching: MatchingAttribute, Equatable {
    var min: Int { get set }
    var max: Int { get set }
    var value: Int { get set }
    var fallback: Bool? { get set }

    init(min: Int, max: Int, value: Int, fallback: Bool?)
}

public extension NumericRangeMatching {

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else {
            self.init(fallback: nil)
            return
        }

        let min = jsonMatchingAttribute[RuleAttributes.min] as? Int ?? MatchingAttributeDefaults.intDefaultValue
        let max = jsonMatchingAttribute[RuleAttributes.max] as? Int ?? MatchingAttributeDefaults.intDefaultMaxValue
        let value = jsonMatchingAttribute[RuleAttributes.value] as? Int ?? MatchingAttributeDefaults.intDefaultValue
        let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool

        self.init(min: min, max: max, value: value, fallback: fallback)
    }

    init(fallback: Bool?) {
        self.init(
            min: MatchingAttributeDefaults.intDefaultValue,
            max: MatchingAttributeDefaults.intDefaultMaxValue,
            value: MatchingAttributeDefaults.intDefaultValue,
            fallback: fallback
        )
    }

    func evaluate(for value: Int) -> EvaluationResult {
        guard self.value == MatchingAttributeDefaults.intDefaultValue else {
            return IntMatchingAttribute(self.value).matches(value: value)
        }
        return RangeIntMatchingAttribute(min: min, max: max).matches(value: value)
    }
}
