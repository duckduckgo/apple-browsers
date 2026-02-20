//
//  AutoconsentMessageHandlerDelegate+macOS.swift
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
import WebExtensions
import os.log

@available(macOS 15.4, *)
final class MacOSAutoconsentMessageHandlerDelegate: AutoconsentMessageHandlerDelegate {

    func showCookiePopupAnimation(topUrl: URL, isCosmetic: Bool) {
        NotificationCenter.default.post(
            name: AutoconsentUserScript.newSitePopupHiddenNotification,
            object: self,
            userInfo: [
                "topUrl": topUrl,
                "isCosmetic": isCosmetic
            ]
        )
    }

    func refreshDashboardState(domain: String, consentStatus: ConsentStatusInfo) {
        Logger.webExtensions.debug("macOS: Refreshing dashboard state for \(domain)")
        NotificationCenter.default.post(
            name: .webExtensionAutoconsentDashboardStateRefresh,
            object: self,
            userInfo: [
                AutoconsentNotification.UserInfoKeys.domain: domain,
                AutoconsentNotification.UserInfoKeys.consentStatus: consentStatus
            ]
        )
    }

    func handleCookiePopup(_ popupInfo: CookiePopupHandledInfo) {
        Logger.webExtensions.debug("macOS: Cookie popup handled for \(popupInfo.url.absoluteString)")

        let message = popupInfo.message
        let userInfo = AutoconsentPopupManagedEvent.makeNotificationUserInfo(
            url: popupInfo.url,
            cmpName: message["cmp"] as? String ?? "unknown",
            isCosmetic: message["isCosmetic"] as? Bool ?? false,
            totalClicks: message["totalClicks"] as? Int ?? 0,
            duration: message["duration"] as? TimeInterval ?? 0
        )

        NotificationCenter.default.post(
            name: AutoconsentPopupManagedEvent.webExtensionPopupManagedNotification,
            object: self,
            userInfo: userInfo
        )
    }

    func sendPixel(_ pixelInfo: PixelInfo) {
        guard let pixel = mapPixelNameToAutoconsentPixel(pixelInfo.name) else {
            Logger.webExtensions.error("macOS: Unknown autoconsent pixel name: \(pixelInfo.name)")
            return
        }

        let frequency: PixelKit.Frequency = pixelInfo.type == "daily" ? .daily : .standard
        Logger.webExtensions.debug("macOS: Firing pixel \(pixelInfo.name) with frequency \(pixelInfo.type)")
        PixelKit.fire(pixel, frequency: frequency, withAdditionalParameters: pixelInfo.params)
    }

    private func mapPixelNameToAutoconsentPixel(_ name: String) -> AutoconsentPixel? {
        switch name {
        case "autoconsent_init":
            return .acInit
        case "error_multiple-popups":
            return .errorMultiplePopups
        case "error_optout":
            return .errorOptoutFailed
        case "error_reload-loop":
            return .errorReloadLoop
        case "popup-found":
            return .popupFound
        case "done":
            return .done
        case "done_cosmetic":
            return .doneCosmetic
        case "done_heuristic":
            return .doneHeuristic
        case "animation-shown":
            return .animationShown
        case "animation-shown_cosmetic":
            return .animationShownCosmetic
        case "disabled-for-site":
            return .disabledForSite
        case "detected-by-patterns":
            return .detectedByPatterns
        case "detected-by-both":
            return .detectedByBoth
        case "detected-only-rules":
            return .detectedOnlyRules
        default:
            return nil
        }
    }
}
