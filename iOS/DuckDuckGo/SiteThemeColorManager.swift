//
//  SiteThemeColorManager.swift
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

import UIKit

final class SiteThemeColorManager {

    private let viewCoordinator: MainViewCoordinator
    private let themeManager: ThemeManager
    private let currentTabViewController: () -> TabViewController?

    private let defaultColor: UIColor = UIColor(designSystemColor: .background)
    private var currentSiteThemeColor: UIColor?

    init(viewCoordinator: MainViewCoordinator,
         currentTabViewController: @autoclosure @escaping () -> TabViewController?,
         themeManager: ThemeManager = ThemeManager.shared) {
        self.viewCoordinator = viewCoordinator
        self.themeManager = themeManager
        self.currentTabViewController = currentTabViewController
    }

    func updateThemeColor() {
        guard ExperimentalThemingManager().isExperimentalThemingEnabled else { return }
        guard viewCoordinator.suggestionTrayContainer.isHidden else {
            resetThemeColor()
            return
        }

        guard let siteThemeColor = currentTabViewController()?.webView?.themeColor else {
            resetThemeColor()
            return
        }

        guard currentSiteThemeColor != siteThemeColor else { return }
        currentSiteThemeColor = siteThemeColor

        let adjustedColor = adjustColor(siteThemeColor)
        applyThemeColor(adjustedColor)
    }

    private func adjustColor(_ color: UIColor) -> UIColor {
        if themeManager.currentInterfaceStyle == .light {
            return color.adjustBrightness(by: 0.04)
        }
        return color.adjustBrightness(by: -0.04)
    }

    private func applyThemeColor(_ color: UIColor) {
        viewCoordinator.statusBackground.backgroundColor = color
        currentTabViewController()?.pullToRefreshViewAdapter?.backgroundColor = color
        currentTabViewController()?.webView?.underPageBackgroundColor = color
    }

    private func resetThemeColor() {
        applyThemeColor(defaultColor)
    }

}
