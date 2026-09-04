//
//  PixelUserAgent.swift
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

import Common
import Foundation

/// The `User-Agent` every pixel request carries.
///
/// Lives apart from the pixel-firing code because each process configures PixelKit with its own
/// `fireRequest` closure and they all need this string.
public enum PixelUserAgent {

    public static let `default`: String = {
        // Strip patch version component as per https://app.asana.com/0/69071770703008/1209176655620013/f
        let trimmedOSVersion = AppVersion.shared.osVersionMajorMinor
        return DefaultUserAgentManager.duckduckGoUserAgent(for: AppVersion.shared, osVersion: trimmedOSVersion)
    }()
}
