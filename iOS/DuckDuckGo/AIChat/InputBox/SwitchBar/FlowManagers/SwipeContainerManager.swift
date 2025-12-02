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
import BrowserServicesKit


/// Manages the horizontal swipe container with pagination between search and AI chat modes
final class SwipeContainerManager: NSObject {

    // MARK: - Properties

    private let switchBarHandler: SwitchBarHandling
    private let featureFlagger: FeatureFlagger

    var searchPageContainer: UIView {
        if switchBarHandler.isUsingFadeOutAnimation {
            return fadeOutContainerViewController.searchPageContainer
        } else {
            return swipeContainerViewController.searchPageContainer
        }
    }

    private lazy var swipeContainerViewController = SwipeContainerViewController(switchBarHandler: switchBarHandler)
    private lazy var fadeOutContainerViewController = FadeOutContainerViewController(switchBarHandler: switchBarHandler, featureFlagger: featureFlagger)

    var containerViewController: UIViewController {
        switchBarHandler.isUsingFadeOutAnimation ? fadeOutContainerViewController : swipeContainerViewController
    }

    var delegate: SwipeContainerViewControllerDelegate? {
        get { swipeContainerViewController.delegate }
        set { swipeContainerViewController.delegate = newValue }
    }

    var fadeOutDelegate: FadeOutContainerViewControllerDelegate? {
        get { fadeOutContainerViewController.delegate }
        set { fadeOutContainerViewController.delegate = newValue }
    }

    // MARK: - Initialization
    
    init(switchBarHandler: SwitchBarHandling,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.switchBarHandler = switchBarHandler
        self.featureFlagger = featureFlagger
        super.init()
    }
    
    // MARK: - Public Methods


    /// Installs the swipe container in the provided parent view
    func installInViewController(_ parentController: UIViewController, asSubviewOf view: UIView, barView: UIView, isTopBarPosition: Bool) {
        parentController.addChild(containerViewController)

        view.insertSubview(containerViewController.view, belowSubview: barView)

        containerViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        if isTopBarPosition {
            containerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            // Allow scroll to flow under
            containerViewController.view.topAnchor.constraint(equalTo: barView.bottomAnchor,
                                                              constant: -Metrics.contentUnderflowOffset).isActive = true

            // Compensate for the underflow + margin
            containerViewController.additionalSafeAreaInsets.top = Metrics.contentMargin + Metrics.contentUnderflowOffset
        } else {
            containerViewController.view.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            containerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        }

        containerViewController.didMove(toParent: parentController)
    }

    private struct Metrics {
        static let contentUnderflowOffset = 16.0
        static let contentMargin = 8.0
    }
}
