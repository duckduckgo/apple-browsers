//
//  Themable.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

extension UIViewController {

    func decorateNavigationBar(_ navigationBar: UINavigationBar? = nil, with theme: Theme = ThemeManager.shared.currentTheme) {

        guard let targetNavigationBar = navigationBar ?? self.navigationController?.navigationBar else { return }

        targetNavigationBar.barTintColor = theme.barBackgroundColor
        targetNavigationBar.tintColor = theme.navigationBarTintColor

        var titleAttrs = targetNavigationBar.titleTextAttributes ?? [:]
        titleAttrs[NSAttributedString.Key.foregroundColor] = theme.navigationBarTitleColor
        navigationController?.navigationBar.titleTextAttributes = titleAttrs
        
        let appearance = UINavigationBarAppearance()
        appearance.shadowColor = .clear
        appearance.backgroundColor = theme.backgroundColor
        appearance.titleTextAttributes = titleAttrs

        targetNavigationBar.standardAppearance = appearance
        targetNavigationBar.scrollEdgeAppearance = appearance
        targetNavigationBar.compactAppearance = appearance
        targetNavigationBar.compactScrollEdgeAppearance = appearance
    }
    
    func decorateToolbar(_ toolbar: UIToolbar? = nil, with theme: Theme = ThemeManager.shared.currentTheme) {

        guard let targetToolbar = toolbar ?? navigationController?.toolbar else {
            return
        }

        let appearance = targetToolbar.standardAppearance

        appearance.backgroundColor = theme.barBackgroundColor
        if ThemeManager.shared.properties.isExperimentalThemingEnabled {
            appearance.shadowColor = .clear
        }

        targetToolbar.standardAppearance = appearance
        targetToolbar.compactAppearance = appearance
        targetToolbar.scrollEdgeAppearance = appearance
        
        targetToolbar.tintColor = theme.barTintColor
    }
}
