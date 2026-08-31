//
//  UserText.swift
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

import Foundation

enum UserText {

    enum PermissionDialog {
        static func cameraTitle(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.dialog.camera.title", bundle: Bundle.module,
                                           value: "“%@” website wants to access your camera",
                                           comment: "Title shown when a website asks to use the camera. The placeholder is the website domain.")
            return String(format: format, domain)
        }

        static func microphoneTitle(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.dialog.microphone.title", bundle: Bundle.module,
                                           value: "“%@” website wants to access the microphone",
                                           comment: "Title shown when a website asks to use the microphone. The placeholder is the website domain.")
            return String(format: format, domain)
        }

        static func cameraAndMicrophoneTitle(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.dialog.camera-and-microphone.title", bundle: Bundle.module,
                                           value: "“%@” website wants to access your camera and microphone",
                                           comment: "Title shown when a website asks to use the camera and microphone. The placeholder is the website domain.")
            return String(format: format, domain)
        }

        static let allowOnce = NSLocalizedString("sitePermissions.dialog.allow-once", bundle: Bundle.module,
                                                 value: "Allow Once",
                                                 comment: "Button that grants a website permission until the page changes.")
        static let allowWhileUsingSite = NSLocalizedString("sitePermissions.dialog.allow-while-using-site", bundle: Bundle.module,
                                                           value: "Allow While Using Site",
                                                           comment: "Button that always grants a website permission.")
        static let neverAllow = NSLocalizedString("sitePermissions.dialog.never-allow", bundle: Bundle.module,
                                                  value: "Never Allow",
                                                  comment: "Button that permanently denies a website permission.")
    }

    enum PermissionRecovery {
        static let cameraToast = NSLocalizedString("sitePermissions.recovery.toast.camera", bundle: Bundle.module,
                                                   value: "DuckDuckGo couldn’t give camera access to this site",
                                                   comment: "Toast shown when a website was allowed camera access but the iOS camera prompt was denied.")
        static let microphoneToast = NSLocalizedString(
            "sitePermissions.recovery.toast.microphone",
            bundle: Bundle.module,
            value: "DuckDuckGo couldn’t give microphone access to this site",
            comment: "Toast shown when a website was allowed microphone access but the iOS microphone prompt was denied."
        )
        static let cameraAndMicrophoneToast = NSLocalizedString(
            "sitePermissions.recovery.toast.camera-and-microphone",
            bundle: Bundle.module,
            value: "DuckDuckGo couldn’t give camera and microphone access to this site",
            comment: "Toast shown when both fresh iOS permission prompts were denied. The combined wording requires copy review."
        )

        static let cameraTitle = NSLocalizedString("sitePermissions.recovery.reminder.camera.title", bundle: Bundle.module,
                                                   value: "DuckDuckGo needs to access your camera",
                                                   comment: "Title of the reminder shown when iOS camera access is blocked.")
        static let cameraBody = NSLocalizedString("sitePermissions.recovery.reminder.camera.body", bundle: Bundle.module,
                                                  value: "Camera permissions are needed if you want to use camera features on this site.",
                                                  comment: "Body of the reminder shown when iOS camera access is blocked.")
        static let microphoneTitle = NSLocalizedString("sitePermissions.recovery.reminder.microphone.title", bundle: Bundle.module,
                                                       value: "DuckDuckGo needs to access your microphone",
                                                       comment: "Title of the reminder shown when iOS microphone access is blocked.")
        static let microphoneBody = NSLocalizedString("sitePermissions.recovery.reminder.microphone.body", bundle: Bundle.module,
                                                      value: "Microphone permissions are needed if you want to use microphone features on this site.",
                                                      comment: "Body of the reminder shown when iOS microphone access is blocked.")
        static let cameraAndMicrophoneTitle = NSLocalizedString(
            "sitePermissions.recovery.reminder.camera-and-microphone.title",
            bundle: Bundle.module,
            value: "DuckDuckGo needs to access your camera and microphone",
            comment: "Title of the reminder shown when both iOS camera and microphone access are blocked. The combined wording requires copy review."
        )
        static let cameraAndMicrophoneBody = NSLocalizedString(
            "sitePermissions.recovery.reminder.camera-and-microphone.body",
            bundle: Bundle.module,
            value: "Camera and microphone permissions are needed if you want to use related features on this site.",
            comment: "Body of the reminder shown when both iOS camera and microphone access are blocked. The combined wording requires copy review."
        )
        static let changePermissions = NSLocalizedString("sitePermissions.recovery.reminder.change-permissions", bundle: Bundle.module,
                                                         value: "Change Permissions",
                                                         comment: "Button that opens the DuckDuckGo page in iOS Settings.")
        static let cancel = NSLocalizedString("sitePermissions.recovery.reminder.cancel", bundle: Bundle.module,
                                              value: "Cancel",
                                              comment: "Button that closes a permission reminder without changing anything.")
    }

    enum VoiceSearchPermissionRecovery {
        static let title = NSLocalizedString("sitePermissions.voice-search.reminder.title", bundle: Bundle.module,
                                             value: "DuckDuckGo needs to access your microphone",
                                             comment: "Title of the reminder shown when iOS microphone access for Voice Search is blocked.")
        static let body = NSLocalizedString("sitePermissions.voice-search.reminder.body", bundle: Bundle.module,
                                            value: "Microphone permissions are needed if you want to use our Private Voice Search.",
                                            comment: "Body of the reminder shown when iOS microphone access for Voice Search is blocked.")
        static let hideVoiceSearch = NSLocalizedString("sitePermissions.voice-search.reminder.hide", bundle: Bundle.module,
                                                       value: "Hide Voice Search",
                                                       comment: "Button that turns off Voice Search in DuckDuckGo.")
    }

}
