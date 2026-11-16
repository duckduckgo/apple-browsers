//
//  DefaultBrowserWinBackPixel.swift
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

/// See definitions in `default-browser-and-dock-prompt-win-back.json5`
enum DefaultBrowserWinBackPixel: PixelKit.Event, Equatable {

    case shown(type: DefaultBrowserAndDockPromptType)
    case confirmButtonClicked(type: DefaultBrowserAndDockPromptType)
    case dismissed(type: DefaultBrowserAndDockPromptType)
    case defaultSetWithoutPromoAction

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .shown:
            return "default-browser-win-back_shown_macos"
        case .confirmButtonClicked:
            return "default-browser-win-back_confirm-action_macos"
        case .dismissed:
            return "default-browser-win-back_cancel-action_macos"
        case .defaultSetWithoutPromoAction:
            return "default-browser-win-back_default-set-without-promo-action_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .shown(let type), .confirmButtonClicked(let type), .dismissed(let type):
            return ["contentType": type.promptTypeDescription]
        case .defaultSetWithoutPromoAction:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}
