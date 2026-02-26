//
//  StartupMetricsReporter.swift
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

import FeatureFlags
import PixelKit
import PrivacyConfig

final class StartupMetricsReporter: StartupProfilerDelegate {

    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let previousSessionRestored: Bool
    private let windowContextProvider: () -> WindowContext
    private let environment: SystemEnvironment

    init(environment: SystemEnvironment = .current, featureFlagger: FeatureFlagger, pixelFiring: PixelFiring?, previousSessionRestored: Bool, windowContext: @autoclosure @escaping () -> WindowContext) {
        self.environment = environment
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.previousSessionRestored = previousSessionRestored
        self.windowContextProvider = windowContext
    }

    func startupProfiler(_ profiler: StartupProfiler, didCompleteWithMetrics metrics: StartupMetrics) {
        guard featureFlagger.isFeatureOn(.startupMetrics), let pixelFiring else {
            return
        }

        Task { @MainActor in
            let pixel = buildMetricsPixel(metrics: metrics, windowContext: windowContextProvider(), environment: environment, previousSessionRestored: previousSessionRestored)
            pixelFiring.fire(pixel, frequency: .standard)
        }
    }
}

// MARK: - Private Helpers

private extension StartupMetricsReporter {

    func buildMetricsPixel(metrics: StartupMetrics, windowContext: WindowContext, environment: SystemEnvironment, previousSessionRestored: Bool) -> StartupMetricsPixel {
        StartupMetricsPixel(
            architecture: environment.architecture,
            activeProcessorCount: environment.activeProcessorCount,
            isOnBattery: environment.isOnBattery,
            sessionRestoration: previousSessionRestored,
            windows: windowContext.windows,
            tabs: windowContext.standardTabs,
            appDelegateInit: metrics.duration(step: .appDelegateInit),
            mainMenuInit: metrics.duration(step: .mainMenuInit),
            appWillFinishLaunching: metrics.duration(step: .appWillFinishLaunching),
            appDidFinishLaunchingBeforeStateRestoration: metrics.duration(step: .appDidFinishLaunchingBeforeRestoration),
            appDidFinishLaunchingAfterStateRestoration: metrics.duration(step: .appDidFinishLaunchingAfterRestoration),
            appStateRestoration: metrics.duration(step: .appStateRestoration),
            initToWillFinishLaunching: metrics.timeElapsedBetween(endOf: .appDelegateInit, startOf: .appWillFinishLaunching),
            appWillFinishToDidFinishLaunching: metrics.timeElapsedBetween(endOf: .appWillFinishLaunching, startOf: .appDidFinishLaunchingBeforeRestoration),
            timeToInteractive: metrics.duration(step: .timeToInteractive)
        )
    }
}
