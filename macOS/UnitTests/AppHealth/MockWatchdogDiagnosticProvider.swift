//
//  MockWatchdogDiagnosticProvider.swift
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

@testable import DuckDuckGo_Privacy_Browser

/// Mock implementation of WatchdogDiagnosticProvider for testing
///
@MainActor
final class MockWatchdogDiagnosticProvider: WatchdogDiagnosticProvider {

    var diagnosticsToReturn: WatchdogDiagnostics = WatchdogDiagnostics(
        isInForeground: nil,
        isAnyWindowVisible: nil,
        isOnBattery: nil,
        openBrowserWindowCount: nil,
        openBrowserTabCount: nil
    )

    var collectDiagnosticsCallCount = 0
    var lastEvent: Watchdog.Event?

    /// Callback that gets called when collectDiagnostics is invoked
    var onDiagnosticsCollected: (() -> Void)?

    func collectDiagnostics(for event: Watchdog.Event) async -> WatchdogDiagnostics {
        collectDiagnosticsCallCount += 1
        lastEvent = event

        onDiagnosticsCollected?()

        return diagnosticsToReturn
    }

    func reset() {
        collectDiagnosticsCallCount = 0
        lastEvent = nil
        onDiagnosticsCollected = nil
        diagnosticsToReturn = WatchdogDiagnostics(
            isInForeground: nil,
            isAnyWindowVisible: nil,
            isOnBattery: nil,
            openBrowserWindowCount: nil,
            openBrowserTabCount: nil
        )
    }
}
