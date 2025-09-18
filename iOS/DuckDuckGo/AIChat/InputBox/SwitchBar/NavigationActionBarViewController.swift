//
//  NavigationActionBarViewController.swift
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

final class NavigationActionBarViewController: UIViewController {
    private let viewModel: NavigationActionBarViewModel
    private var navigationActionBarView: NavigationActionBarView!

    var isShowingGradient: Bool {
        get { navigationActionBarView.isShowingGradient }
        set { navigationActionBarView.isShowingGradient = newValue }
    }

    init(viewModel: NavigationActionBarViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        navigationActionBarView = NavigationActionBarView(viewModel: viewModel)
        view = navigationActionBarView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}
