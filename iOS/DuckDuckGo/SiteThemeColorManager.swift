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
    private let appSettings: AppSettings
    private let currentTabViewController: () -> TabViewController?

    private weak var tabViewController: TabViewController?
    private var colorCache: [String: UIColor] = [:]
    private var themeColorObservation: NSKeyValueObservation?

    init(viewCoordinator: MainViewCoordinator,
         currentTabViewController: @autoclosure @escaping () -> TabViewController?,
         appSettings: AppSettings,
         themeManager: ThemeManager = ThemeManager.shared) {
        self.viewCoordinator = viewCoordinator
        self.appSettings = appSettings
        self.themeManager = themeManager
        self.currentTabViewController = currentTabViewController
    }

    deinit {
        themeColorObservation?.invalidate()
    }

    // MARK: - Public Methods

    func attach(to tabViewController: TabViewController) {
        self.tabViewController = tabViewController
        themeColorObservation?.invalidate()
        startObservingThemeColor()
    }

    func updateThemeColor() {
        guard let host = currentTabViewController()?.url?.host,
              let cachedColor = colorCache[host] else {
            resetThemeColor()
            return
        }
        updateThemeColor(cachedColor)
    }

    func resetThemeColor() {
        applyThemeColor(UIColor(designSystemColor: .background))
    }

    // MARK: - Private Methods

    private func startObservingThemeColor() {
        themeColorObservation = tabViewController?.webView?.observe(\.themeColor, options: [.initial, .new]) { [weak self] webView, change in
            guard let self,
                  let newColor = change.newValue as? UIColor,
                  let host = webView.url?.host else {
                self?.resetThemeColor()
                return
            }

            colorCache[host] = newColor
            if isCurrentTab {
                updateThemeColor(newColor)
            }
        }
    }

    private var isCurrentTab: Bool {
        tabViewController?.tabModel == currentTabViewController()?.tabModel
    }

    private func updateThemeColor(_ color: UIColor) {
        guard viewCoordinator.suggestionTrayContainer.isHidden else {
            resetThemeColor()
            return
        }
        applyThemeColor(adjustColor(color))
    }

    private func adjustColor(_ color: UIColor) -> UIColor {
        let brightnessAdjustment = themeManager.currentInterfaceStyle == .light ? 0.04 : -0.04
        return color.adjustBrightness(by: brightnessAdjustment)
    }

    private func applyThemeColor(_ color: UIColor) {
        guard ExperimentalThemingManager().isExperimentalThemingEnabled else { return }
        // We do not support top address bar position in this 1st iteration
        if appSettings.currentAddressBarPosition == .bottom {
            viewCoordinator.statusBackground.backgroundColor = color
        } else {
            viewCoordinator.statusBackground.backgroundColor = UIColor(designSystemColor: .background)
        }
        tabViewController?.pullToRefreshViewAdapter?.backgroundColor = color
        tabViewController?.webView?.underPageBackgroundColor = color
        tabViewController?.webView?.scrollView.backgroundColor = color
    }

}
