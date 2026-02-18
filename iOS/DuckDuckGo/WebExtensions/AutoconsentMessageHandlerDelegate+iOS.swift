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
    }

    func handleCookiePopup(_ popupInfo: CookiePopupHandledInfo) {
        Logger.webExtensions.debug("iOS: Cookie popup handled for \(popupInfo.url.absoluteString)")
    }

    func sendPixel(_ pixelInfo: PixelInfo) {
        Logger.webExtensions.debug("iOS: Firing pixel \(pixelInfo.name) of type \(pixelInfo.type)")
    }
}
