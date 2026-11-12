//
//  UIApplicationExtension.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import UIKit
import Subscription

extension UIApplication {

    enum TerminationError: Error {

        case insufficientDiskSpace
        case unrecoverableState

    }

    // MARK: notification settings

    private static let notificationSettingsURL: URL? = {
        let settingsString: String
        if #available(iOS 16, *) {
            settingsString = UIApplication.openNotificationSettingsURLString
        } else if #available(iOS 15.4, *) {
            settingsString = UIApplicationOpenNotificationSettingsURLString
        } else {
            settingsString = UIApplication.openSettingsURLString
        }
        return URL(string: settingsString)
    }()

    func openAppNotificationSettings() async -> Bool {
        guard
            let url = UIApplication.notificationSettingsURL,
            self.canOpenURL(url) else { return false }
        return await self.open(url)
    }

    // MARK: foreground scene windows

    var foregroundSceneWindows: [UIWindow] {
        let focusedScene = (delegate as? AppDelegate)?.appStateMachine.windowManager?.focusedWindow?.windowScene
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
        func priority(_ scene: UIWindowScene) -> Int {
            if scene === focusedScene { return 0 }
            return scene.activationState == .foregroundActive ? 1 : 2
        }
        return scenes.sorted { priority($0) < priority($1) }.flatMap(\.windows)
    }

    var firstKeyWindow: UIWindow? {
        return foregroundSceneWindows.first(where: \.isKeyWindow)
    }

}
