//
//  CreateImagePixel.swift
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

enum CreateImageEntryPoint: String {
    case toolsMenu = "tools_menu"
    case chatHeaderNewImage = "chat_header_new_image"
}

struct CreateImageModelSwitch: Equatable {
    let fromModelId: String
    let toModelId: String
    let fromModelHasExtraPrivacyProtections: Bool
    let entryPoint: CreateImageEntryPoint
}

enum CreateImagePixel: PixelKit.Event {
    struct SwitchContext: Equatable {
        let surface: UnifiedToggleInputPixelSurface
        let change: CreateImageModelSwitch
    }

    private enum Parameter {
        static let surface = "surface"
        static let fromModelId = "from_model_id"
        static let toModelId = "to_model_id"
        static let fromModelPrivacyPreserving = "from_model_privacy_preserving"
        static let entryPoint = "entry_point"
    }

    case modelSwitched(SwitchContext)
    case modelSwitchNoticeDismissed
    case unavailable

    var name: String {
        switch self {
        case .modelSwitched: return "aichat_unified_input_create_image_model_switched"
        case .modelSwitchNoticeDismissed: return "aichat_unified_input_create_image_model_switch_notice_dismissed"
        case .unavailable: return "aichat_unified_input_create_image_unavailable"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .modelSwitched(let context):
            return [
                Parameter.surface: context.surface.rawValue,
                Parameter.fromModelId: context.change.fromModelId,
                Parameter.toModelId: context.change.toModelId,
                Parameter.fromModelPrivacyPreserving: String(context.change.fromModelHasExtraPrivacyProtections),
                Parameter.entryPoint: context.change.entryPoint.rawValue
            ]
        case .modelSwitchNoticeDismissed, .unavailable:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

protocol CreateImagePixelFiring {
    func modelSwitched(_ change: CreateImageModelSwitch)
    func createImageUnavailable()
    func modelSwitchNoticeDismissed()
}

struct CreateImagePixelAdapter: CreateImagePixelFiring {
    private let firing: UTIPixelFiring
    private let surface: () -> UnifiedToggleInputPixelSurface

    init(firing: UTIPixelFiring = .live, surface: @escaping () -> UnifiedToggleInputPixelSurface) {
        self.firing = firing
        self.surface = surface
    }

    func modelSwitched(_ change: CreateImageModelSwitch) {
        firing.fire(CreateImagePixel.modelSwitched(.init(surface: surface(), change: change)), frequency: .dailyAndCount)
    }

    func createImageUnavailable() {
        firing.fire(CreateImagePixel.unavailable, frequency: .daily)
    }

    func modelSwitchNoticeDismissed() {
        firing.fire(CreateImagePixel.modelSwitchNoticeDismissed, frequency: .dailyAndCount)
    }
}
