//
//  BurnerHomePageViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import AppKit
import SwiftUI

@MainActor
final class BurnerHomePageViewController: NSViewController {

    let appearancePreferences: AppearancePreferences

    required init?(coder: NSCoder) {
        fatalError("BurnerHomePageViewController: Bad initializer")
    }

    init(appearancePreferences: AppearancePreferences = AppearancePreferences.shared) {
        self.appearancePreferences = appearancePreferences

        super.init(nibName: nil, bundle: nil)
    }

    override func loadView() {
        let rootView = BurnerHomePageView()
            .environmentObject(appearancePreferences)

        self.view = NSHostingView(rootView: rootView)
    }
}
