//
//  UnifiedToggleInputPastedTextPixel.swift
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

import PixelKit

struct UnifiedToggleInputPastedTextPixel: PixelKit.Event {
    enum Action: String {
        case attached
        case removed
        case edited
        case sheetOpened = "sheet_opened"
    }

    enum Surface: String {
        case addressBar = "address_bar"
        case duckAI = "duck_ai"
        case contextualChat = "contextual_chat"
        case iPadOmnibar = "ipad_omnibar"

        init(_ surface: UnifiedToggleInputPixelSurface) {
            switch surface {
            case .addressBar: self = .addressBar
            case .duckAI: self = .duckAI
            case .contextualChat: self = .contextualChat
            }
        }
    }

    let action: Action
    let surface: Surface

    var name: String { "aichat_unified_input_pasted_text_\(action.rawValue)" }
    var parameters: [String: String]? { ["surface": surface.rawValue] }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}
