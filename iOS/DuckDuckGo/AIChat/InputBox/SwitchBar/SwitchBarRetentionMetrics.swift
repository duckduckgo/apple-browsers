//
//  SwitchBarRetentionMetrics.swift
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
import Persistence
import Core
import AIChat

/// Protocol for managing daily retention metrics
protocol SwitchBarRetentionMetricsProviding {
    func checkDailyAndSendPixelIfApplicable()
}

/// Manages daily retention metrics for new omnibar feature
final class SwitchBarRetentionMetrics: SwitchBarRetentionMetricsProviding {
    
    // MARK: - Private Properties
    
    private let storage: KeyValueStoring
    private let pixelFiring: PixelFiring.Type
    private let aiChatSettings: AIChatSettingsProvider
    
    // MARK: - Storage Keys
    
    private enum StorageKey {
        static let lastEnabledState = "SwitchBarRetentionMetrics.lastEnabledState"
        static let lastCheckTimestamp = "SwitchBarRetentionMetrics.lastCheckTimestamp"
    }
    
    // MARK: - Initialization
    
    init(storage: KeyValueStoring = UserDefaults.standard,
         pixelFiring: PixelFiring.Type = Pixel.self,
         aiChatSettings: AIChatSettingsProvider) {
        self.storage = storage
        self.pixelFiring = pixelFiring
        self.aiChatSettings = aiChatSettings
    }
    
    // MARK: - SwitchBarRetentionMetricsProviding
    
    func checkDailyAndSendPixelIfApplicable() {
        let currentTimestamp = Date().timeIntervalSince1970
        let currentlyEnabled = aiChatSettings.isAIChatSearchInputUserSettingsEnabled
        
        // Get stored state
        let lastEnabledState = storage.object(forKey: StorageKey.lastEnabledState) as? Bool
        let lastCheckTimestamp = storage.object(forKey: StorageKey.lastCheckTimestamp) as? Double
        
        // Step 1: First check - no previous state
        guard let previousEnabledState = lastEnabledState,
              let previousTimestamp = lastCheckTimestamp else {
            // First time - just persist current state for tomorrow
            persistCurrentState(enabled: currentlyEnabled, timestamp: currentTimestamp)
            return
        }
        
        // Step 2: 24-hour check
        let twentyFourHoursInSeconds: Double = 24 * 60 * 60
        guard currentTimestamp - previousTimestamp >= twentyFourHoursInSeconds else {
            // Less than 24 hours - do nothing
            return
        }
        
        // Step 3: Eligibility check - was feature enabled during last check?
        guard previousEnabledState else {
            // Feature was disabled last time - persist current state and exit
            persistCurrentState(enabled: currentlyEnabled, timestamp: currentTimestamp)
            return
        }
        
        // Step 4: Fire retention pixel with current enablement state
        let parameters = [
            "still_enabled": currentlyEnabled ? "true" : "false"
        ]
        
        pixelFiring.fire(.aiChatExperimentalOmnibarDailyRetention,
                        withAdditionalParameters: parameters)
        
        // Step 5: Persist current state for next cycle
        persistCurrentState(enabled: currentlyEnabled, timestamp: currentTimestamp)
    }
    
    // MARK: - Private Helpers
    
    private func persistCurrentState(enabled: Bool, timestamp: Double) {
        storage.set(enabled, forKey: StorageKey.lastEnabledState)
        storage.set(timestamp, forKey: StorageKey.lastCheckTimestamp)
    }
}
