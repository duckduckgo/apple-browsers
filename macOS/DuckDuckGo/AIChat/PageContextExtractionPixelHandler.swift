//
//  PageContextExtractionPixelHandler.swift
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
import Foundation
import PixelKit

protocol PageContextExtractionPixelFiring {
    func fire(_ outcome: PageContextExtractionOutcome,
              trigger: PageContextExtractionTrigger,
              latency: PageContextExtractionLatencyBucket?)
}

final class PageContextExtractionPixelHandler: PageContextExtractionPixelFiring {

    private let firePixel: (AIChatPixel) -> Void

    init(firePixel: @escaping (AIChatPixel) -> Void = { PixelKit.fire($0, frequency: .dailyAndCount) }) {
        self.firePixel = firePixel
    }

    func fire(_ outcome: PageContextExtractionOutcome,
              trigger: PageContextExtractionTrigger,
              latency: PageContextExtractionLatencyBucket?) {
        switch outcome {
        case .success:
            firePixel(.aiChatPageContextExtractionSuccess)
        case .failure(let reason):
            firePixel(.aiChatPageContextExtractionFailed(reason: reason.rawValue, trigger: trigger.rawValue, latency: latency?.rawValue))
        case .prevented(let category):
            firePixel(.aiChatPageContextExtractionPrevented(category: category, trigger: trigger.rawValue))
        }
    }
}
