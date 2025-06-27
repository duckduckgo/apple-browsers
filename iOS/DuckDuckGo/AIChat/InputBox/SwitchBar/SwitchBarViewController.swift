//
//  SwitchBarViewController.swift
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
import SwiftUI
import Combine
import DesignResourcesKitIcons

class SwitchBarViewController: UIViewController {

    private struct Constants {
        static let segmentedControlHeight: CGFloat = 36
        static let segmentedControlTopPadding: CGFloat = 20
        static let textEntryViewTopPadding: CGFloat = 16
        static let textEntryViewSidePadding: CGFloat = 16
        static let backButtonHorizontalPadding: CGFloat = 16
    }

    private let segmentedControl = UISegmentedControl(items: ["Search", "Duck.ai"])
    let textEntryViewController: SwitchBarTextEntryViewController
    let backButton = BrowserChromeButton(.secondary)

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

    private var collapsedStateConstraint: NSLayoutConstraint?
    private var expandedStateConstraint: NSLayoutConstraint?
    private var segmentedControlTopConstraint: NSLayoutConstraint?

    private var isExpanded = false

    // MARK: - Initialization
    init(switchBarHandler: SwitchBarHandling) {
        self.switchBarHandler = switchBarHandler
        self.textEntryViewController = SwitchBarTextEntryViewController(handler: switchBarHandler)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        setupSubscriptions()
        view.backgroundColor = .clear

        setExpanded(isExpanded)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseInOut]) {
            self.setExpanded(false)
            self.view.layoutIfNeeded()
        }
    }

    private func setupSubscriptions() {
        switchBarHandler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                let segmentIndex = newState == .search ? 0 : 1
                if self?.segmentedControl.selectedSegmentIndex != segmentIndex {
                    self?.segmentedControl.selectedSegmentIndex = segmentIndex
                }
                self?.updateLayouts()
            }
            .store(in: &cancellables)
    }

    private func updateLayouts() {
        self.view.layoutIfNeeded()
    }

    func focusTextField() {
        textEntryViewController.focusTextField()
    }

    func unfocusTextField() {
        textEntryViewController.unfocusTextField()
    }

    private func setupViews() {
        view.backgroundColor = UIColor.systemBackground

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlValueChanged), for: .valueChanged)
        segmentedControl.setContentHuggingPriority(.required, for: .horizontal)

        view.addSubview(segmentedControl)
        view.addSubview(backButton)

        addChild(textEntryViewController)
        view.addSubview(textEntryViewController.view)
        textEntryViewController.didMove(toParent: self)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        textEntryViewController.view.translatesAutoresizingMaskIntoConstraints = false

        backButton.setImage(DesignSystemImages.Glyphs.Size24.arrowLeft)
    }

    func setExpanded(_ isExpanded: Bool) {
        self.isExpanded = isExpanded

        if isExpanded {
            collapsedStateConstraint?.isActive = false
            segmentedControlTopConstraint?.isActive = true
            expandedStateConstraint?.isActive = true
        } else {
            expandedStateConstraint?.isActive = false
            segmentedControlTopConstraint?.isActive = false
            collapsedStateConstraint?.isActive = true
        }

        segmentedControl.alpha = isExpanded ? 1 : 0

        textEntryViewController.setExpanded(isExpanded)
    }

    private func setupConstraints() {

        collapsedStateConstraint = textEntryViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        expandedStateConstraint = textEntryViewController.view.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.textEntryViewTopPadding)
        
        segmentedControlTopConstraint = segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)

        // Create bottom constraint with lower priority to avoid conflicts with parent constraints
        let textEntryBottomConstraint = textEntryViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        textEntryBottomConstraint.priority = UILayoutPriority(999) // High priority but not required

        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            segmentedControl.heightAnchor.constraint(equalToConstant: Constants.segmentedControlHeight),

            textEntryViewController.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Constants.textEntryViewSidePadding),
            textEntryViewController.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Constants.textEntryViewSidePadding),
            textEntryBottomConstraint,

            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Constants.backButtonHorizontalPadding),
            backButton.centerYAnchor.constraint(equalTo: segmentedControl.centerYAnchor)
        ])
    }

    // MARK: - Actions
    @objc private func segmentedControlValueChanged() {
        let selectedIndex = segmentedControl.selectedSegmentIndex
        let newMode: TextEntryMode = selectedIndex == 0 ? .search : .aiChat

        switchBarHandler.setToggleState(newMode)
    }
}
