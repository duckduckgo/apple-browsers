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

    public var isDefaultBrowserPromptsForActiveUsersFeatureEnabled: Bool = true

    public var isDefaultBrowserPromptsForInactiveUsersFeatureEnabled: Bool = true

    public var firstActiveModalDelayDays: Int = 1

    public var secondActiveModalDelayDays: Int = 2

    public var subsequentActiveModalRepeatIntervalDays: Int = 3

    public var inactiveModalNumberOfDaysSinceInstall: Int = 28

    public var inactiveModalNumberOfInactiveDays: Int = 7
}

package final class MockDefaultBrowserPromptFeatureFlagProvider: DefaultBrowserPromptFeatureFlagProvider {
    package var isDefaultBrowserPromptsForActiveUsersFeatureEnabled: Bool = true

    package var isDefaultBrowserPromptsForInactiveUsersFeatureEnabled: Bool = true

    package init() {}
}

package final class MockDefaultBrowserPromptFeatureFlagSettingsProvider: DefaultBrowserPromptFeatureFlagSettingsProvider {
    package var defaultBrowserPromptFeatureSettings: [String: Any] = [:]

    package init() {}
}
