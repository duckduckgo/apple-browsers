//
//  SyncSetupAuthenticationPixel.swift
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
import SyncUI_iOS

enum SyncSetupAuthenticationPixel: PixelKit.Event {

    case result(SyncSettingsViewModel.SetupAuthenticationResult, source: SyncSettingsViewModel.SetupAuthenticationSource)

    var name: String {
        switch self {
        case .result: return "sync_setup_authentication_result"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .result(let result, let source):
            return ["result": result.rawValue, "source": source.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
