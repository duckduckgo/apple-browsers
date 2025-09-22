//
//  WidePixelFailureEvent.swift
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
import Common

public enum WidePixelFailureEvent {
    public static let eventMapping: EventMapping<WidePixelFailureEvent> = .init { event, _, _, _ in
        PixelKit.shared?.fire(event, frequency: .dailyAndCount)
    }

    case saveFailed(pixelName: String, error: Error)
    case updateFailed(pixelName: String, error: Error)
    case loadFailed(pixelName: String, error: Error)
    case completionFailed(pixelName: String, error: Error)
    case discardFailed(pixelName: String, error: Error)
}

extension WidePixelFailureEvent: PixelKitEvent, PixelKitEventWithCustomPrefix {
    public var namePrefix: String {
#if os(macOS)
        return "m_mac_"
#elseif os(iOS)
        return "m_"
#endif
    }

    public var name: String {
        switch self {
        case .saveFailed: return "wide_pixel_save_failed"
        case .updateFailed: return "wide_pixel_update_failed"
        case .loadFailed: return "wide_pixel_load_failed"
        case .completionFailed: return "wide_pixel_completion_failed"
        case .discardFailed: return "wide_pixel_discard_failed"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .saveFailed(let pixelName, _),
                .updateFailed(let pixelName, _),
                .loadFailed(let pixelName, _),
                .completionFailed(let pixelName, _),
                .discardFailed(let pixelName, _): return ["pixelName": pixelName]
        }
    }
}
