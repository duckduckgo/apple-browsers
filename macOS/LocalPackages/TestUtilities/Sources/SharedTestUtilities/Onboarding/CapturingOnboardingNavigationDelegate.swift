//
//  CapturingOnboardingNavigationDelegate.swift
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

public class CapturingOnboardingNavigationDelegate {

    public var didCallSearchFor = false
    public var didNavigateToCalled = false
    public var capturedQuery = ""
    public var capturedUrlString = ""

    public init() {}

    public func searchFromOnboarding(for query: String) {
        didCallSearchFor = true
        capturedQuery = query
    }

    public func navigateFromOnboarding(to url: URL) {
        didNavigateToCalled = true
        capturedUrlString = url.absoluteString
    }
}
