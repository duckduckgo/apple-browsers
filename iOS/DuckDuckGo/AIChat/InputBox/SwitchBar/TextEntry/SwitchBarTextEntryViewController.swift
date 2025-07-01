//
//  SwitchBarTextEntryViewController.swift
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

class SwitchBarTextEntryViewController: UIViewController {

    // MARK: - Properties
    let textEntryView: SwitchBarTextEntryView
    private let handler: SwitchBarHandling
    private let containerView = UIView()

    // Constraint references for dynamic sizing
    private var textEntryBottomConstraint: NSLayoutConstraint?

    private var cancellables = Set<AnyCancellable>()
    private var isExpanded = false
    private var showsActionView: Bool { handler.currentToggleState == .aiChat && isExpanded }

    // MARK: - Initialization
    init(handler: SwitchBarHandling) {
        self.handler = handler
        self.textEntryView = SwitchBarTextEntryView(handler: handler)
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
        self.view.layoutIfNeeded()
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func focusTextField() {
        textEntryView.becomeFirstResponder()
    }

    func unfocusTextField() {
        textEntryView.resignFirstResponder()
    }

    private func setupViews() {
        setupContainerViewAppearance()
        view.addSubview(containerView)

        containerView.addSubview(textEntryView)
        containerView.backgroundColor = UIColor(designSystemColor: .surface)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        textEntryView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupContainerViewAppearance() {

        containerView.layer.cornerRadius = 16
        containerView.layer.masksToBounds = false

        containerView.layer.shadowColor = UIColor.label.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOpacity = 0.1

        containerView.layer.borderColor = UIColor(designSystemColor: .accent).cgColor // TODO: observe trait collection changes
        containerView.layer.borderWidth = 2

        updateShadowPath()
    }

    private func updateShadowPath() {
        containerView.layer.shadowPath = UIBezierPath(
            roundedRect: containerView.bounds,
            cornerRadius: containerView.layer.cornerRadius
        ).cgPath
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateShadowPath()
    }


    private func setupConstraints() {
        textEntryBottomConstraint = textEntryView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        textEntryBottomConstraint?.priority = UILayoutPriority(999)
        textEntryBottomConstraint?.isActive = true

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 70),

            textEntryView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textEntryView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textEntryView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
    }

    // MARK: - Action Handlers
    private func handleWebSearchToggle() {
        handler.toggleForceWebSearch()
    }

    private func handleSend() {
        let currentText = handler.currentText
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handler.submitText(currentText)
            handler.clearText()
        }
    }

    // MARK: - Public Methods
    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textEntryView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return textEntryView.resignFirstResponder()
    }

    func selectAllText() {
        textEntryView.selectAllText()
    }
}
