//
//  MessageNavigator.swift
//  DuckDuckGo
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

import RemoteMessaging
import UIKit

protocol MessageNavigator {

    func navigateTo(_ target: NavigationTarget)

}

class DefaultMessageNavigator: MessageNavigator {

    weak var mainViewController: MainViewController?

    init(mainViewController: MainViewController? = UIApplication.shared.window?.rootViewController as? MainViewController) {
        assert(mainViewController != nil)
        self.mainViewController = mainViewController
    }

    func navigateTo(_ target: NavigationTarget) {
        switch target {
        case .duckAISettings:
            mainViewController?.segueToSettingsAIChat()
        case .settings:
            mainViewController?.segueToSettings()
        }
    }

}
