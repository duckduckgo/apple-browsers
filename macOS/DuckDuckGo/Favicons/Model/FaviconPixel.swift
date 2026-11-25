//
//  FaviconPixel.swift
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

/// Pixels of favicon processing.
enum FaviconPixel: PixelKit.Event {

    /// The web content process that renders SVG and PDF favicons (see `FaviconRasterizer`) terminated, whether it
    /// crashed or was killed by the system. The associated error carries `errorCode` and `errorDomain`.
    case svgRenderingProcessTerminated(error: Error)

    var name: String {
        switch self {
        case .svgRenderingProcessTerminated:
            return "favicon-svg-rendering_process-terminated_macos"
        }
    }

    var namePrefix: PixelKitNamePrefix { .none }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
