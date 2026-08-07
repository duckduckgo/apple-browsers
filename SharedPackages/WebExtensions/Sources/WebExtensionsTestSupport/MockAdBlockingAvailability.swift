//
//  MockAdBlockingAvailability.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import WebExtensions

public final class MockAdBlockingAvailability: AdBlockingAvailabilityProviding {
    public var isFeatureSupported: Bool
    public var isEnabledByUser: Bool
    public var defaultYouTubeAdBlockingEnabled: Bool

    public init(
        isFeatureSupported: Bool = true,
        isEnabledByUser: Bool = false,
        defaultYouTubeAdBlockingEnabled: Bool = false
    ) {
        self.isFeatureSupported = isFeatureSupported
        self.isEnabledByUser = isEnabledByUser
        self.defaultYouTubeAdBlockingEnabled = defaultYouTubeAdBlockingEnabled
    }

    public func shouldShowAnimation(for url: URL) -> Bool {
        false
    }
}
