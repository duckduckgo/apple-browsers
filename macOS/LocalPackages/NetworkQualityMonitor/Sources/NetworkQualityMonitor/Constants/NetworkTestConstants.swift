//
//  NetworkTestConstants.swift
//  NetworkQualityMonitor
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

/// Shared constants used across multiple NetworkQualityMonitor services
public enum NetworkTestConstants {
    
    
    // MARK: - Shared Timing Constants
    
    enum Timing {
        static let nanosPerMillisecond: UInt64 = 1_000_000
        static let nanosPerSecond: UInt64 = 1_000_000_000
        static let millisPerSecond: Double = 1000
        static let megabitsPerByte: Double = 8.0 / 1_000_000
        
        // Sleep durations in nanoseconds
        static let measurementDelay: UInt64 = 50_000_000  // 50ms
        static let baselineSampleDelay: UInt64 = 100_000_000  // 100ms
        static let downloadStartDelay: UInt64 = 500_000_000  // 500ms
    }
}