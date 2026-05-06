//
//  AddressBarPerfPixel.swift
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
/// Each interaction emits up to two pixels — one per stage — carrying a 9-band basis-points
/// histogram of latency measurements. Schemas are identical to the Windows counterparts so
/// the dashboard can run the same query logic per platform.
enum AddressBarPerfPixel: PixelKitEvent {

    private enum ParameterNames {
        static let bp_0_16     = "bp_0_16"
        static let bp_16_50    = "bp_16_50"
        static let bp_50_100   = "bp_50_100"
        static let bp_100_150  = "bp_100_150"
        static let bp_150_200  = "bp_150_200"
        static let bp_200_300  = "bp_200_300"
        static let bp_300_500  = "bp_300_500"
        static let bp_500_1000 = "bp_500_1000"
        static let bp_1000_plus = "bp_1000_plus"
    }

    /// Char-render histogram for one address-bar interaction (one band-share per parameter).
    case charRender(basisPoints: [Int])
    /// Suggest-settle histogram for one address-bar interaction (one band-share per parameter).
    case suggestSettle(basisPoints: [Int])

    var name: String {
        switch self {
        case .charRender:
            return "m_mac_address-bar_char-render-perf"
        case .suggestSettle:
            return "m_mac_address-bar_suggest-settle-perf"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .charRender(let basisPoints), .suggestSettle(let basisPoints):
            return Self.histogramParameters(basisPoints)
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }

    private static func histogramParameters(_ basisPoints: [Int]) -> [String: String] {
        precondition(basisPoints.count == AddressBarPerfBucketing.bandCount,
                     "Histogram must have exactly \(AddressBarPerfBucketing.bandCount) bands")
        return [
            ParameterNames.bp_0_16:      String(basisPoints[0]),
            ParameterNames.bp_16_50:     String(basisPoints[1]),
            ParameterNames.bp_50_100:    String(basisPoints[2]),
            ParameterNames.bp_100_150:   String(basisPoints[3]),
            ParameterNames.bp_150_200:   String(basisPoints[4]),
            ParameterNames.bp_200_300:   String(basisPoints[5]),
            ParameterNames.bp_300_500:   String(basisPoints[6]),
            ParameterNames.bp_500_1000:  String(basisPoints[7]),
            ParameterNames.bp_1000_plus: String(basisPoints[8])
        ]
    }
}
