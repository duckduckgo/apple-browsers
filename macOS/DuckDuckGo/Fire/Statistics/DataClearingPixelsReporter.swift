//
//  DataClearingPixelsReporter.swift
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
import QuartzCore
import PixelKit

final class DataClearingPixelsReporter {

    var timeProvider: () -> CFTimeInterval
    private let pixelFiring: PixelFiring?

    @MainActor
    private var lastFireTime: CFTimeInterval?
    private let retriggerWindow: TimeInterval = 20.0

    enum BurnPath: String {
        case burnEntity = "burn_entity"
        case burnAll = "burn_all"
        case burnVisits =  "burn_visits"
    }

    init(pixelFiring: PixelFiring? = PixelKit.shared, timeProvider: @escaping () -> CFTimeInterval = { CACurrentMediaTime() }) {
        self.pixelFiring = pixelFiring
        self.timeProvider = timeProvider
    }

    // MARK: - Overall Flow Measurement

    func fireCompletionPixel(from startTime: CFTimeInterval,
                             dialogResult: FireDialogResult,
                             path: BurnPath,
                             autoClear: Bool) {
        pixelFiring?.fire(
            DataClearingPixels.fireCompletion(
                duration: prepareDuration(from: startTime, to: timeProvider()),
                option: prepare(dialogResult.clearingOption),
                domains: prepare(dialogResult),
                path: path.rawValue,
                autoClear: String(autoClear)
            ),
            frequency: .standard
        )
    }

    @MainActor
    func fireRetriggerPixelIfNeeded() {
        let now = timeProvider()
        if let lastFire = lastFireTime, (now - lastFire) <= retriggerWindow {
            pixelFiring?.fire(DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        }
        lastFireTime = now
    }

    // MARK: - Per-Action Quality Metrics

    func fireDurationPixel(_ durationPixel: @escaping (Int) -> DataClearingPixels,
                           from startTime: CFTimeInterval) {
        pixelFiring?.fire(
            durationPixel(prepareDuration(from: startTime, to: timeProvider())),
            frequency: .standard
        )
    }

    func fireDurationPixel(_ durationPixel: @escaping (String, Int) -> DataClearingPixels,
                           from startTime: CFTimeInterval,
                           entity: String) {
        pixelFiring?.fire(
            durationPixel(entity, prepareDuration(from: startTime, to: timeProvider())),
            frequency: .standard
        )
    }

    func fireResiduePixelIfNeeded(_ residuePixel: DataClearingPixels, check: () -> Bool) {
        if check() {
            pixelFiring?.fire(residuePixel, frequency: .standard)
        }
    }

    func fireResiduePixel(_ residuePixel: DataClearingPixels) {
        pixelFiring?.fire(residuePixel, frequency: .standard)
    }

    func fireErrorPixel(_ errorPixel: DataClearingPixels) {
        pixelFiring?.fire(errorPixel, frequency: .dailyAndStandard)
    }
}

// MARK: - Private Helpers

private extension DataClearingPixelsReporter {

    private func prepareDuration(from startTime: CFTimeInterval, to endTime: CFTimeInterval) -> Int {
        Int((endTime - startTime) * 1000)
    }

    private func prepare(_ result: FireDialogResult) -> String {
        var domains: [String] = []
        if result.includeHistory {
            domains.append("History")
        }
        if result.includeTabsAndWindows {
            domains.append("TabsAndWindows")
        }
        if result.includeCookiesAndSiteData {
            domains.append("CookiesAndSiteData")
        }
        if result.includeChatHistory {
            domains.append("ChatHistory")
        }
        return domains.commaSeparatedString
    }

    private func prepare(_ option: FireDialogViewModel.ClearingOption) -> String {
        option.description
    }

    private static func prepare(_ path: BurnPath) -> String {
        path.rawValue
    }
}

private extension Array where Element == String {
    var commaSeparatedString: String { joined(separator: ",") }
}
