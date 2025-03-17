//
//  ExperimentalTheme.swift
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

struct ExperimentalTheme: Theme {
    var name: ThemeName { baseTheme.name }

    var backgroundColor: UIColor { .systemPink }
    var mainViewBackgroundColor: UIColor { .systemPink }
    var searchBarBackgroundColor: UIColor { .systemPink }
    var tabsBarBackgroundColor: UIColor { .systemPink }
    var homeRowBackgroundColor: UIColor { .systemPink }
    var barBackgroundColor: UIColor { .systemPink }

    var statusBarStyle: UIStatusBarStyle { baseTheme.statusBarStyle }
    var keyboardAppearance: UIKeyboardAppearance { baseTheme.keyboardAppearance }
    var tabsBarSeparatorColor: UIColor { baseTheme.tabsBarSeparatorColor }
    var navigationBarTintColor: UIColor { baseTheme.navigationBarTintColor }
    var searchBarTextDeemphasisColor: UIColor { baseTheme.searchBarTextDeemphasisColor }
    var browsingMenuHighlightColor: UIColor { baseTheme.browsingMenuHighlightColor }
    var tableCellHighlightedBackgroundColor: UIColor { baseTheme.tableCellHighlightedBackgroundColor }
    var activityStyle: UIActivityIndicatorView.Style { baseTheme.activityStyle }
    var destructiveColor: UIColor { baseTheme.destructiveColor }

    let baseTheme = DefaultTheme()
}
