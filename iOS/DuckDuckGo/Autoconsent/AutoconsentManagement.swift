//
//  AutoconsentManagement.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import UIKit
import PixelKit
import os.log

@MainActor
protocol AutoconsentManaging: AnyObject {
    var sitesNotifiedCache: Set<String> { get set }
    var detectedByPatternsCache: Set<String> { get set }
    var detectedByBothCache: Set<String> { get set }
    var detectedOnlyRulesCache: Set<String> { get set }
    func firePixel(pixel: AutoconsentPixel, additionalParameters: [String: String])
    func clearCache() -> Result<Void, Error>
    func clearCache(forDomains domains: [String]) -> Result<Void, Error>
}

@MainActor
final class AutoconsentManagement: AutoconsentManaging {

    var sitesNotifiedCache = Set<String>()

    var pixelCounter = [String: Int]()

    var detectedByPatternsCache = Set<String>()
    var detectedByBothCache = Set<String>()
    var detectedOnlyRulesCache = Set<String>()

    // Task scheduling for pixel summary
    private var pendingSummaryTask: DispatchWorkItem?
    private var pendingAdditionalParams: [String: String] = [:]

    init() {
        setupNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotificationObservers() {
        // Listen for app termination notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )

        // Also listen for app entering background as a fallback
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appWillTerminate() {
        firePendingSummaryImmediately()
    }

    @objc private func appDidEnterBackground() {
        firePendingSummaryImmediately()
    }

    private func firePendingSummaryImmediately() {
        // Cancel any pending task
        pendingSummaryTask?.cancel()
        pendingSummaryTask = nil

        // Fire summary immediately if there are events
        fireSummaryPixel()
    }

    func firePixel(pixel: AutoconsentPixel, additionalParameters: [String: String] = [:]) {
        // Only schedule summary task if counter is currently empty
        if pixelCounter.isEmpty {
            // Cancel any existing pending task (shouldn't happen but safety first)
            pendingSummaryTask?.cancel()

            // Store additional params for the summary pixel
            pendingAdditionalParams = additionalParameters

            // Create new task for firing summary after 120 seconds
            let summaryTask = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.fireSummaryPixel()
                self.pendingSummaryTask = nil
            }

            // Store reference to the task so we can cancel it if needed
            pendingSummaryTask = summaryTask

            // Schedule the task
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: summaryTask)
        }

        // increment counter
        pixelCounter[pixel.key, default: 0] += 1

        // fire daily pixel if needed
        PixelKit.fire(pixel, frequency: .daily, withAdditionalParameters: additionalParameters, includeAppVersionParameter: true)
    }

    func fireSummaryPixel() {
        if !pixelCounter.isEmpty {
            PixelKit.fire(AutoconsentPixel.summary(events: pixelCounter), frequency: .standard, withAdditionalParameters: pendingAdditionalParams, includeAppVersionParameter: true)
            pixelCounter = [:]
            pendingAdditionalParams = [:]
            detectedByPatternsCache.removeAll()
            detectedByBothCache.removeAll()
            detectedOnlyRulesCache.removeAll()
        }
    }

    func clearCache() -> Result<Void, Error> {
        dispatchPrecondition(condition: .onQueue(.main))
        sitesNotifiedCache.removeAll()
        detectedByPatternsCache.removeAll()
        detectedByBothCache.removeAll()
        detectedOnlyRulesCache.removeAll()
        return .success(())
    }
    
    func clearCache(forDomains domains: [String]) -> Result<Void, Error> {
        dispatchPrecondition(condition: .onQueue(.main))
        let domainSet = Set(domains)

        // sitesNotifiedCache stores hosts directly
        sitesNotifiedCache = sitesNotifiedCache.filter { host in
            !domainSet.contains(where: { domain in
                host == domain || host.hasSuffix(".\(domain)")
            })
        }
        return .success(())
    }

}
