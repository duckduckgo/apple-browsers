//
//  MockDefaultBrowserPromptFeatureFlag.swift
//  DuckDuckGo
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
import SetDefaultBrowserCore

public final class MockDefaultBrowserPromptFeatureFlag: DefaultBrowserPromptFeatureFlagger {
    public init() {}

    public var isDefaultBrowserPromptsFeatureEnabled: Bool = true

    public var firstModalDelayDays: Int = 1

    public var secondModalDelayDays: Int = 2

    public var subsequentModalRepeatIntervalDays: Int = 3
}

package final class MockDefaultBrowserPromptFeatureFlagProvider: DefaultBrowserPromptFeatureFlagProvider {
    package var isDefaultBrowserPromptsFeatureEnabled: Bool = true

    package init() {}
}

package final class MockDefaultBrowserPromptFeatureFlagSettingsProvider: DefaultBrowserPromptFeatureFlagSettingsProvider {
    package var featureSettings: [String: Any] = [:]

    package init() {}
}
