//
//  AutoconsentManagement.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

final class AutoconsentManagement {

    var sitesNotifiedCache = Set<String>()

    var pixelCounter = [String: Int]()

    var detectedByPatternsCache = Set<String>()
    var detectedByBothCache = Set<String>()
    var detectedOnlyRulesCache = Set<String>()

    private var pendingSummaryTask: DispatchWorkItem?
    private var pendingAdditionalParams: [String: String] = [:]

    func firePixel(pixel: AutoconsentPixel, additionalParameters: [String: String] = [:]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.pixelCounter.isEmpty {
                self.pendingSummaryTask?.cancel()
                self.pendingAdditionalParams = additionalParameters

                let summaryTask = DispatchWorkItem { [weak self] in
                    self?.fireSummaryPixel()
                    self?.pendingSummaryTask = nil
                }
                self.pendingSummaryTask = summaryTask
                DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: summaryTask)
            }

            self.pixelCounter[pixel.key, default: 0] += 1
            PixelKit.fire(pixel, frequency: .daily, withAdditionalParameters: additionalParameters)
        }
    }

    func fireSummaryPixel() {
        guard !pixelCounter.isEmpty else { return }

        PixelKit.fire(AutoconsentPixel.summary(events: pixelCounter),
                      frequency: .standard,
                      withAdditionalParameters: pendingAdditionalParams)
        pixelCounter = [:]
        pendingAdditionalParams = [:]
        detectedByPatternsCache.removeAll()
        detectedByBothCache.removeAll()
        detectedOnlyRulesCache.removeAll()
    }

    func clearCache() {
        dispatchPrecondition(condition: .onQueue(.main))
        sitesNotifiedCache.removeAll()
        detectedByPatternsCache.removeAll()
        detectedByBothCache.removeAll()
        detectedOnlyRulesCache.removeAll()
    }

}
