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
import UIComponents

class SwitchBarTextEntryViewController: UIViewController {

    // MARK: - Properties
    let textEntryView: SwitchBarTextEntryView
    private let handler: SwitchBarHandling
    private let containerView = CompositeShadowView()
    private let borderOverlayView = UIView()

    // Constraint references for dynamic sizing
    private var textEntryBottomConstraint: NSLayoutConstraint?
    private var containerHeightConstraint: NSLayoutConstraint?
    private var containerStaticHeightConstraint: NSLayoutConstraint?

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
        
        containerStaticHeightConstraint?.isActive = !expanded
        containerHeightConstraint?.isActive = expanded
        textEntryView.alpha = expanded ? 1 : 0
    }

    func focusTextField() {
        textEntryView.becomeFirstResponder()
    }

    func unfocusTextField() {
        textEntryView.resignFirstResponder()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            borderOverlayView.layer.borderColor = UIColor(Color(designSystemColor: .accent)).cgColor
        }
    }

    private func setupViews() {
        setupContainerViewAppearance()
        setUpBorderOverlayAppearance()

        view.addSubview(containerView)
        view.addSubview(borderOverlayView)

        containerView.addSubview(textEntryView)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        textEntryView.translatesAutoresizingMaskIntoConstraints = false
        borderOverlayView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setUpBorderOverlayAppearance() {
        borderOverlayView.layer.cornerRadius = Metrics.borderCornerRadius
        borderOverlayView.layer.masksToBounds = true

        borderOverlayView.layer.borderColor = UIColor(designSystemColor: .accent).cgColor
        borderOverlayView.layer.borderWidth = Metrics.borderWidth
    }

    private func setupContainerViewAppearance() {

        containerView.layer.cornerRadius = Metrics.containerCornerRadius
        containerView.layer.masksToBounds = false

        containerView.backgroundColor = UIColor(designSystemColor: .surface)
        containerView.applyActiveShadow()
    }

    private func setupConstraints() {
        textEntryBottomConstraint = textEntryView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        textEntryBottomConstraint?.priority = UILayoutPriority(999)
        textEntryBottomConstraint?.isActive = true

        containerHeightConstraint = containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 70).withPriority(.init(999))
        containerStaticHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 44)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            borderOverlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: -Metrics.borderWidth),
            borderOverlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: Metrics.borderWidth),
            borderOverlayView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -Metrics.borderWidth),
            borderOverlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: Metrics.borderWidth),

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

    private struct Metrics {
        static let borderWidth: CGFloat = 2
        static let borderCornerRadius: CGFloat = 18
        static let containerCornerRadius: CGFloat = 16
    }
}
