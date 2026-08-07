//
//  AITabChromeDecision.swift
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

/// Pure decision for the AI-tab bottom chrome (native chat input bar + voice header pill).
/// Every field is gated on `isOnAITab`: applying these on a non-AI tab causes bar-positioning
/// glitches, so the gate is a real invariant, not a formality.
struct AITabChromeDecision: Equatable {
    let hidesInputBar: Bool
    let voiceChromeActive: Bool

    /// Value-only inputs, so the decision is pure and its tests need no mocks.
    struct Inputs: Equatable {
        let isOnAITab: Bool
        let isAIChatInputHiddenByFrontend: Bool
        let isVoiceSessionActive: Bool
    }

    static func resolve(_ inputs: Inputs) -> AITabChromeDecision {
        AITabChromeDecision(
            hidesInputBar: inputs.isOnAITab && inputs.isAIChatInputHiddenByFrontend,
            voiceChromeActive: inputs.isOnAITab && inputs.isVoiceSessionActive
        )
    }
}
