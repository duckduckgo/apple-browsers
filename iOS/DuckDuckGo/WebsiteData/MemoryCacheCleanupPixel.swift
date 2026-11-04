//
//  MemoryCacheCleanupPixel.swift
//  DuckDuckGo
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

import PixelKit

/// Shows how long the deferred memory cache removal takes, and how often iOS suspends the app before it ends.
enum MemoryCacheCleanupPixel: PixelKit.Event {

    case finished(durationMilliseconds: Int, expired: Bool)

    var name: String {
        switch self {
        case .finished: return "fire_memory-cache-cleanup_finished"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .finished(let durationMilliseconds, let expired):
            return ["duration_ms": Self.bucket(milliseconds: durationMilliseconds),
                    "expired": expired ? "true" : "false"]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    /// Inclusive upper bounds in milliseconds; `more` is over 300000.
    static func bucket(milliseconds: Int) -> String {
        let upperBounds = [100, 250, 500, 1000, 2000, 5000, 10000, 30000, 60000, 120000, 300000]
        return upperBounds.first { milliseconds <= $0 }.map(String.init) ?? "more"
    }
}
