//
//  DevicePlatform.swift
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
import SwiftUI

public enum DevicePlatform {
    public static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    public static var isIpad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    public static var isIphone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    public static var formFactor: String {
        switch true {
        case isMac:
            return "desktop"
        case isIpad:
            return "tablet"
        case isIphone:
            return "phone"
        default:
            return "unknown"
        }
    }
}
