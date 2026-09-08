//
//  DataImportPermissionPixel.swift
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

/**
 * This enum keeps pixels related to the browser data directory read permission flow (macOS 27+).
 *
 * See macOS/PixelDefinitions/pixels/definitions/data_import_permission_pixels.json5 for more details.
 */
enum DataImportPermissionPixel: PixelKit.Event {
    /// These names are already complete: they carry their own `_macos` marker, so PixelKit must not
    /// prepend `m_mac_` on top of it.
    var namePrefix: PixelKitNamePrefix { .none }

    case directoryPermissionPromptScreenShown(source: String)
    case directoryPermissionGranted(source: String)
    case directoryPermissionDenied(source: String)
    case directoryPermissionCancelled(source: String)
    case directoryPermissionRetryScreenShown(source: String)
    case directoryPermissionErrorScreenShown(source: String)

    var name: String {
        switch self {
        case .directoryPermissionPromptScreenShown: return "dataimport_directory-permission_prompt-screen_shown_macos"
        case .directoryPermissionGranted: return "dataimport_directory-permission_granted_macos"
        case .directoryPermissionDenied: return "dataimport_directory-permission_denied_macos"
        case .directoryPermissionCancelled: return "dataimport_directory-permission_cancelled_macos"
        case .directoryPermissionRetryScreenShown: return "dataimport_directory-permission_retry-screen_shown_macos"
        case .directoryPermissionErrorScreenShown: return "dataimport_directory-permission_error-screen_shown_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .directoryPermissionPromptScreenShown(let source),
                .directoryPermissionGranted(let source),
                .directoryPermissionDenied(let source),
                .directoryPermissionCancelled(let source),
                .directoryPermissionRetryScreenShown(let source),
                .directoryPermissionErrorScreenShown(let source):
            return [Constants.sourceParameter: source]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .directoryPermissionPromptScreenShown,
                .directoryPermissionGranted,
                .directoryPermissionDenied,
                .directoryPermissionCancelled,
                .directoryPermissionRetryScreenShown,
                .directoryPermissionErrorScreenShown:
            return [.pixelSource]
        }
    }

    private enum Constants {
        static let sourceParameter = "source"
    }
}
