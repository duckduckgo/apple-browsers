//
//  AIChatFunnelState.swift
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

/// Protocol for managing state of user progression through the Discovery & Adoption Funnel for experimental omnibar
protocol AIChatFunnelStateProviding {
    // MARK: - State Checking
    var hasEverViewedSettings: Bool { get }
    var hasEverEnabledFeature: Bool { get }
    var hasEverInteractedAfterEnable: Bool { get }
    var hasEverSubmittedSearch: Bool { get }
    var hasEverSubmittedPrompt: Bool { get }
    var hasAchievedFullConversion: Bool { get }
    var lastKnownEnabledState: Bool { get }
    
    // MARK: - State Setting
    func markFirstSettingsView()
    func markFirstFeatureEnable()
    func markFirstInteraction()
    func markFirstSearchSubmission()
    func markFirstPromptSubmission()
    func markFullConversion()
    
    // MARK: - Reset All Storage
    func resetAllFunnelState()
    
    // MARK: - Enabled State Management
    func updateLastKnownEnabledState(_ enabled: Bool)
}

/// Manages state of user progression through the Discovery & Adoption Funnel for experimental omnibar
struct AIChatFunnelState: AIChatFunnelStateProviding {
    private let storage: KeyValueStoring
    
    init(storage: KeyValueStoring) {
        self.storage = storage
    }
    
    // MARK: - Private Keys
    private enum Keys {
        static let hasEverViewedSettings = "FunnelTracking.hasEverViewedSettings"
        static let hasEverEnabledFeature = "FunnelTracking.hasEverEnabledFeature"
        static let hasEverInteractedAfterEnable = "FunnelTracking.hasEverInteractedAfterEnable"
        static let hasEverSubmittedSearch = "FunnelTracking.hasEverSubmittedSearch"
        static let hasEverSubmittedPrompt = "FunnelTracking.hasEverSubmittedPrompt"
        static let hasAchievedFullConversion = "FunnelTracking.hasAchievedFullConversion"
        static let lastKnownEnabledState = "FunnelTracking.lastKnownEnabledState"
    }
    
    // MARK: - State Checking
    var hasEverViewedSettings: Bool {
        storage.object(forKey: Keys.hasEverViewedSettings) as? Bool ?? false
    }
    
    var hasEverEnabledFeature: Bool {
        storage.object(forKey: Keys.hasEverEnabledFeature) as? Bool ?? false
    }
    
    var hasEverInteractedAfterEnable: Bool {
        storage.object(forKey: Keys.hasEverInteractedAfterEnable) as? Bool ?? false
    }
    
    var hasEverSubmittedSearch: Bool {
        storage.object(forKey: Keys.hasEverSubmittedSearch) as? Bool ?? false
    }
    
    var hasEverSubmittedPrompt: Bool {
        storage.object(forKey: Keys.hasEverSubmittedPrompt) as? Bool ?? false
    }
    
    var hasAchievedFullConversion: Bool {
        storage.object(forKey: Keys.hasAchievedFullConversion) as? Bool ?? false
    }
    
    var lastKnownEnabledState: Bool {
        storage.object(forKey: Keys.lastKnownEnabledState) as? Bool ?? false
    }
    
    // MARK: - State Setting
    func markFirstSettingsView() {
        storage.set(true, forKey: Keys.hasEverViewedSettings)
    }
    
    func markFirstFeatureEnable() {
        storage.set(true, forKey: Keys.hasEverEnabledFeature)
    }
    
    func markFirstInteraction() {
        storage.set(true, forKey: Keys.hasEverInteractedAfterEnable)
    }
    
    func markFirstSearchSubmission() {
        storage.set(true, forKey: Keys.hasEverSubmittedSearch)
    }
    
    func markFirstPromptSubmission() {
        storage.set(true, forKey: Keys.hasEverSubmittedPrompt)
    }
    
    func markFullConversion() {
        storage.set(true, forKey: Keys.hasAchievedFullConversion)
    }
    
    // MARK: - Reset All Storage
    func resetAllFunnelState() {
        storage.removeObject(forKey: Keys.hasEverViewedSettings)
        storage.removeObject(forKey: Keys.hasEverEnabledFeature)
        storage.removeObject(forKey: Keys.hasEverInteractedAfterEnable)
        storage.removeObject(forKey: Keys.hasEverSubmittedSearch)
        storage.removeObject(forKey: Keys.hasEverSubmittedPrompt)
        storage.removeObject(forKey: Keys.hasAchievedFullConversion)
        storage.removeObject(forKey: Keys.lastKnownEnabledState)
    }
    
    // MARK: - Enabled State Management
    func updateLastKnownEnabledState(_ enabled: Bool) {
        storage.set(enabled, forKey: Keys.lastKnownEnabledState)
    }
}
