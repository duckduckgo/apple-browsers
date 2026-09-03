//
//  UITestTimeouts.swift
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

public enum UITestTimeouts {

    /// Mostly used to wait for element existence. This is about three times longer than needed for CI resilience.
    public static let elementExistence: Double = 5.0

    /// The fire animation has environmental dependencies, so tests wait for it to finish before continuing.
    public static let fireAnimation: Double = 30.0

    /// Timeout for page loads and network requests.
    public static let navigation: Double = 30.0

    /// Timeout for localhost test-server connections.
    public static let localTestServer: Double = 15.0
}
