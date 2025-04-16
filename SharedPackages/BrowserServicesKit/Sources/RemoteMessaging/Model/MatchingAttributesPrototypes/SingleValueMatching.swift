//
//  SingleValueMatching.swift
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

public protocol SingleValueMatching: MatchingAttribute, Equatable {
    associatedtype Value: Equatable

    var value: Value? { get set }
    var fallback: Bool? { get set }

    init(value: Value?, fallback: Bool?)
}

public extension SingleValueMatching {

    init(jsonMatchingAttribute: AnyDecodable) {
        guard let jsonMatchingAttribute = jsonMatchingAttribute.value as? [String: Any] else {
            self.init(value: nil, fallback: nil)
            return
        }

        let value = jsonMatchingAttribute[RuleAttributes.value] as? Value
        let fallback = jsonMatchingAttribute[RuleAttributes.fallback] as? Bool
        self.init(value: value, fallback: fallback)
    }
}

public extension SingleValueMatching where Value == Bool {
    func evaluate(for value: Bool) -> EvaluationResult {
        guard let expectedValue = self.value else {
            return .fail
        }
        return BooleanMatchingAttribute(expectedValue).matches(value: value)
    }
}

public extension SingleValueMatching where Value == String {
    func evaluate(for value: String) -> EvaluationResult {
        guard let expectedValue = self.value else {
            return .fail
        }
        return StringMatchingAttribute(expectedValue).matches(value: value)
    }

    func evaluate(for value: String?) -> EvaluationResult {
        guard let value, let expectedValue = self.value else {
            return .fail
        }
        return StringMatchingAttribute(expectedValue).matches(value: value)
    }
}

public extension SingleValueMatching where Value == [String] {
    func evaluate(for value: String) -> EvaluationResult {
        guard let expectedValue = self.value else {
            return .fail
        }
        return StringArrayMatchingAttribute(expectedValue).matches(value: value)
    }
}
