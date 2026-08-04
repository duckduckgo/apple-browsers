//
//  BookmarksPixel.swift
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

/**
 * This enum keeps pixels related to Bookmarks.
 */
enum BookmarksPixel: PixelKitEvent {
    /**
     * Event Trigger: Bookmark data finishes loading successfully.
     *
     * > Note: This is a daily pixel. The exact bookmark count is never sent; it is mapped to a privacy-preserving bucket.
     *
     * Anomaly Investigation:
     * - An anomaly may indicate a change in the distribution of bookmark counts or an issue loading or reporting bookmarks.
     */
    case count(BookmarksCountBucket)

    // MARK: -

    var name: String {
        switch self {
        case .count: return "bookmarks_count"
        }
    }

    var frequency: PixelKit.Frequency {
        switch self {
        case .count: return .daily
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .count(let bucket):
            return [ParameterKey.bookmarksCountBucket.rawValue: bucket.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .count:
            return [.pixelSource]
        }
    }

    // MARK: - Nested Types

    private enum ParameterKey: String {
        case bookmarksCountBucket = "bookmarks_count_bucket"
    }

    enum BookmarksCountBucket: String, CaseIterable {
        case zero = "0"
        case oneToTen = "1-10"
        case elevenToFifty = "11-50"
        case fiftyOneToOneHundred = "51-100"
        case oneHundredOneToFiveHundred = "101-500"
        case fiveHundredOneOrMore = "501+"

        init(_ bookmarksCount: Int) {
            switch bookmarksCount {
            case ..<1:
                self = .zero
            case 1...10:
                self = .oneToTen
            case 11...50:
                self = .elevenToFifty
            case 51...100:
                self = .fiftyOneToOneHundred
            case 101...500:
                self = .oneHundredOneToFiveHundred
            default:
                self = .fiveHundredOneOrMore
            }
        }
    }
}

extension BookmarksPixel {
    func fire(pixelFiring: PixelFiring? = PixelKit.shared) {
        pixelFiring?.fire(self, frequency: frequency)
    }
}
