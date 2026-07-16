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

enum UncleanExitRestartSource: String {
    // New crash reported since last launch checkpoint (Sparkle only)
    case crash = "crash"
    // Pending update snapshot captured at shutdown (Sparkle only)
    case appUpdate = "app_update"
    // Unclean exit with unknown cause; version changed since last launch (App Store only)
    case unknownWithAppUpdate = "unknown_with_app_update"
    // No identified source for the restart
    case unknown = "unknown"
}

/**
 * This enum keeps pixels related to the session restore prompt when the app was closed unexpectedly.
 *
 * See macOS/PixelDefinitions/pixels/session_restore_prompt_pixels.json5 for more details.
 */
enum SessionRestorePromptPixel: PixelKitEvent {
    case unexpectedAppTerminationDetected(reason: UncleanExitRestartSource)
    case promptShown
    case promptDismissedWithoutRestore
    case promptDismissedWithRestore
    case appTerminatedWhilePromptShowing
    case appTerminationFlagReadFailed
    case appTerminationFlagWriteFailed

    var name: String {
        switch self {
        case .unexpectedAppTerminationDetected: return "m_mac_unclean-exit_detected"
        case .promptShown: return "m_mac_unclean-exit_popup_shown"
        case .promptDismissedWithoutRestore: return "m_mac_unclean-exit_popup_dismissed_without-restore"
        case .promptDismissedWithRestore: return "m_mac_unclean-exit_popup_dismissed_with-restore"
        case .appTerminatedWhilePromptShowing: return "m_mac_unclean-exit_popup_browser-closed"
        case .appTerminationFlagReadFailed: return "unclean-exit_flag-read-failed"
        case .appTerminationFlagWriteFailed: return "unclean-exit_flag-write-failed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .unexpectedAppTerminationDetected(let reason):
            return ["restart-source-attribution": reason.rawValue]
        case .promptShown,
                .promptDismissedWithoutRestore,
                .promptDismissedWithRestore,
                .appTerminatedWhilePromptShowing,
                .appTerminationFlagReadFailed,
                .appTerminationFlagWriteFailed:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .unexpectedAppTerminationDetected,
                .promptShown,
                .promptDismissedWithoutRestore,
                .promptDismissedWithRestore,
                .appTerminatedWhilePromptShowing,
                .appTerminationFlagReadFailed,
                .appTerminationFlagWriteFailed:
            return [.pixelSource]
        }
    }
}
