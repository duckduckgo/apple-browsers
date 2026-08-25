//
//  AIChatFullModeFeature.swift
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

import Common

/// Provides access to full Duck AI chat mode availability.
protocol AIChatFullModeFeatureProviding {
    /// Whether Duck AI full chat mode is available on this device.
    ///
    /// Returns `true` when the device is running on an iPhone (not iPad or other devices).
    var isAvailable: Bool { get }
}

/// Determines availability of Duck AI's full chat mode feature.
struct AIChatFullModeFeature: AIChatFullModeFeatureProviding {

    private let devicePlatform: DevicePlatformProviding.Type

    /// Initializes with dependencies.
    ///
    /// - Parameters:
    ///   - devicePlatform: The device platform provider. Defaults to the actual `DevicePlatform`.
    init(devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.devicePlatform = devicePlatform
    }

    /// Whether Duck AI full chat mode is available.
    var isAvailable: Bool {
        devicePlatform.isIphone
    }
}
