//
//  MainViewController+MultiWindow.swift
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

import UIKit

extension MainViewController {
    var windowMenuEntries: [BrowsingMenuEntry] {
        guard browserWindowRequest != nil, UIApplication.shared.supportsMultipleScenes else { return [] }
        let regular = BrowsingMenuEntry.regular(
            name: NSLocalizedString("multiWindowNewWindow", value: "New Window", comment: "Open a browser window"),
            image: UIImage(systemName: "macwindow.badge.plus")!,
            accessibilityIdentifier: "Browser.NewWindow",
            action: { [weak self] in self?.browserWindowRequest?(.normal) })
        guard fireModeCapability.isFireModeEnabled else { return [regular] }
        let fire = BrowsingMenuEntry.regular(
            name: NSLocalizedString("multiWindowNewFireWindow", value: "New Fire Window", comment: "Open a Fire mode window"),
            image: UIImage(systemName: "flame")!,
            accessibilityIdentifier: "Browser.NewFireWindow",
            action: { [weak self] in self?.browserWindowRequest?(.fire) })
        return [regular, fire]
    }
}
