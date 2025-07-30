//
//  SwipeContainerManager.swift
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


/// Manages the horizontal swipe container with pagination between search and AI chat modes
final class SwipeContainerManager: NSObject {
    
    // MARK: - Properties

    private let switchBarHandler: SwitchBarHandling

    var searchPageContainer: UIView { swipeContainerViewController.searchPageContainer }

    lazy var swipeContainerViewController = SwipeContainerViewController(switchBarHandler: switchBarHandler)

    var delegate: SwipeContainerViewControllerDelegate? {
        get { swipeContainerViewController.delegate }
        set { swipeContainerViewController.delegate = newValue }
    }

    // MARK: - Initialization
    
    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Installs the swipe container in the provided parent view
    func installInViewController(_ parentController: UIViewController, belowView: UIView) {
        parentController.addChild(swipeContainerViewController)

        parentController.view.insertSubview(swipeContainerViewController.view, belowSubview: belowView)
        swipeContainerViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            swipeContainerViewController.view.leadingAnchor.constraint(equalTo: parentController.view.leadingAnchor),
            swipeContainerViewController.view.trailingAnchor.constraint(equalTo: parentController.view.trailingAnchor),
            // Allow scroll to flow under
            swipeContainerViewController.view.topAnchor.constraint(equalTo: belowView.bottomAnchor, constant: -Metrics.contentUnderflowOffset),
            swipeContainerViewController.view.bottomAnchor.constraint(equalTo: parentController.view.bottomAnchor),
        ])

        // Compensate for the underflow + margin
        swipeContainerViewController.additionalSafeAreaInsets.top = Metrics.contentMargin + Metrics.contentUnderflowOffset

        swipeContainerViewController.didMove(toParent: parentController)
    }

    private struct Metrics {
        static let contentUnderflowOffset = 16.0
        static let contentMargin = 8.0
    }
}
