//
//  FadeOutContainerViewController.swift
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
import Combine

protocol FadeOutContainerViewControllerDelegate: AnyObject {
    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didTransitionToMode mode: TextEntryMode)
    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didUpdateTransitionProgress progress: CGFloat)
    func fadeOutContainerViewControllerIsShowingSuggestions(_ controller: FadeOutContainerViewController) -> Bool
    /// Return true to keep the search page visible during duck.ai transition (URL fallback case).
    func fadeOutContainerViewControllerShouldKeepSearchVisible(_ controller: FadeOutContainerViewController) -> Bool
}

final class FadeOutContainerViewController: UIViewController {
    weak var delegate: FadeOutContainerViewControllerDelegate?

    @Published private(set) var transitionProgress: CGFloat = 0.0

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    private(set) var searchPageContainer: UIView!
    private(set) var chatPageContainer: UIView!

    var isSwipeEnabled: Bool = true {
        didSet { panGestureRecognizer?.isEnabled = isSwipeEnabled }
    }

    private var panGestureRecognizer: UIPanGestureRecognizer!
    private let swipeVelocityThreshold: CGFloat = 500
    private let swipeTranslationThreshold: CGFloat = 50

    private var displayLink: CADisplayLink?
    private var targetProgress: CGFloat = 0.0
    private var visibleMode: TextEntryMode?
    private var transitionID = 0

    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopDisplayLink()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createContainerViews()
        setupConstraints()
        setupSwipeGestures()
        configureInitialState()
        setupBindings()
    }

    func setMode(_ mode: TextEntryMode, animated: Bool = true) {
        updateVisibility(to: mode, animated: animated)
    }

    // MARK: - Private

    private func setupBindings() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                guard mode == self.switchBarHandler.currentToggleState else { return }
                self.updateVisibility(to: mode, animated: true)
            }
            .store(in: &cancellables)
    }

    private func createContainerViews() {
        searchPageContainer = UIView()
        searchPageContainer.translatesAutoresizingMaskIntoConstraints = false

        chatPageContainer = UIView()
        chatPageContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchPageContainer)
        view.addSubview(chatPageContainer)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            searchPageContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchPageContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchPageContainer.topAnchor.constraint(equalTo: view.topAnchor),
            searchPageContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            chatPageContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatPageContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatPageContainer.topAnchor.constraint(equalTo: view.topAnchor),
            chatPageContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupSwipeGestures() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.delegate = self
        panGestureRecognizer.isEnabled = isSwipeEnabled
        view.addGestureRecognizer(panGestureRecognizer)
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }

        let velocity = gesture.velocity(in: view)
        let translation = gesture.translation(in: view)
        let currentMode = switchBarHandler.currentToggleState

        let isHorizontalSwipe = abs(velocity.x) > abs(velocity.y)
        guard isHorizontalSwipe else { return }

        let meetsVelocityThreshold = abs(velocity.x) > swipeVelocityThreshold
        let meetsTranslationThreshold = abs(translation.x) > swipeTranslationThreshold

        guard meetsVelocityThreshold || meetsTranslationThreshold else { return }

        if velocity.x < 0 && currentMode == .search {
            delegate?.fadeOutContainerViewController(self, didTransitionToMode: .aiChat)
        } else if velocity.x > 0 && currentMode == .aiChat {
            delegate?.fadeOutContainerViewController(self, didTransitionToMode: .search)
        }
    }

    private func configureInitialState() {
        let currentMode = switchBarHandler.currentToggleState
        let isSearchMode = currentMode == .search
        searchPageContainer.alpha = isSearchMode ? 1.0 : 0.0
        chatPageContainer.alpha = isSearchMode ? 0.0 : 1.0
        transitionProgress = isSearchMode ? 0.0 : 1.0
        visibleMode = currentMode
    }

    private func updateVisibility(to mode: TextEntryMode, animated: Bool) {
        guard searchPageContainer != nil, chatPageContainer != nil else { return }
        guard visibleMode != mode else { return }

        visibleMode = mode
        transitionID += 1
        let currentTransitionID = transitionID
        let isSearchMode = mode == .search
        let targetProgress = isSearchMode ? 0.0 : 1.0
        self.targetProgress = targetProgress

        let isShowingSuggestions = delegate?.fadeOutContainerViewControllerIsShowingSuggestions(self) ?? false
        let shouldHideSearchImmediately = !isSearchMode && isShowingSuggestions
        let keepSearchVisible = delegate?.fadeOutContainerViewControllerShouldKeepSearchVisible(self) ?? false

        if shouldHideSearchImmediately && !keepSearchVisible {
            searchPageContainer.alpha = 0.0
        }

        let animations = {
            if !shouldHideSearchImmediately && !keepSearchVisible {
                self.searchPageContainer.alpha = isSearchMode ? 1.0 : 0.0
            }
            if !keepSearchVisible {
                self.chatPageContainer.alpha = isSearchMode ? 0.0 : 1.0
            }
        }

        let completion: (Bool) -> Void = { [weak self] finished in
            guard let self, self.transitionID == currentTransitionID else { return }

            self.stopDisplayLink()
            guard finished else { return }

            self.updateTransitionProgress(targetProgress)
            self.delegate?.fadeOutContainerViewController(self, didTransitionToMode: mode)
        }

        if animated {
            startDisplayLink()
            UIView.animate(withDuration: 0.25, animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }

    // MARK: - Display Link for Smooth Toggle transitions

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkTick() {
        guard let presentationLayer = chatPageContainer.layer.presentation() else { return }

        let currentProgress = CGFloat(presentationLayer.opacity)
        updateTransitionProgress(currentProgress)
    }

    private func updateTransitionProgress(_ progress: CGFloat) {
        transitionProgress = progress
        delegate?.fadeOutContainerViewController(self, didUpdateTransitionProgress: progress)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension FadeOutContainerViewController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        let velocity = panGesture.velocity(in: view)
        // Only begin if horizontal velocity is significantly greater than vertical
        return abs(velocity.x) > abs(velocity.y) * 1.5
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't recognize simultaneously with scroll views
        // (We installSuggestionsTray in searchPageContainer and they can conflict with each other)
        if otherGestureRecognizer.view is UIScrollView {
            return false
        }
        return true
    }
}
