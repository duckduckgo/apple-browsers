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
import Combine

/// Protocol for handling swipe container events
protocol SwipeContainerManagerDelegate: AnyObject {
    func swipeContainerManager(_ manager: SwipeContainerManager, didSwipeToMode mode: TextEntryMode)
    func swipeContainerManager(_ manager: SwipeContainerManager, didUpdateScrollProgress progress: CGFloat)
}

/// Manages the horizontal swipe container with pagination between search and AI chat modes
final class SwipeContainerManager: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: SwipeContainerManagerDelegate?
    
    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Scroll Progress
    @Published private(set) var scrollProgress: CGFloat = 0.0
    var scrollProgressPublisher: AnyPublisher<CGFloat, Never> {
        $scrollProgress.eraseToAnyPublisher()
    }
    
    // MARK: - UI Elements
    
    private(set) var swipeScrollView: UIScrollView!
    private(set) var searchPageContainer: UIView!
    private(set) var chatPageContainer: UIView!
    
    // MARK: - Initialization
    
    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        super.init()
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Installs the swipe container in the provided parent view
    func installInView(_ parentView: UIView, belowView topView: UIView) {
        createScrollView()
        createContainerViews()
        addToParentView(parentView)
        setupConstraints(belowView: topView, superview: parentView)
        configureInitialPosition()
    }
    
    /// Updates the scroll view position and content size when bounds change
    func updateLayout(viewBounds: CGRect) {
        guard swipeScrollView != nil else { return }
        let pageWidth = viewBounds.width
        swipeScrollView.contentSize = CGSize(width: pageWidth * 2, height: 0)
        updateScrollViewPosition(pageWidth: pageWidth, animated: false)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateScrollViewPosition(animated: true)
            }
            .store(in: &cancellables)
    }
    
    private func createScrollView() {
        swipeScrollView = UIScrollView()
        swipeScrollView.isPagingEnabled = true
        swipeScrollView.showsHorizontalScrollIndicator = false
        swipeScrollView.showsVerticalScrollIndicator = false
        swipeScrollView.delegate = self
        swipeScrollView.bounces = false
        swipeScrollView.translatesAutoresizingMaskIntoConstraints = false
        swipeScrollView.contentInsetAdjustmentBehavior = .never
    }
    
    private func createContainerViews() {
        searchPageContainer = UIView()
        searchPageContainer.translatesAutoresizingMaskIntoConstraints = false
        
        chatPageContainer = UIView()
        chatPageContainer.backgroundColor = .clear
        chatPageContainer.translatesAutoresizingMaskIntoConstraints = false
        
        swipeScrollView.addSubview(searchPageContainer)
        swipeScrollView.addSubview(chatPageContainer)
    }
    
    private func addToParentView(_ parentView: UIView) {
        parentView.addSubview(swipeScrollView)
    }
    
    private func setupConstraints(belowView topView: UIView, superview: UIView) {
        NSLayoutConstraint.activate([
            // Scroll view constraints
            swipeScrollView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            swipeScrollView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            swipeScrollView.topAnchor.constraint(equalTo: topView.bottomAnchor, constant: 4),
            swipeScrollView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),

            // Search page constraints
            searchPageContainer.leadingAnchor.constraint(equalTo: swipeScrollView.contentLayoutGuide.leadingAnchor),
            searchPageContainer.topAnchor.constraint(equalTo: swipeScrollView.contentLayoutGuide.topAnchor),
            searchPageContainer.bottomAnchor.constraint(equalTo: swipeScrollView.contentLayoutGuide.bottomAnchor),
            searchPageContainer.widthAnchor.constraint(equalTo: swipeScrollView.frameLayoutGuide.widthAnchor),
            searchPageContainer.heightAnchor.constraint(equalTo: swipeScrollView.frameLayoutGuide.heightAnchor),

            // Chat page constraints
            chatPageContainer.leadingAnchor.constraint(equalTo: searchPageContainer.trailingAnchor),
            chatPageContainer.trailingAnchor.constraint(equalTo: swipeScrollView.contentLayoutGuide.trailingAnchor),
            chatPageContainer.topAnchor.constraint(equalTo: swipeScrollView.contentLayoutGuide.topAnchor),
            chatPageContainer.bottomAnchor.constraint(equalTo: swipeScrollView.contentLayoutGuide.bottomAnchor),
            chatPageContainer.widthAnchor.constraint(equalTo: swipeScrollView.frameLayoutGuide.widthAnchor),
            chatPageContainer.heightAnchor.constraint(equalTo: swipeScrollView.frameLayoutGuide.heightAnchor)
        ])
    }
    
    private func configureInitialPosition() {
        guard let parentView = swipeScrollView.superview else { return }

        let pageWidth = parentView.bounds.width
        swipeScrollView.contentSize = CGSize(width: pageWidth * 2, height: 0)
        updateScrollViewPosition(pageWidth: pageWidth, animated: false)
    }
    
    private func updateScrollViewPosition(pageWidth: CGFloat? = nil, animated: Bool) {
        guard let parentView = swipeScrollView.superview else { return }

        let pageWidth = pageWidth ?? parentView.bounds.width

        let targetX: CGFloat = switchBarHandler.currentToggleState == .search ? 0 : pageWidth
        swipeScrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
    }
    
    private func updateScrollProgress(_ progress: CGFloat) {
        scrollProgress = progress
        delegate?.swipeContainerManager(self, didUpdateScrollProgress: progress)
    }
}

// MARK: - UIScrollViewDelegate

extension SwipeContainerManager: UIScrollViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pageWidth = scrollView.frame.width
        guard pageWidth > 0 else { return }
        
        // Calculate progress (0 = search, 1 = aiChat)
        let progress = max(0, min(1, scrollView.contentOffset.x / pageWidth))
        updateScrollProgress(progress)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let pageWidth = scrollView.frame.width
        let currentPage = Int(scrollView.contentOffset.x / pageWidth)
        
        let newMode: TextEntryMode = currentPage == 0 ? .search : .aiChat
        
        if newMode != switchBarHandler.currentToggleState {
            delegate?.swipeContainerManager(self, didSwipeToMode: newMode)
        }
    }
}
