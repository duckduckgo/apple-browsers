//
//  BandwidthAnalyzing.swift
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

/// Protocol abstraction for bandwidth analysis functionality.
///
/// This protocol defines the interface for monitoring network bandwidth usage
/// and determining connection idle state.
///
public protocol BandwidthAnalyzing: Actor {

    /// Records a bandwidth measurement with the provided received and transmitted byte counts.
    ///
    /// - Parameters:
    ///   - rxBytes: Total bytes received
    ///   - txBytes: Total bytes transmitted
    func record(rxBytes: UInt64, txBytes: UInt64)

    /// Prevents the connection from being marked as idle.
    ///
    /// This is useful when external conditions indicate the connection should not be
    /// considered idle, even if bandwidth measurements might suggest otherwise.
    func preventIdle()

    /// Returns whether the connection is currently idle based on bandwidth analysis.
    ///
    /// - Returns: `true` if the connection is idle, `false` otherwise
    func isConnectionIdle() -> Bool

    /// Resets the bandwidth analyzer, clearing all recorded measurements.
    ///
    /// This is typically called when switching servers.
    func reset()
}
