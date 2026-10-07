//
//  SyncCameraPermissionPixel.swift
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

import AVFoundation
import PixelKit

enum SyncCameraPermissionPixel: PixelKit.Event {

    case promptResult(granted: Bool)

    var name: String {
        switch self {
        case .promptResult:
            return "sync_setup_camera_permission_prompt_result"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .promptResult(let granted):
            return ["result": granted ? "granted" : "denied"]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

enum SyncCameraPermissionPixelValue: String {
    static let parameterKey = "camera_permission"

    case authorized
    case notDetermined = "not_determined"
    case denied

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .notDetermined:
            self = .notDetermined
        case .denied, .restricted:
            self = .denied
        @unknown default:
            self = .denied
        }
    }
}
