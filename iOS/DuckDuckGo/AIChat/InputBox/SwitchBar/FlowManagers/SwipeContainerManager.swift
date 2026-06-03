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

import Combine
import Foundation
import UIKit

/// Manages the horizontal swipe container with pagination between search and AI chat modes
final class SwipeContainerManager: NSObject {

    enum ContentTransition {
        case paged
        case crossfade

        init(switchBarHandler: SwitchBarHandling) {
            self = switchBarHandler.isUsingFadeOutAnimation ? .crossfade : .paged
        }
    }

    // MARK: - Properties

    private let switchBarHandler: SwitchBarHandling
    private let contentTransition: ContentTransition

    private var usesFadeOutTransition: Bool {
        contentTransition == .crossfade
    }

    var searchPageContainer: UIView {
        if usesFadeOutTransition {
            return fadeOutContainerViewController.searchPageContainer
        } else {
            return swipeContainerViewController.searchPageContainer
        }
    }

    var chatPageContainer: UIView {
        if usesFadeOutTransition {
            return fadeOutContainerViewController.chatPageContainer
        } else {
            return swipeContainerViewController.chatPageContainer
        }
    }

    private lazy var swipeContainerViewController = SwipeContainerViewController(switchBarHandler: switchBarHandler)
    private lazy var fadeOutContainerViewController = FadeOutContainerViewController(switchBarHandler: switchBarHandler)

    var containerViewController: UIViewController {
        usesFadeOutTransition ? fadeOutContainerViewController : swipeContainerViewController
    }

    var delegate: SwipeContainerViewControllerDelegate? {
        get { swipeContainerViewController.delegate }
        set { swipeContainerViewController.delegate = newValue }
    }

    var animateProgrammaticModeChanges: Bool {
        get { swipeContainerViewController.animateProgrammaticModeChanges }
        set { swipeContainerViewController.animateProgrammaticModeChanges = newValue }
    }

    var isSwipeEnabled: Bool {
        get {
            usesFadeOutTransition
                ? fadeOutContainerViewController.isSwipeEnabled
                : swipeContainerViewController.isSwipeEnabled
        }
        set {
            if usesFadeOutTransition {
                fadeOutContainerViewController.isSwipeEnabled = newValue
            } else {
                swipeContainerViewController.isSwipeEnabled = newValue
            }
        }
    }

    var fadeOutDelegate: FadeOutContainerViewControllerDelegate? {
        get { fadeOutContainerViewController.delegate }
        set { fadeOutContainerViewController.delegate = newValue }
    }

    // MARK: - Initialization
    
    init(switchBarHandler: SwitchBarHandling,
         contentTransition: ContentTransition? = nil) {
        self.switchBarHandler = switchBarHandler
        self.contentTransition = contentTransition ?? ContentTransition(switchBarHandler: switchBarHandler)
        super.init()
    }
    
    // MARK: - Public Methods


    /// Installs the chat history manager in the chat page container.
    /// Used by the legacy `OmniBarEditingStateViewController` (non-UTI path).
    @MainActor
    func installChatHistory(using manager: AIChatHistoryManager) {
        manager.installInContainerView(chatPageContainer, parentViewController: containerViewController)
    }

    /// Installs the Duck.ai multi-section suggestions coordinator in the chat page container.
    /// Used by `UnifiedInputContentContainerViewController` (UTI path).
    @MainActor
    func installDuckAISuggestions<P: Publisher>(using coordinator: DuckAISuggestionsCoordinator,
                                                textPublisher: P) where P.Output == String, P.Failure == Never {
        coordinator.start(in: chatPageContainer,
                          parentViewController: containerViewController,
                          textPublisher: textPublisher)
    }

    /// Overlays the search page on the visible area, or returns it to its natural position.
    func setSearchPageVisible(_ visible: Bool, animated: Bool) {
        if usesFadeOutTransition {
            applySearchPageFade(visible, animated: animated)
        } else {
            applySearchPageSlide(visible, animated: animated)
        }
    }

    /// Pages already overlap — control visibility with alpha.
    private func applySearchPageFade(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1.0 : 0.0
        if visible {
            searchPageContainer.superview?.bringSubviewToFront(searchPageContainer)
        }
        if animated {
            UIView.animate(withDuration: 0.2) { self.searchPageContainer.alpha = alpha }
        } else {
            searchPageContainer.alpha = alpha
        }
    }

    /// Pages are side-by-side — translate the search page over the chat page.
    private func applySearchPageSlide(_ visible: Bool, animated: Bool) {
        if visible {
            let pageWidth = swipeContainerViewController.swipeScrollView.frame.width
            searchPageContainer.transform = CGAffineTransform(translationX: pageWidth, y: 0)
            searchPageContainer.superview?.bringSubviewToFront(searchPageContainer)
            searchPageContainer.alpha = 1.0
        } else {
            let fadeOut = {
                self.searchPageContainer.alpha = 0.0
            }
            let resetTransform = { (_: Bool) in
                self.searchPageContainer.transform = .identity
                self.searchPageContainer.alpha = 1.0
            }
            if animated {
                UIView.animate(withDuration: 0.2, animations: fadeOut, completion: resetTransform)
            } else {
                fadeOut()
                resetTransform(true)
            }
        }
    }

    /// Restores the chat page container visibility after URL fallback hides.
    func restoreChatPageVisibility() {
        chatPageContainer.alpha = 1.0
    }

    func syncVisibleMode(animated: Bool) {
        if usesFadeOutTransition {
            fadeOutContainerViewController.setMode(switchBarHandler.currentToggleState, animated: animated)
        } else {
            swipeContainerViewController.syncToCurrentMode(animated: animated)
        }
    }

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
