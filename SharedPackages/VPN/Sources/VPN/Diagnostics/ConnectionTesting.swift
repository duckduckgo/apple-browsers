//
//  ConnectionTesting.swift
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

/// Protocol abstraction for VPN connection testing functionality.
///
/// This protocol defines the interface for testing whether the Network Protection
/// connection is working properly by performing connectivity checks.
///
@MainActor
protocol ConnectionTesting: AnyObject {

    /// Starts the connection tester.
    ///
    /// - Parameters:
    ///   - tunnelIfName: The name of the tunnel interface to test
    ///   - testImmediately: If `true`, performs an immediate connection test
    /// - Throws: An error if the tester fails to start
    func start(tunnelIfName: String, testImmediately: Bool) async throws

    /// Stops the connection tester.
    func stop()

    /// Forces the next connection test to fail (for testing purposes).
    func failNextTest()
}
