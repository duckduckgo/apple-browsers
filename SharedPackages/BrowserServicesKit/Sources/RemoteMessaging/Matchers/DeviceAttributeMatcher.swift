//
//  DeviceAttributeMatcher.swift
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
import Common

public struct DeviceAttributeMatcher: AttributeMatching {

    let osVersion: String
    let localeIdentifier: String
    let formFactor: String

    public init(osVersion: String = AppVersion.shared.osVersion,
                locale: String = Locale.current.identifier,
                formFactor: String = DevicePlatform.formFactor) {
        self.osVersion = osVersion
        self.localeIdentifier = locale
        self.formFactor = formFactor
    }

    public func evaluate(matchingAttribute: MatchingAttribute) -> EvaluationResult? {
        switch matchingAttribute {
        case let matchingAttribute as LocaleMatchingAttribute:
            return matchingAttribute.evaluate(for: LocaleMatchingAttribute.localeIdentifierAsJsonFormat(localeIdentifier))
        case let matchingAttribute as OSMatchingAttribute:
            return matchingAttribute.evaluate(for: osVersion)
        case let matchingAttribute as FormFactorMatchingAttribute:
            return matchingAttribute.evaluate(for: formFactor)
        default:
            return nil
        }
    }
}
