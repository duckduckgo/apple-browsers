//
//  KeyExpirationTesting.swift
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

/// Protocol abstraction for key expiration testing and automatic rekeying.
///
/// This protocol defines the interface for monitoring VPN key expiration
/// and triggering automatic rekeying when keys expire.
///
protocol KeyExpirationTesting: Actor {

    /// Starts the key expiration tester.
    ///
    /// - Parameter testImmediately: If `true`, performs an immediate key expiration check
    func start(testImmediately: Bool) async

    /// Stops the key expiration tester.
    func stop()

    /// Sets a custom key validity interval or resets to automatic.
    ///
    /// - Parameter validity: The validity interval in seconds, or `nil` to use automatic
    func setKeyValidity(_ validity: TimeInterval?)

    /// Checks if the key is expired and performs rekeying if necessary.
    func rekeyIfExpired() async
}
