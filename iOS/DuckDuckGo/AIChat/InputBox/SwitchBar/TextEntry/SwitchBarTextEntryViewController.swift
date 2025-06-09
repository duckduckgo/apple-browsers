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
    private let handler: SwitchBarHandling
    private let textEntryView: SwitchBarTextEntryView
    private var actionViewController: UIHostingController<SwitchBarActionView>?
    private let containerView = UIView()

    // Constraint references for dynamic sizing
    private var actionViewHeightConstraint: NSLayoutConstraint?

    private var cancellables = Set<AnyCancellable>()

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
        updateActionViewVisibility()
    }

    private func setupViews() {
        setupContainerViewAppearance()
        view.addSubview(containerView)

        containerView.addSubview(textEntryView)
        containerView.backgroundColor = .systemBackground
        setupActionView()

        containerView.translatesAutoresizingMaskIntoConstraints = false
        textEntryView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupContainerViewAppearance() {

        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = false

        containerView.layer.shadowColor = UIColor.label.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOpacity = 0.1

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
            onImageUpload: { [weak self] in
                self?.handleImageUpload()
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
            onImageUpload: { [weak self] in
                self?.handleImageUpload()
            },
            onSend: { [weak self] in
                self?.handleSend()
            }
        )

        actionViewController?.rootView = updatedActionView
    }

    private func setupConstraints() {
        guard let actionView = actionViewController?.view else { return }

        actionViewHeightConstraint = actionView.heightAnchor.constraint(equalToConstant: 60)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            textEntryView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textEntryView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textEntryView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            actionView.topAnchor.constraint(equalTo: textEntryView.bottomAnchor, constant: 8),
            actionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            actionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            actionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            actionViewHeightConstraint!
        ])

        updateConstraintsForCurrentMode()
    }

    func updateConstraintsForCurrentMode() {
        updateActionViewVisibility()

        let isSearchMode = handler.currentToggleState == .search
        let targetHeight: CGFloat = isSearchMode ? 0 : 60

        self.actionViewHeightConstraint?.constant = targetHeight
        self.actionViewController?.view.alpha = isSearchMode ? 0 : 1
    }

    private func setupSubscriptions() {

        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActionView()
            }
            .store(in: &cancellables)
    }

    private func updateActionViewVisibility() {
        actionViewController?.view.isHidden = handler.currentToggleState == .aiChat ? false : true
    }

    // MARK: - Action Handlers
    private func handleImageUpload() {
        // TODO: Implement image upload functionality
        print("Image upload tapped")
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
}
