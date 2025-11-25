//
//  FadeoutContainerViewController.swift
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

/// Protocol for handling fadeout container events
protocol FadeoutContainerViewControllerDelegate: AnyObject {
    func fadeoutContainerViewController(_ controller: FadeoutContainerViewController, didTransitionToMode mode: TextEntryMode)
    func fadeoutContainerViewController(_ controller: FadeoutContainerViewController, didUpdateTransitionProgress progress: CGFloat)
}

final class FadeoutContainerViewController: UIViewController {

    weak var delegate: FadeoutContainerViewControllerDelegate?

    // MARK: - Transition Progress
    @Published private(set) var transitionProgress: CGFloat = 0.0
    var transitionProgressPublisher: AnyPublisher<CGFloat, Never> {
        $transitionProgress.eraseToAnyPublisher()
    }

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements

    private(set) var searchPageContainer: UIView!
    private(set) var chatPageContainer: UIView!

    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        super.init(nibName: nil, bundle: nil)
        setupBindings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        createContainerViews()
        setupConstraints()
        setupSwipeGestures()
        configureInitialState()
    }

    func setMode(_ mode: TextEntryMode) {
        updateVisibility(animated: true)
    }

    // MARK: - Private

    private func setupBindings() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateVisibility(animated: true)
            }
            .store(in: &cancellables)
    }

    private func createContainerViews() {
        searchPageContainer = UIView()
        searchPageContainer.backgroundColor = .yellow
        searchPageContainer.translatesAutoresizingMaskIntoConstraints = false

        chatPageContainer = UIView()
//        chatPageContainer.backgroundColor = .green
        chatPageContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchPageContainer)
        view.addSubview(chatPageContainer)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Search page constraints (full size)
            searchPageContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchPageContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchPageContainer.topAnchor.constraint(equalTo: view.topAnchor),
            searchPageContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Chat page constraints (full size, overlaid)
            chatPageContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatPageContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatPageContainer.topAnchor.constraint(equalTo: view.topAnchor),
            chatPageContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupSwipeGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)
    }

    @objc private func handleSwipeGesture(_ gesture: UISwipeGestureRecognizer) {
        let currentMode = switchBarHandler.currentToggleState

        switch gesture.direction {
        case .left:
            // Swipe left: go to Duck.ai (if currently in Search mode)
            if currentMode == .search {
                delegate?.fadeoutContainerViewController(self, didTransitionToMode: .aiChat)
            }
        case .right:
            // Swipe right: go to Search (if currently in Duck.ai mode)
            if currentMode == .aiChat {
                delegate?.fadeoutContainerViewController(self, didTransitionToMode: .search)
            }
        default:
            break
        }
    }

    private func configureInitialState() {
        let isSearchMode = switchBarHandler.currentToggleState == .search
        searchPageContainer.alpha = isSearchMode ? 1.0 : 0.0
        chatPageContainer.alpha = isSearchMode ? 0.0 : 1.0
        transitionProgress = isSearchMode ? 0.0 : 1.0
    }

    private func updateVisibility(animated: Bool) {
        let isSearchMode = switchBarHandler.currentToggleState == .search
        let targetProgress: CGFloat = isSearchMode ? 0.0 : 1.0

        // Update progress immediately so the toggle moves right away
        updateTransitionProgress(targetProgress)

        let animations = {
            self.searchPageContainer.alpha = isSearchMode ? 1.0 : 0.0
            self.chatPageContainer.alpha = isSearchMode ? 0.0 : 1.0
        }

        let completion: (Bool) -> Void = { [weak self] finished in
            guard let self, finished else { return }
            let newMode: TextEntryMode = isSearchMode ? .search : .aiChat
            self.delegate?.fadeoutContainerViewController(self, didTransitionToMode: newMode)
        }

        if animated {
            UIView.animate(withDuration: 0.25, animations: animations, completion: completion)
        } else {
            animations()
            completion(true)
        }
    }

    private func updateTransitionProgress(_ progress: CGFloat) {
        transitionProgress = progress
        delegate?.fadeoutContainerViewController(self, didUpdateTransitionProgress: progress)
    }
}

