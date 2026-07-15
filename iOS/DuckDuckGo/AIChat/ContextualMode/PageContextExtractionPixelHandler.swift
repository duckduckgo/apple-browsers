//
//  PageContextExtractionPixelHandler.swift
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

import AIChat
import Core
import Foundation

/// Maps a platform-agnostic `PageContextExtractionOutcome` to the iOS extraction-telemetry pixels.
/// Injected into `AIChatPageContextHandler` so the mapping is unit-testable and the firing
/// side-effect can be stubbed in tests. Mirrors the macOS `PageContextExtractionPixelHandler`.
protocol PageContextExtractionPixelFiring {
    func fire(_ outcome: PageContextExtractionOutcome,
              trigger: PageContextExtractionTrigger,
              latency: PageContextExtractionLatencyBucket?)
}

final class PageContextExtractionPixelHandler: PageContextExtractionPixelFiring {

    private let firePixel: (Pixel.Event, [String: String]) -> Void

    /// - Parameter firePixel: fires the mapped pixel + params. Defaults to a daily+count `DailyPixel` fire.
    init(firePixel: @escaping (Pixel.Event, [String: String]) -> Void = { DailyPixel.fireDailyAndCount(pixel: $0, withAdditionalParameters: $1) }) {
        self.firePixel = firePixel
    }

    func fire(_ outcome: PageContextExtractionOutcome,
              trigger: PageContextExtractionTrigger,
              latency: PageContextExtractionLatencyBucket?) {
        switch outcome {
        case .success:
            // Mirrors macOS: the success pixel carries no discriminating params.
            firePixel(.aiChatPageContextExtractionSuccess, [:])
        case .failure(let reason):
            var params = ["reason": reason.rawValue, "trigger": trigger.rawValue]
            if let latency {
                params["latency"] = latency.rawValue
            }
            firePixel(.aiChatPageContextExtractionFailed, params)
        case .prevented(let category):
            firePixel(.aiChatPageContextExtractionPrevented,
                      ["category": category, "reason": "non_attachable", "trigger": trigger.rawValue])
        }
    }
}
