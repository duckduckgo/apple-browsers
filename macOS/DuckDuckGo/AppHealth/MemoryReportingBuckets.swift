//
//  MemoryReportingBuckets.swift
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

/// Provides bucketing functions for memory usage reporting context parameters.
///
/// Each function maps a raw value to the nearest lower bucket boundary, matching
/// the Windows browser pixel definitions for cross-platform consistency.
///
enum MemoryReportingBuckets {

    /// Memory usage buckets in megabytes.
    /// Maps a memory value to: 0, 512, 1024, 2048, 4096, 8192, or 16384.
    static func bucketMemoryMB(_ value: Double) -> Int {
        switch Int(value) {
        case ..<512:
            return 0
        case 512..<1024:
            return 512
        case 1024..<2048:
            return 1024
        case 2048..<4096:
            return 2048
        case 4096..<8192:
            return 4096
        case 8192..<16384:
            return 8192
        default:
            return 16384
        }
    }

    /// Window count buckets.
    /// Maps a count to: 0, 1, 2, 4, 7, 11, or 21.
    static func bucketWindowCount(_ count: Int) -> Int {
        switch count {
        case ..<1:
            return 0
        case 1:
            return 1
        case 2..<4:
            return 2
        case 4..<7:
            return 4
        case 7..<11:
            return 7
        case 11..<21:
            return 11
        default:
            return 21
        }
    }

    /// Standard (unpinned) tab count buckets.
    /// Maps a count to: 0, 1, 2, 4, 7, 11, 21, or 51.
    static func bucketStandardTabCount(_ count: Int) -> Int {
        switch count {
        case ..<1:
            return 0
        case 1:
            return 1
        case 2..<4:
            return 2
        case 4..<7:
            return 4
        case 7..<11:
            return 7
        case 11..<21:
            return 11
        case 21..<51:
            return 21
        default:
            return 51
        }
    }

    /// Pinned tab count buckets.
    /// Maps a count to: 0, 1, 2, 4, 7, 11, or 15.
    static func bucketPinnedTabCount(_ count: Int) -> Int {
        switch count {
        case ..<1:
            return 0
        case 1:
            return 1
        case 2..<4:
            return 2
        case 4..<7:
            return 4
        case 7..<11:
            return 7
        case 11..<15:
            return 11
        default:
            return 15
        }
    }

    /// Used allocation buckets in megabytes.
    /// Maps a value to: 0, 64, 128, 256, 512, 1024, 2048, 4096, 8192, or 16384.
    static func bucketUsedAllocationMB(_ value: Double) -> Int {
        switch Int(value) {
        case ..<64:
            return 0
        case 64..<128:
            return 64
        case 128..<256:
            return 128
        case 256..<512:
            return 256
        case 512..<1024:
            return 512
        case 1024..<2048:
            return 1024
        case 2048..<4096:
            return 2048
        case 4096..<8192:
            return 4096
        case 8192..<16384:
            return 8192
        default:
            return 16384
        }
    }

    /// WebContent total memory buckets in megabytes.
    /// Maps a value to: 0, 512, 1024, 2048, 4096, 8192, 16384, 32768, or 65536.
    static func bucketWebContentMemoryMB(_ value: Double) -> Int {
        switch Int(value) {
        case ..<512:
            return 0
        case 512..<1024:
            return 512
        case 1024..<2048:
            return 1024
        case 2048..<4096:
            return 2048
        case 4096..<8192:
            return 4096
        case 8192..<16384:
            return 8192
        case 16384..<32768:
            return 16384
        case 32768..<65536:
            return 32768
        default:
            return 65536
        }
    }

    /// Returns the architecture of the current build.
    static var currentArchitecture: String {
        #if arch(arm64)
        return "ARM"
        #else
        return "Intel"
        #endif
    }
}
