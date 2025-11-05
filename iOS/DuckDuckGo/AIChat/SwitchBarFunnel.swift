//
//  SwitchBarFunnel.swift
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

/// Funnel step definition with dependencies and pixel information
enum SwitchBarFunnelStep: CaseIterable {
    case settingsViewed
    case featureEnabled
    case firstInteraction
    case searchSubmitted
    case promptSubmitted
    case fullConversion
    
    var storageKey: String {
        switch self {
        case .settingsViewed: return "SwitchBarFunnelStep.hasEverViewedSettings"
        case .featureEnabled: return "SwitchBarFunnelStep.hasEverEnabledFeature"
        case .firstInteraction: return "SwitchBarFunnelStep.hasEverInteractedAfterEnable"
        case .searchSubmitted: return "SwitchBarFunnelStep.hasEverSubmittedSearch"
        case .promptSubmitted: return "SwitchBarFunnelStep.hasEverSubmittedPrompt"
        case .fullConversion: return "SwitchBarFunnelStep.hasAchievedFullConversion"
        }
    }
    
    var pixelEvent: Pixel.Event {
        switch self {
        case .settingsViewed: return .aiChatExperimentalOmnibarFirstSettingsViewed
        case .featureEnabled: return .aiChatExperimentalOmnibarFirstEnabled
        case .firstInteraction: return .aiChatExperimentalOmnibarFirstInteraction
        case .searchSubmitted: return .aiChatExperimentalOmnibarFirstSearchSubmission
        case .promptSubmitted: return .aiChatExperimentalOmnibarFirstPromptSubmission
        case .fullConversion: return .aiChatExperimentalOmnibarFullConversionUser
        }
    }
    
    var dependencies: Set<SwitchBarFunnelStep> {
        switch self {
        case .settingsViewed: return []
        case .featureEnabled: return [.settingsViewed]
        case .firstInteraction: return [.featureEnabled]
        case .searchSubmitted: return [.firstInteraction]
        case .promptSubmitted: return [.firstInteraction]
        case .fullConversion: return [.searchSubmitted, .promptSubmitted]
        }
    }
}

/// Protocol for managing state of user progression through the Discovery & Adoption Funnel for experimental switchbar
protocol SwitchBarFunnelProviding {
    func processStep(_ step: SwitchBarFunnelStep)
    func resetAllFunnelState()
}

/// Manages state of user progression through the Discovery & Adoption Funnel for experimental switchbar
struct SwitchBarFunnel: SwitchBarFunnelProviding {
    private let storage: KeyValueStoring
    
    init(storage: KeyValueStoring) {
        self.storage = storage
    }
    
    func processStep(_ step: SwitchBarFunnelStep) {
        // Check if step already completed
        let stepCompleted = storage.object(forKey: step.storageKey) as? Bool ?? false
        guard !stepCompleted else { return }
        
        // Check if all dependencies are satisfied
        let dependenciesSatisfied = step.dependencies.allSatisfy { dependency in
            storage.object(forKey: dependency.storageKey) as? Bool ?? false
        }
        
        guard dependenciesSatisfied else { return }
        
        // Mark step as completed and fire pixel
        storage.set(true, forKey: step.storageKey)
        Pixel.fire(pixel: step.pixelEvent)
        
        // Check for full conversion after each step
        checkForFullConversion()
    }
    
    func resetAllFunnelState() {
        for step in SwitchBarFunnelStep.allCases {
            storage.removeObject(forKey: step.storageKey)
        }
    }
    
    private func checkForFullConversion() {
        let fullConversionStep = SwitchBarFunnelStep.fullConversion
        let alreadyConverted = storage.object(forKey: fullConversionStep.storageKey) as? Bool ?? false
        
        guard !alreadyConverted else { return }
        
        let conversionDependenciesSatisfied = fullConversionStep.dependencies.allSatisfy { dependency in
            storage.object(forKey: dependency.storageKey) as? Bool ?? false
        }
        
        if conversionDependenciesSatisfied {
            storage.set(true, forKey: fullConversionStep.storageKey)
            Pixel.fire(pixel: fullConversionStep.pixelEvent)
        }
    }
}
