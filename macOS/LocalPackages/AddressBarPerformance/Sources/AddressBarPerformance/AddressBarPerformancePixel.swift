//
//  AddressBarPerformancePixel.swift
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
import PixelKit

/// Tracks address-bar UI responsiveness for the cross-platform UI responsiveness SLO.
/// Each interaction emits a single pixel carrying two 9-band basis-points histograms — one for
/// char-render latency, one for suggest-render latency — plus a `stages` enum naming which
/// halves carry real data. An interaction that produced no samples for a given stage sends that
/// stage as nine zeros; the `stages` parameter lets the backend filter halves explicitly without
/// having to inspect the histogram sums.
///
/// The Windows counterpart ships two separate pixels with the same per-stage schemas. The
/// macOS divergence is intentional — both stages share trigger, snapshot, and deferred dispatch,
/// so a single pixel halves the network traffic in the case where both stages have data.
/// Backend aggregation accommodates the divergence via a macOS-specific Prefect case.
struct AddressBarPerformancePixel: PixelKitEvent {

    /// Names which halves of the pixel carry real data. A pixel is only emitted when at least one
    /// stage has samples, so a "neither" case is never sent.
    enum Stages: String {
        case character
        case suggestion
        case both
    }

    /// 9-band basis-points histogram of char-render latencies for the interaction, or nine zeros
    /// when no char samples were captured.
    let charBasisPoints: [Int]

    /// 9-band basis-points histogram of suggest-render latencies for the interaction, or nine zeros
    /// when no suggest samples were captured.
    let suggestBasisPoints: [Int]

    /// Names which halves of this pixel carry real data.
    let stages: Stages

    var name: String { "m_mac_address-bar_render-perf" }

    var parameters: [String: String]? {
        var result = Self.histogramParameters(prefix: "character_", basisPoints: charBasisPoints)
        for (key, value) in Self.histogramParameters(prefix: "suggestion_", basisPoints: suggestBasisPoints) {
            result[key] = value
        }
        result["stages"] = stages.rawValue
        return result
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }

    private static func histogramParameters(prefix: String, basisPoints: [Int]) -> [String: String] {
        precondition(basisPoints.count == AddressBarPerformanceBucketing.bandCount,
                     "Histogram must have exactly \(AddressBarPerformanceBucketing.bandCount) bands")
        return [
            "\(prefix)bp_0_16": String(basisPoints[0]),
            "\(prefix)bp_16_50": String(basisPoints[1]),
            "\(prefix)bp_50_100": String(basisPoints[2]),
            "\(prefix)bp_100_150": String(basisPoints[3]),
            "\(prefix)bp_150_200": String(basisPoints[4]),
            "\(prefix)bp_200_300": String(basisPoints[5]),
            "\(prefix)bp_300_500": String(basisPoints[6]),
            "\(prefix)bp_500_1000": String(basisPoints[7]),
            "\(prefix)bp_1000_plus": String(basisPoints[8])
        ]
    }
}
