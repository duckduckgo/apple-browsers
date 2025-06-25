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
    private var actionViewController: UIHostingController<SwitchBarActionView>?
    private let containerView = UIView()

    // Constraint references for dynamic sizing
    private var actionViewHeightConstraint: NSLayoutConstraint?
    private var actionViewBottomConstraint: NSLayoutConstraint?
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
        setupSubscriptions()
        updateConstraintsForCurrentMode()
        self.view.layoutIfNeeded()
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        updateConstraintsForCurrentMode()
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
        setupActionView()

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

    private func setupActionView() {
        let hasText = !handler.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let actionView = SwitchBarActionView(
            hasText: hasText,
            forceWebSearchEnabled: handler.forceWebSearch,
            onWebSearchToggle: { [weak self] in
                self?.handleWebSearchToggle()
            },
            onSend: { [weak self] in
                self?.handleSend()
            }
        )

        actionViewController = UIHostingController(rootView: actionView)

        if let actionVC = actionViewController {
            addChild(actionVC)
            containerView.addSubview(actionVC.view)
            actionVC.didMove(toParent: self)

            actionVC.view.backgroundColor = UIColor.clear
            actionVC.view.translatesAutoresizingMaskIntoConstraints = false

            let isSearchMode = handler.currentToggleState == .search
            actionVC.view.alpha = isSearchMode ? 0 : 1
        }
    }

    private func updateActionView() {
        let hasText = !handler.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let updatedActionView = SwitchBarActionView(
            hasText: hasText,
            forceWebSearchEnabled: handler.forceWebSearch,
            onWebSearchToggle: { [weak self] in
                self?.handleWebSearchToggle()
            },
            onSend: { [weak self] in
                self?.handleSend()
            }
        )

        actionViewController?.rootView = updatedActionView
    }

    private func setupConstraints() {
        guard let actionView = actionViewController?.view else { return }

        actionViewBottomConstraint = actionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        textEntryBottomConstraint = textEntryView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        textEntryBottomConstraint?.priority = UILayoutPriority(999)

        let spacingConstraint = actionView.topAnchor.constraint(equalTo: textEntryView.bottomAnchor, constant: 8)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            textEntryView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textEntryView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textEntryView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            actionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            actionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            spacingConstraint
        ])

        updateConstraintsForCurrentMode()
    }

    func updateConstraintsForCurrentMode() {
        if showsActionView {
            textEntryBottomConstraint?.isActive = false
            actionViewBottomConstraint?.isActive = true
            actionViewController?.view.alpha = 1
        } else {
            actionViewBottomConstraint?.isActive = false
            textEntryBottomConstraint?.isActive = true
            actionViewController?.view.alpha = 0
        }
    }

    private func setupSubscriptions() {
        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActionView()
            }
            .store(in: &cancellables)

        handler.forceWebSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActionView()
            }
            .store(in: &cancellables)
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
