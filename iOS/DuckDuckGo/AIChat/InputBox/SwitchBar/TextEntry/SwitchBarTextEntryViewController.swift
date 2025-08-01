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
    private let textEntryView: SwitchBarTextEntryView
    private let handler: SwitchBarHandling
    private let containerView = CompositeShadowView()

    private var cancellables = Set<AnyCancellable>()
    var isExpandable: Bool {
        get { textEntryView.isExpandable }
        set { textEntryView.isExpandable = newValue }
    }

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
        setupPasteAndGo()
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

        containerView.translatesAutoresizingMaskIntoConstraints = false
        textEntryView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupContainerViewAppearance() {

        containerView.layer.cornerRadius = Metrics.containerCornerRadius
        containerView.layer.masksToBounds = false

        textEntryView.layer.cornerRadius = Metrics.containerCornerRadius
        textEntryView.layer.masksToBounds = true
        
        containerView.backgroundColor = UIColor(designSystemColor: .urlBar)
        containerView.applyActiveShadow()
    }

    private func setupConstraints() {

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            textEntryView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textEntryView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textEntryView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textEntryView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    private func setupPasteAndGo() {
        let title = UserText.actionPasteAndGo
        UIMenuController.shared.menuItems = [UIMenuItem(title: title, action: #selector(self.pasteURLAndGo))]
    }

    // MARK: - Action Handlers
    @objc private func pasteURLAndGo(sender: UIMenuItem) {
        guard let pastedText = UIPasteboard.general.string,
              !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        handler.updateCurrentText(pastedText)
        handleSend()
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
        static let containerCornerRadius: CGFloat = 16
    }
}
