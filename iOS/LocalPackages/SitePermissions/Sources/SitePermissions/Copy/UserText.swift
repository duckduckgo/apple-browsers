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
import FoundationExtensions

enum UserText {

    enum PermissionDialog {
        static func cameraTitle(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.dialog.camera.title", bundle: Bundle.module,
                                            value: "“%@” website wants to access your camera",
                                            comment: "Website camera permission prompt title. %@ is the website domain; this is separate from iOS camera permission.")
            return String(format: format, domain)
        }

        static func microphoneTitle(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.dialog.microphone.title", bundle: Bundle.module,
                                            value: "“%@” website wants to access your microphone",
                                            comment: "Website microphone permission prompt title. %@ is the website domain; this is separate from iOS microphone permission.")
            return String(format: format, domain)
        }

        static func cameraAndMicrophoneTitle(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.dialog.camera-and-microphone.title", bundle: Bundle.module,
                                            value: "“%@” website wants to access your camera and microphone",
                                            comment: "Combined website camera and microphone permission prompt title. %@ is the website domain; iOS app permissions are separate.")
            return String(format: format, domain)
        }

        static func locationTitle(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.dialog.location.title", bundle: Bundle.module,
                                            value: "“%@” website wants to access your location",
                                            comment: "Website location permission prompt title. %@ is the website domain; this is separate from iOS location permission.")
            return String(format: format, domain)
        }

        static let duckDuckGoSERPLocationTitle = NSLocalizedString(
            "sitePermissions.dialog.location.duckduckgo-serp.title",
            bundle: Bundle.module,
            value: "“duckduckgo.com” wants to access your location",
            comment: "Title shown when DuckDuckGo search results ask to use location. The missing word 'website' requires copy review."
        )
        static let duckDuckGoSERPLocationBody = NSLocalizedString(
            "sitePermissions.dialog.location.duckduckgo-serp.body",
            bundle: Bundle.module,
            value: "We’ll anonymize your location and use it to deliver better results, closer to you.",
            comment: "Explanation shown when DuckDuckGo search results ask to use location. Copy requires review."
        )

        static let allowOnce = NSLocalizedString("sitePermissions.dialog.allow-once", bundle: Bundle.module,
                                                  value: "Allow Once",
                                                  comment: "Button that temporarily grants a website permission for the current page.")
        static let allowWhileUsingSite = NSLocalizedString("sitePermissions.dialog.allow-while-using-site", bundle: Bundle.module,
                                                            value: "Allow While Using Site",
                                                            comment: "Button that saves approval for this website. DuckDuckGo's iOS app permission is separate.")
        static let neverAllow = NSLocalizedString("sitePermissions.dialog.never-allow", bundle: Bundle.module,
                                                   value: "Never Allow",
                                                   comment: "Button that saves denial for this website until the user changes it.")
        static let deny = NSLocalizedString("sitePermissions.dialog.deny", bundle: Bundle.module,
                                             value: "Deny",
                                             comment: "Fire-tab button that denies a website permission for this tab session without saving it.")
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
        static let locationToast = NSLocalizedString(
            "sitePermissions.recovery.toast.location",
            bundle: Bundle.module,
            value: "DuckDuckGo couldn’t share location with this site",
            comment: "Toast shown when a website was allowed location access but the iOS location prompt was denied."
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
        static let locationTitle = NSLocalizedString("sitePermissions.recovery.reminder.location.title", bundle: Bundle.module,
                                                      value: "DuckDuckGo needs to access your location",
                                                      comment: "Title of the reminder shown when iOS location access is blocked.")
        static let locationBody = NSLocalizedString("sitePermissions.recovery.reminder.location.body", bundle: Bundle.module,
                                                     value: "Location permissions are needed if you want to use location features on this site.",
                                                     comment: "Body of the reminder shown when iOS location access is blocked.")
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
        static let settingsBody = NSLocalizedString("sitePermissions.voice-search.settings-reminder.body", bundle: Bundle.module,
                                                     value: "Microphone permissions are needed if you want to use our private voice features.",
                                                     comment: "Body of the reminder shown when enabling Private Voice Search in Settings while iOS microphone access is blocked.")
    }

    enum VoiceChatPermissionRecovery {
        static let body = NSLocalizedString("sitePermissions.voice-chat.reminder.body", bundle: Bundle.module,
                                             value: "Microphone permissions are needed if you want to use Voice Chat in Duck.ai.",
                                             comment: "Body of the reminder shown when iOS microphone access for Duck.ai Voice Chat is blocked.")
    }

    enum PermissionManagement {
        static func title(domain: String) -> String {
            let format = NSLocalizedString("sitePermissions.management.title", bundle: Bundle.module,
                                           value: "Permissions for “%@”",
                                           comment: "Visible and VoiceOver title of the website permission sheet. %@ is the website domain; translators may move it within the sentence.")
            return String(format: format, domain)
        }

        static let camera = NSLocalizedString("sitePermissions.management.camera", bundle: Bundle.module,
                                              value: "Camera",
                                              comment: "Camera permission row label.")
        static let microphone = NSLocalizedString("sitePermissions.management.microphone", bundle: Bundle.module,
                                                  value: "Microphone",
                                                  comment: "Microphone permission row label.")
        static let location = NSLocalizedString("sitePermissions.management.location", bundle: Bundle.module,
                                                 value: "Location",
                                                 comment: "Location permission row label.")
        static let askEachTime = NSLocalizedString("sitePermissions.management.ask-each-time", bundle: Bundle.module,
                                                   value: "Ask Each Time",
                                                   comment: "Permission picker option that asks again when a site requests access.")
        static let alwaysAllow = NSLocalizedString("sitePermissions.management.always-allow", bundle: Bundle.module,
                                                   value: "Always Allow",
                                                   comment: "Website permission picker option that saves approval for this site; iOS app permission is separate.")
        static let neverAllow = NSLocalizedString("sitePermissions.management.never-allow", bundle: Bundle.module,
                                                  value: "Never Allow",
                                                  comment: "Website permission picker option that saves denial for this site until the user changes it.")
        static let reloadCaption = NSLocalizedString("sitePermissions.management.reload-caption", bundle: Bundle.module,
                                                     value: "Reload the page for changes to take effect.",
                                                     comment: "Caption below on-site permission rows explaining when changes apply.")
        static let removePermissions = NSLocalizedString("sitePermissions.management.remove-permissions", bundle: Bundle.module,
                                                         value: "Remove Permissions",
                                                         comment: "Action that removes all stored permissions for the current site.")
        static let goToSystemSettings = NSLocalizedString("sitePermissions.management.go-to-system-settings", bundle: Bundle.module,
                                                          value: "Go to System Settings",
                                                          comment: "Action that opens DuckDuckGo's page in iOS Settings.")
        static let close = NSLocalizedString("sitePermissions.management.close", bundle: Bundle.module,
                                             value: "Close",
                                             comment: "Accessibility label for the on-site permission sheet close button.")
        static let inUseFormat = NSLocalizedString("sitePermissions.management.accessibility.in-use", bundle: Bundle.module,
                                                   value: "%@, in use",
                                                   comment: "VoiceOver value for a website permission currently in use. %@ is its selected option, such as Always Allow.")
        static let pausedFormat = NSLocalizedString("sitePermissions.management.accessibility.paused", bundle: Bundle.module,
                                                    value: "%@, paused",
                                                    comment: "VoiceOver value for a paused website permission. %@ is its selected option, such as Always Allow.")

        static func title(for permissionType: SitePermissionType) -> String {
            switch permissionType {
            case .camera:
                return camera
            case .microphone:
                return microphone
            case .location:
                return location
            }
        }

        static func title(for option: SitePermissionPickerOption) -> String {
            switch option {
            case .askEachTime:
                return askEachTime
            case .alwaysAllow:
                return alwaysAllow
            case .neverAllow:
                return neverAllow
            case .deny:
                return PermissionDialog.deny
            }
        }

        static func inUseAccessibilityValue(state: String) -> String {
            String(format: inUseFormat, state)
        }

        static func pausedAccessibilityValue(state: String) -> String {
            String(format: pausedFormat, state)
        }

        static func reminder(permissionTypes: Set<SitePermissionType>) -> String? {
            let format = NSLocalizedString("sitePermissions.management.reminder", bundle: Bundle.module,
                                           value: "DuckDuckGo needs to access your %@, if you want to use related features on this site.",
                                           comment: "Reminder shown when iOS blocks permissions a website is allowed to use. "
                                               + "%@ is a localized list of camera, location, or microphone names. Copy requires review.")
            let names = [SitePermissionType.camera, .location, .microphone]
                .filter(permissionTypes.contains)
                .map { permissionType in
                    switch permissionType {
                    case .camera:
                        return NSLocalizedString("sitePermissions.management.reminder.camera", bundle: Bundle.module,
                                                 value: "camera",
                                                 comment: "Lowercase camera name in a localized list of iOS permissions blocked for a website.")
                    case .location:
                        return NSLocalizedString("sitePermissions.management.reminder.location", bundle: Bundle.module,
                                                 value: "location",
                                                 comment: "Lowercase location name in a localized list of iOS permissions blocked for a website.")
                    case .microphone:
                        return NSLocalizedString("sitePermissions.management.reminder.microphone", bundle: Bundle.module,
                                                 value: "microphone",
                                                 comment: "Lowercase microphone name in a localized list of iOS permissions blocked for a website.")
                    }
                }
            guard !names.isEmpty else { return nil }
            let list = ListFormatter.localizedString(byJoining: names)
            return String(format: format, list)
        }
    }

}
