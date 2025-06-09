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

class SwitchBarViewController: UIViewController {

    // MARK: - Properties
    private let segmentedControl = UISegmentedControl(items: ["Search", "Duck.ai"])
    private let textEntryViewController: SwitchBarTextEntryViewController

    private let switchBarHandler: SwitchBarHandling
    private var cancellables = Set<AnyCancellable>()

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
        self.textEntryViewController.updateConstraintsForCurrentMode()

        //TODO: Fix issue
        //        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: {
        //            self.view.layoutIfNeeded()
        //        })
    }

    private func setupViews() {
        view.backgroundColor = UIColor.systemBackground

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlValueChanged), for: .valueChanged)
        segmentedControl.setContentHuggingPriority(.required, for: .horizontal)
        
        view.addSubview(segmentedControl)

        addChild(textEntryViewController)
        view.addSubview(textEntryViewController.view)
        textEntryViewController.didMove(toParent: self)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        textEntryViewController.view.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            segmentedControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            segmentedControl.heightAnchor.constraint(equalToConstant: 36),

            textEntryViewController.view.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 16),
            textEntryViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textEntryViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textEntryViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Actions
    @objc private func segmentedControlValueChanged() {
        let selectedIndex = segmentedControl.selectedSegmentIndex
        let newMode: TextEntryMode = selectedIndex == 0 ? .search : .aiChat

        switchBarHandler.setToggleState(newMode)
    }
}
