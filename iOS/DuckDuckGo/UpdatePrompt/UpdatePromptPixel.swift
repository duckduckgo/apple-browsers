//
//  UpdatePromptPixel.swift
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
import PixelKit

/// The update prompt's funnel, per reminder step.
enum UpdatePromptPixel: PixelKit.Event, Equatable {
    case shown(UpdatePromptStep)
    case updateTapped(UpdatePromptStep)
    case dismissed(UpdatePromptStep)

    var name: String {
        switch self {
        case .shown: "update-prompt_shown"
        case .updateTapped: "update-prompt_update-tapped"
        case .dismissed: "update-prompt_dismissed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .shown(let step), .updateTapped(let step), .dismissed(let step):
            ["step": step.pixelValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
