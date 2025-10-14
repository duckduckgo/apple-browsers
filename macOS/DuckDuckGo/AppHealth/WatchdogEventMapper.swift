//
//  WatchdogEventMapper.swift
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
import BrowserServicesKit
import Common
import PixelKit
import Darwin

/// Diagnostic information to be included with a hang pixel
///
public struct WatchdogDiagnostics {
    /// Whether the app is currently in the foreground
    public let isInForeground: Bool?

    /// Whether any window is currently visible (not hidden or minimized)
    public let isAnyWindowVisible: Bool?

    /// Whether the device is running on battery power or plugged in
    public let isOnBattery: Bool?

    /// Number of open DDG browser windows
    public let openBrowserWindowCount: Int?

    /// Number of open browser tabs
    public let openBrowserTabCount: Int?
}

/// Protocol for providing diagnostic information to the Watchdog
///
public protocol WatchdogDiagnosticProvider {
    func collectDiagnostics(for event: Watchdog.Event) async -> WatchdogDiagnostics
}

/// EventMapper that converts WatchdogEvents from BrowserServicesKit to HangPixel events
///
public class WatchdogEventMapper: EventMapping<Watchdog.Event> {
    /// Provides diagnostic parameters to be included with the pixel, such as browser window count, whether the device is on battery or plugged in, etc.
    let diagnosticProvider: WatchdogDiagnosticProvider
    private let _pixelKit: PixelKit?
    private var pixelKit: PixelKit? {
        _pixelKit ?? PixelKit.shared
    }

    public init(diagnosticProvider: WatchdogDiagnosticProvider, pixelKit: PixelKit? = nil) {
        self.diagnosticProvider = diagnosticProvider
        self._pixelKit = pixelKit

        super.init { _, _, _, _ in }

        self.eventMapper = { [weak self] event, _, _, onComplete in
            switch event {
            case .uiHangNotRecovered(let durationSeconds):
                Task {
                    guard let self = self else { return }

                    let diagnostics = await self.diagnosticProvider.collectDiagnostics(for: event)
                    let batteryPower = self.getBatteryPower(from: diagnostics)

                    let pixel = HangPixel.uiHangNotRecovered(
                        durationSeconds: durationSeconds,
                        inForeground: diagnostics.isInForeground,
                        anyWindowVisible: diagnostics.isAnyWindowVisible,
                        batteryPower: batteryPower,
                        openBrowserWindowCount: diagnostics.openBrowserWindowCount,
                        openBrowserTabCount: diagnostics.openBrowserTabCount,
                        stackTrace: nil
                    )

                    self.pixelKit?.fire(pixel, frequency: .dailyAndCount) { _, error in
                        onComplete(error)
                    }
                }
            case .uiHangRecovered(let durationSeconds):
                Task {
                    guard let self = self else { return }

                    let diagnostics = await self.diagnosticProvider.collectDiagnostics(for: event)
                    let batteryPower = self.getBatteryPower(from: diagnostics)

                    let pixel = HangPixel.uiHangRecovered(
                        durationSeconds: durationSeconds,
                        inForeground: diagnostics.isInForeground,
                        anyWindowVisible: diagnostics.isAnyWindowVisible,
                        batteryPower: batteryPower,
                        openBrowserWindowCount: diagnostics.openBrowserWindowCount,
                        openBrowserTabCount: diagnostics.openBrowserTabCount,
                        stackTrace: nil
                    )

                    self.pixelKit?.fire(pixel, frequency: .dailyAndCount) { _, error in
                        onComplete(error)
                    }
                }
            }
        }
    }

    private func getBatteryPower(from diagnostics: WatchdogDiagnostics) -> HangPixel.BatteryPower? {
        guard let onBattery = diagnostics.isOnBattery else {
            return nil
        }

        return onBattery ? .onBattery : .pluggedIn
    }
}
