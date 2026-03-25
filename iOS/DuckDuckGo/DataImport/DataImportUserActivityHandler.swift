//
//  DataImportUserActivityHandler.swift
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
import os.log
import BrowserKit

protocol DataImportUserActivityHandling {
    @discardableResult
    func handle(_ userActivity: NSUserActivity) -> Bool
}

final class DataImportUserActivityHandler: DataImportUserActivityHandling {

    static var browserKitImportActivityType: String {
#if compiler(>=6.3)
        if #available(iOS 26.4, *) {
            return BEBrowserDataImportManager.userActivityType
        }
#endif
        return "BEBrowserDataExchangeImportActivity"
    }

    private var lastHandledActivityIdentifier: String?

    @discardableResult
    func handle(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == Self.browserKitImportActivityType else {
            return false
        }

        guard let importToken = Self.importToken(from: userActivity) else {
            Logger.general.error("Skipping BrowserKit data import activity without import token")
            return false
        }
        let activityIdentifier = importToken.uuidString

        guard shouldHandleActivity(withIdentifier: activityIdentifier) else {
            Logger.general.debug("Skipping duplicate BrowserKit data import activity")
            return true
        }

        NotificationCenter.default.post(name: .didReceiveBrowserKitDataImportActivity, object: userActivity)
        return true
    }

    private func shouldHandleActivity(withIdentifier identifier: String) -> Bool {
        guard lastHandledActivityIdentifier != identifier else {
            return false
        }

        lastHandledActivityIdentifier = identifier
        return true
    }

    private static func importToken(from userActivity: NSUserActivity) -> UUID? {
#if compiler(>=6.3)
        if #available(iOS 26.4, *) {
            return userActivity.userInfo?[BEBrowserDataImportManager.importTokenUserInfoKey] as? UUID
        }
#endif
        return nil
    }
}

extension Notification.Name {
    static let didReceiveBrowserKitDataImportActivity = Notification.Name("didReceiveBrowserKitDataImportActivity")
}
