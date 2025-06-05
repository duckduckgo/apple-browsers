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
    private let themeManager: ThemeManaging
    private let appSettings: AppSettings
    private let currentTabViewController: () -> TabViewController?

    private weak var tabViewController: TabViewController?
    private var colorCache: [String: UIColor] = [:]
    private var themeColorObservation: NSKeyValueObservation?

    init(viewCoordinator: MainViewCoordinator,
         currentTabViewController: @autoclosure @escaping () -> TabViewController?,
         appSettings: AppSettings,
         themeManager: ThemeManaging) {
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
        guard isCurrentTabShowingDaxPlayer == false else {
            return
        }

        guard let host = currentTabViewController()?.url?.host,
              let cachedColor = colorCache[host],
              shouldApplyColorToCurrentTab else {
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

            guard let self, self.isCurrentTabShowingDaxPlayer == false else {
                return
            }

            guard self.shouldApplyColorToCurrentTab, let host = webView.url?.host else {
                self.resetThemeColor()
                return
            }

            if let newColor = change.newValue as? UIColor {
                colorCache[host] = newColor
                if isCurrentTab {
                    updateThemeColor(newColor)
                }
            } else {
                self.resetThemeColor()
                self.colorCache[host] = nil
            }
        }
    }

    private var isCurrentTab: Bool {
        tabViewController?.tabModel == currentTabViewController()?.tabModel
    }

    private var shouldApplyColorToCurrentTab: Bool {
        // We do not support top address bar position in this 1st iteration
        appSettings.currentAddressBarPosition == .bottom
        && !(isCurrentTabShowingError || isCurrentTabShowingDaxPlayer)
    }

    private var isCurrentTabShowingError: Bool {
        currentTabViewController()?.isError == true
    }

    private var isCurrentTabShowingDaxPlayer: Bool {
        currentTabViewController()?.url?.isDuckPlayer == true
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

    private func applyThemeColor(_ color: UIColor?) {
        guard themeManager.properties.isExperimentalThemingEnabled else { return }

        var newColor = UIColor(designSystemColor: .background)

        if let color {
            newColor = color
        }

        if AppWidthObserver.shared.isPad && viewCoordinator.parentController?.traitCollection.horizontalSizeClass == .regular {
            viewCoordinator.statusBackground.backgroundColor = themeManager.currentTheme.tabsBarBackgroundColor
        } else {
            viewCoordinator.statusBackground.backgroundColor = newColor
        }
        tabViewController?.pullToRefreshViewAdapter?.backgroundColor = newColor
        tabViewController?.webView?.underPageBackgroundColor = newColor
        tabViewController?.webView?.scrollView.backgroundColor = newColor
    }

}
