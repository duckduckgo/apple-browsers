//
//  SessionRestorePromptPixel.swift
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

import PixelKit

/**
 * This enum keeps pixels related to the session restore prompt when the app was closed unexpectedly.
 *
 * See macOS/PixelDefinitions/pixels/session_restore_prompt_pixels.json5 for more details.
 */
enum SessionRestorePromptPixel: PixelKitEvent {
    case unexpectedAppTerminationDetected
    case promptShown
    case promptDismissedWithoutRestore
    case promptDismissedWithRestore
    case appTerminatedWhilePromptShowing

    var name: String {
        switch self {
        case .unexpectedAppTerminationDetected: return "m_mac_unclean-exit_detected"
        case .promptShown: return "m_mac_unclean-exit_popup_shown"
        case .promptDismissedWithoutRestore: return "m_mac_unclean-exit_popup_dismissed_without-restore"
        case .promptDismissedWithRestore: return "m_mac_unclean-exit_popup_dismissed_with-restore"
        case .appTerminatedWhilePromptShowing: return "m_mac_unclean-exit_popup_browser-closed"
        }
    }

    var parameters: [String: String]? {
        nil
    }
}
