//
//  UTISessionMonitor.swift
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

import Foundation
import UIKit

/// Owns the omnibar UTI session lifecycle: the process-global "used both modes" dedupe,
/// per-submission activity metrics, and session finalization on background. Omnibar host only.
@MainActor
final class UTISessionMonitor {

    private(set) static var hasUsedSearchInSession = false
    private(set) static var hasUsedAIChatInSession = false

    static func resetSessionFlags() {
        hasUsedSearchInSession = false
        hasUsedAIChatInSession = false
    }

    private let isEnabled: Bool
    private let metrics: SessionStateMetricsProviding
    private let fireBothModesPixel: () -> Void
    private var backgroundObserver: NSObjectProtocol?

    init(isEnabled: Bool,
         metrics: SessionStateMetricsProviding,
         fireBothModesPixel: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.metrics = metrics
        self.fireBothModesPixel = fireBothModesPixel
    }

    func startObservingBackground() {
        guard isEnabled, backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.metrics.finalizeSession()
                UTISessionMonitor.resetSessionFlags()
            }
        }
    }

    func recordActivity(mode: TextEntryMode) {
        guard isEnabled else { return }
        let previouslyUsedBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession
        switch mode {
        case .search:
            Self.hasUsedSearchInSession = true
            metrics.incrementActivity(.searchSubmitted)
        case .aiChat:
            Self.hasUsedAIChatInSession = true
            metrics.incrementActivity(.promptSubmitted)
        }
        let nowUsesBothModes = Self.hasUsedSearchInSession && Self.hasUsedAIChatInSession
        if nowUsesBothModes && !previouslyUsedBothModes {
            fireBothModesPixel()
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }
}
