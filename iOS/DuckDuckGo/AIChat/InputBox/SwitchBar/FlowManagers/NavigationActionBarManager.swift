//
//  NavigationActionBarManager.swift
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

import Foundation
import UIKit

/// Protocol for handling navigation action bar events
protocol NavigationActionBarManagerDelegate: AnyObject {
    func navigationActionBarManagerDidTapMicrophone(_ manager: NavigationActionBarManager)
    func navigationActionBarManagerDidTapNewLine(_ manager: NavigationActionBarManager)
    func navigationActionBarManagerDidTapSearch(_ manager: NavigationActionBarManager)
}

/// Manages the navigation action bar displayed at the bottom of the screen
final class NavigationActionBarManager {
    
    // MARK: - Properties
    
    weak var delegate: NavigationActionBarManagerDelegate?
    
    private let switchBarHandler: SwitchBarHandling
    private var navigationActionBarViewController: NavigationActionBarViewController?
    private var navigationActionBarViewModel: NavigationActionBarViewModel?
    
    // MARK: - Initialization
    
    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
    }

    // MARK: - Public Methods
    
    /// Installs the navigation action bar in the provided parent view controller
    @MainActor
    func installInViewController(_ viewController: UIViewController, safeAreaGuide: UILayoutGuide) {
        let viewModel = NavigationActionBarViewModel(
            switchBarHandler: switchBarHandler,
            onMicrophoneTapped: { [weak self] in
                guard let self = self else { return }
                self.delegate?.navigationActionBarManagerDidTapMicrophone(self)
            },
            onNewLineTapped: { [weak self] in
                guard let self = self else { return }
                self.delegate?.navigationActionBarManagerDidTapNewLine(self)
            },
            onSearchTapped: { [weak self] in
                guard let self = self else { return }
                self.delegate?.navigationActionBarManagerDidTapSearch(self)
            }
        )
        navigationActionBarViewModel = viewModel
        
        let actionBarViewController = NavigationActionBarViewController(viewModel: viewModel)
        navigationActionBarViewController = actionBarViewController
        
        viewController.addChild(actionBarViewController)
        viewController.view.addSubview(actionBarViewController.view)
        actionBarViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            actionBarViewController.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            actionBarViewController.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            actionBarViewController.view.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        actionBarViewController.didMove(toParent: viewController)
    }
    
    /// Removes the navigation action bar from its parent
    func removeFromParent() {
        navigationActionBarViewController?.willMove(toParent: nil)
        navigationActionBarViewController?.view.removeFromSuperview()
        navigationActionBarViewController?.removeFromParent()
        navigationActionBarViewController = nil
        navigationActionBarViewModel = nil
    }
}
