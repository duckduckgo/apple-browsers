//
//  SessionStateMetrics.swift
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

/// Session activity types for switchbar usage
enum SessionActivityType: CaseIterable {
    case searchSubmitted
    case promptSubmitted
}

/// Protocol for managing session state metrics
protocol SessionStateMetricsProviding {
    func incrementActivity(_ activity: SessionActivityType)
    func finalizeSession()
}

/// Manages session state metrics for the switchbar
final class SessionStateMetrics: SessionStateMetricsProviding {
    
    private let storage: KeyValueStoring
    private var searchCount: Int = 0
    private var promptCount: Int = 0
    private let pixelFiring: PixelFiring.Type
    
    init(storage: KeyValueStoring, pixelFiring: PixelFiring.Type = Pixel.self) {
        self.storage = storage
        self.pixelFiring = pixelFiring
    }
    
    func incrementActivity(_ activity: SessionActivityType) {
        switch activity {
        case .searchSubmitted:
            searchCount += 1
        case .promptSubmitted:
            promptCount += 1
        }
    }
    
    func finalizeSession() {
        
        // Only fire pixel if there was any activity
        guard searchCount > 0 || promptCount > 0 else {
            resetSessionCounters()
            return
        }
        
        // Fire session summary pixel
        let parameters = [
            "searches_in_session": String(searchCount),
            "prompts_in_session": String(promptCount)
        ]
        
        pixelFiring.fire(.aiChatExperimentalOmnibarSessionSummary,
                                     withAdditionalParameters: parameters)
        
        resetSessionCounters()
    }
    
    private func resetSessionCounters() {
        searchCount = 0
        promptCount = 0
    }
}
