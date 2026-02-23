//
//  AutoconsentMessageHandlerDelegate+iOS.swift
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
import PixelKit
import WebExtensions
import os.log

@available(iOS 18.4, *)
final class IOSAutoconsentMessageHandlerDelegate: AutoconsentMessageHandlerDelegate {

    func showCookiePopupAnimation(topUrl: URL, isCosmetic: Bool) {
        NotificationCenter.default.post(
            name: .newSiteCookiesManaged,
            object: self,
            userInfo: [
                AutoconsentUserScript.UserInfoKeys.topURL: topUrl,
                AutoconsentUserScript.UserInfoKeys.isCosmetic: isCosmetic
            ]
        )
    }

    func refreshDashboardState(domain: String, consentStatus: ConsentStatusInfo) {
        Logger.webExtensions.debug("iOS: Refreshing dashboard state for \(domain)")
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
        Logger.webExtensions.debug("iOS: Cookie popup handled for \(popupInfo.url.absoluteString)")
    }

    func sendPixel(_ pixelInfo: PixelInfo) {
        guard let pixel = mapPixelNameToAutoconsentPixel(pixelInfo.name, params: pixelInfo.params) else {
            Logger.webExtensions.error("iOS: Unknown autoconsent pixel name: \(pixelInfo.name)")
            return
        }

        let frequency: PixelKit.Frequency = pixelInfo.type == "daily" ? .daily : .standard
        let additionalParams = processAdditionalParams(pixelInfo.params, isSummary: pixelInfo.name == "autoconsent_summary")

        Logger.webExtensions.debug("iOS: Firing pixel \(pixelInfo.name) with frequency \(pixelInfo.type)")

        PixelKit.fire(pixel, frequency: frequency, withAdditionalParameters: additionalParams, includeAppVersionParameter: true)
    }

    private func processAdditionalParams(_ params: [String: Any], isSummary: Bool) -> [String: String] {
        let stringParams = params.compactMapValues { value -> String? in
            if let stringValue = value as? String { return stringValue }
            if let intValue = value as? Int { return String(intValue) }
            return nil
        }

        if isSummary {
            // Filter out params that are already packed as part of the summary pixel
            let summaryKeys = Set(AutoconsentPixel.summaryPixels.map { $0.key })
            return stringParams.filter { !summaryKeys.contains($0.key) }
        }

        return stringParams
    }

    private func mapPixelNameToAutoconsentPixel(_ name: String, params: [String: Any]) -> AutoconsentPixel? {
        switch name {
        case "autoconsent_init":
            return .acInit
        case "autoconsent_error_multiple-popups":
            return .errorMultiplePopups
        case "autoconsent_error_optout":
            return .errorOptoutFailed
        case "autoconsent_error_reload-loop":
            return .errorReloadLoop
        case "autoconsent_popup-found":
            return .popupFound
        case "autoconsent_done":
            return .done
        case "autoconsent_done_cosmetic":
            return .doneCosmetic
        case "autoconsent_done_heuristic":
            return .doneHeuristic
        case "autoconsent_animation-shown":
            return .animationShown
        case "autoconsent_animation-shown_cosmetic":
            return .animationShownCosmetic
        case "autoconsent_disabled-for-site":
            return .disabledForSite
        case "autoconsent_detected-by-patterns":
            return .detectedByPatterns
        case "autoconsent_detected-by-both":
            return .detectedByBoth
        case "autoconsent_detected-only-rules":
            return .detectedOnlyRules
        case "autoconsent_self-test-ok":
            return .selfTestOk
        case "autoconsent_self-test-fail":
            return .selfTestFail
        case "autoconsent_summary":
            let intParams = params.compactMapValues { value -> Int? in
                if let intValue = value as? Int { return intValue }
                if let stringValue = value as? String { return Int(stringValue) }
                return nil
            }
            return .summary(events: intParams)
        default:
            return nil
        }
    }
}
