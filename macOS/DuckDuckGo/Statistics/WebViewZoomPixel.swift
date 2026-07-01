//
//  WebViewZoomPixel.swift
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

import AppKit
import Foundation
import PixelKit

enum WebViewZoomEntryPoint: String {
    case keyboard
    case popover
    case menu
    case actualSize = "actual-size"

    /// Infers keyboard vs menu for main menu bar zoom actions (View → Zoom In/Out).
    /// Key equivalents (⌘+/⌘−) arrive with a `keyDown` event; mouse clicks do not.
    static var forMainMenuBarZoomAction: WebViewZoomEntryPoint {
        NSApp.currentEvent?.type == .keyDown ? .keyboard : .menu
    }
}

enum WebViewZoomPixel: PixelKitEvent {

    /// Fired on each page zoom action (zoom in, zoom out, or actual size).
    case zoomChanged(entryPoint: WebViewZoomEntryPoint)

    /// Fired at most once per user per day when any page zoom action occurs.
    case zoomDaily

    var name: String {
        switch self {
        case .zoomChanged:
            return "m_mac_webview_zoom-changed"
        case .zoomDaily:
            return "m_mac_webview_zoom"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .zoomChanged(let entryPoint):
            return ["entry_point": entryPoint.rawValue]
        case .zoomDaily:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }

    static func fire(entryPoint: WebViewZoomEntryPoint) {
        PixelKit.fire(WebViewZoomPixel.zoomChanged(entryPoint: entryPoint), frequency: .standard, includeAppVersionParameter: true)
        PixelKit.fire(WebViewZoomPixel.zoomDaily, frequency: .daily, includeAppVersionParameter: true)
    }
}
