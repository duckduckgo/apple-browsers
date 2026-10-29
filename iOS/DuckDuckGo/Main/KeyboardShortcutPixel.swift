//
//  KeyboardShortcutPixel.swift
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

/// Pixels for hardware keyboard shortcut use.
enum KeyboardShortcutPixel: PixelKit.Event {
    case used

    var name: String { "keyboard-shortcut_used" }
    var parameters: [String: String]? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }

    /// Fires `used` once per day.
    static func fireUsed(with pixelFiring: (any PixelKitFiring)?) {
        pixelFiring?.fire(KeyboardShortcutPixel.used, frequency: .daily)
    }
}
