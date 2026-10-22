//
//  DuckAIUsageContextPixel.swift
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

/// Daily usage context, sent apart from the settings snapshot so the two can't be combined into a finer profile.
struct DuckAIUsageContextPixel: PixelKit.Event {

    let usageContext: UsageContext
    let windowMode: UsageContext.WindowMode

    var name: String { "aichat_usage_context" }

    var parameters: [String: String]? {
        usageContext.parameters.merging([UsageContext.ParameterName.windowMode: windowMode.rawValue]) { $1 }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

@MainActor
struct DuckAIUsageContextPixelReporter {

    private let usageContextProvider: UsageContextProviding
    private let pixelFiring: PixelFiring?

    init(usageContextProvider: UsageContextProviding, pixelFiring: PixelFiring? = PixelKit.shared) {
        self.usageContextProvider = usageContextProvider
        self.pixelFiring = pixelFiring
    }

    func fireDaily() {
        pixelFiring?.fire(currentContext, frequency: .daily)
    }

    var currentContext: DuckAIUsageContextPixel {
        DuckAIUsageContextPixel(usageContext: usageContextProvider.currentContext,
                                windowMode: usageContextProvider.currentWindowMode)
    }
}
